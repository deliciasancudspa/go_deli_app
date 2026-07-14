-- ============================================================================
-- MOTOR DE DESPACHO AUTOMÁTICO DE RIDERS (server-side, robusto)
-- ============================================================================
-- Reemplaza la búsqueda de rider que corría en el navegador del aliado.
-- Corre en la base de datos y se dispara por:
--   • start_dispatch(order_id)  -> cuando el aliado pulsa "Llamar rider"
--   • trigger en order_rejections -> cuando un rider rechaza
--   • pg_cron (dispatch_tick)   -> para timeouts (rider ignora la oferta)
-- Cada oferta se inserta en `notifications` (type=order_offer), lo que dispara
-- el push vía la Edge Function notify-rider ya existente.
--
-- Lógica:
--   Ronda = 1 pasada por todos los riders elegibles.
--   FASE 1 (libres):   riders aprobados+online con 0 pedidos activos,
--                      ordenados por CERCANÍA a la tienda. Uno por uno.
--   FASE 2 (en ruta):  si ningún libre acepta, riders con pedido on_the_way,
--                      por pedido más antiguo. Si aceptan, el pedido queda
--                      EN COLA (is_queued) tras su pedido en ruta.
--   Si nadie acepta la ronda completa -> avisa al admin y REINICIA la ronda
--   (hasta max rondas). Sin riders online -> needs_manual.
-- ============================================================================

-- 1. Columnas de estado de despacho ------------------------------------------
-- NOTA: current_offer_rider_id NO tiene FK constraint hacia deliverers.
-- Si tuviera FK, PostgREST fallaría con PGRST201 al embedear "deliverers"
-- porque habría 2 FK entre orders y deliverers (deliverer_id + esta).
-- Ver migración 20260713000002_fix_double_fk_tracking.sql.
alter table public.orders add column if not exists current_offer_rider_id  uuid;
alter table public.orders add column if not exists current_offer_expires_at timestamptz;
alter table public.orders add column if not exists dispatch_phase           text;      -- 'free' | 'in_route'
alter table public.orders add column if not exists dispatch_round           int not null default 0;
alter table public.orders add column if not exists is_queued                boolean not null default false;

-- 2. Registro de intentos por ronda ------------------------------------------
create table if not exists public.order_dispatch_attempts (
  id         bigint generated always as identity primary key,
  order_id   uuid not null references public.orders(id) on delete cascade,
  rider_id   uuid not null references public.deliverers(id) on delete cascade,
  round      int  not null,
  kind       text not null default 'offered',   -- offered | rejected | ignored
  created_at timestamptz not null default now()
);
create index if not exists idx_oda_order_round on public.order_dispatch_attempts(order_id, round);
alter table public.order_dispatch_attempts enable row level security;
drop policy if exists oda_select on public.order_dispatch_attempts;
create policy oda_select on public.order_dispatch_attempts for select to authenticated using (true);

-- 3. Distancia haversine en metros -------------------------------------------
create or replace function public.haversine_m(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
) returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- 4. Aviso al admin ----------------------------------------------------------
create or replace function public.notify_admin_no_rider(p_order_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into notifications(target, type, emoji, title, message, is_read)
  values ('admin', 'dispatch_alert', '🚨', 'Despacho sin rider',
          'Pedido #' || upper(substr(p_order_id::text, 1, 8)) || ': ' || p_reason, false);
end $$;

-- 5. Ofrecer el pedido al siguiente mejor rider ------------------------------
create or replace function public.dispatch_offer_next(p_order_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_order      orders%rowtype;
  v_store_lat  double precision;
  v_store_lng  double precision;
  v_rider      uuid;
  v_round      int;
  v_phase      text;
  v_timeout    int := 45;   -- segundos para responder una oferta
  v_max_rounds int := 3;    -- rondas completas antes de needs_manual
begin
  perform set_config('dispatch.bypass', '1', true);
  select * into v_order from orders where id = p_order_id;
  if not found then return 'not_found'; end if;
  if v_order.rider_search_status is distinct from 'searching' then return 'not_searching'; end if;
  if v_order.deliverer_id is not null then return 'already_assigned'; end if;

  select s.lat, s.lng into v_store_lat, v_store_lng from stores s where s.id = v_order.store_id;

  v_round := greatest(coalesce(v_order.dispatch_round, 0), 1);
  if v_order.dispatch_round is distinct from v_round then
    update orders set dispatch_round = v_round where id = p_order_id;
  end if;

  -- FASE 1: riders LIBRES (0 pedidos activos), sin oferta pendiente, no
  -- intentados esta ronda, MISMA COMUNA, dentro de 10km, ordenados por CERCANÍA.
  -- Si la tienda no tiene commune_id, o el rider no tiene commune_id asignado,
  -- se permite el matching (backward compat + riders sin ubicación previa).
  select d.id into v_rider
  from deliverers d
  where d.status = 'approved' and d.is_online = true
    and (v_order.commune_id is null or d.commune_id is null or d.commune_id = v_order.commune_id)
    and (v_store_lat is null or v_store_lng is null
         or d.current_lat is null or d.current_lng is null
         or haversine_m(v_store_lat, v_store_lng, d.current_lat, d.current_lng) <= 10000)
    and not exists (select 1 from order_dispatch_attempts a
                    where a.order_id = p_order_id and a.round = v_round and a.rider_id = d.id)
    and not exists (select 1 from orders o2
                    where o2.deliverer_id = d.id and o2.status in ('assigned','picked_up','on_the_way'))
    and not exists (select 1 from orders o3
                    where o3.current_offer_rider_id = d.id and o3.current_offer_expires_at > now())
  order by case when v_store_lat is null or d.current_lat is null then 1 else 0 end,
           haversine_m(v_store_lat, v_store_lng, d.current_lat, d.current_lng) asc
  limit 1;
  v_phase := 'free';

  -- FASE 2: riders EN RUTA (pedido on_the_way), MISMA COMUNA, dentro de 10km,
  -- por pedido más antiguo, que no tengan ya un pedido en cola.
  if v_rider is null then
    select d.id into v_rider
    from deliverers d
    where d.status = 'approved' and d.is_online = true
      and (v_order.commune_id is null or d.commune_id is null or d.commune_id = v_order.commune_id)
      and (v_store_lat is null or v_store_lng is null
           or d.current_lat is null or d.current_lng is null
           or haversine_m(v_store_lat, v_store_lng, d.current_lat, d.current_lng) <= 10000)
      and not exists (select 1 from order_dispatch_attempts a
                      where a.order_id = p_order_id and a.round = v_round and a.rider_id = d.id)
      and not exists (select 1 from orders o3
                      where o3.current_offer_rider_id = d.id and o3.current_offer_expires_at > now())
      and not exists (select 1 from orders o4
                      where o4.deliverer_id = d.id and o4.is_queued = true
                        and o4.status in ('assigned','picked_up','on_the_way'))
      and exists (select 1 from orders o5
                  where o5.deliverer_id = d.id and o5.status = 'on_the_way')
    order by (select min(o6.updated_at) from orders o6
              where o6.deliverer_id = d.id and o6.status = 'on_the_way') asc
    limit 1;
    v_phase := 'in_route';
  end if;

  -- Hay rider al que ofrecer
  if v_rider is not null then
    update orders set
      current_offer_rider_id   = v_rider,
      current_offer_expires_at = now() + make_interval(secs => v_timeout),
      dispatch_phase           = v_phase,
      is_queued                = (v_phase = 'in_route')
    where id = p_order_id;

    insert into order_dispatch_attempts(order_id, rider_id, round, kind)
    values (p_order_id, v_rider, v_round, 'offered');

    insert into notifications(target, type, emoji, title, message, is_read, data)
    select v_rider::text, 'order_offer', '🛵', 'Nuevo pedido disponible',
           coalesce(s.emoji,'🍽️') || ' ' || coalesce(s.name,'Tienda') || ' — ' || coalesce(o.delivery_address,''),
           false,
           jsonb_build_object(
             'order_id', p_order_id,
             'store_name', s.name, 'store_emoji', s.emoji,
             'delivery_address', o.delivery_address,
             'delivery_reference', o.delivery_reference,
             'total', o.total, 'payment_method', o.payment_method,
             'rider_fee', o.rider_fee,
             'distance_km', case when o.delivery_distance is not null
                                 then round((o.delivery_distance/1000.0)::numeric, 1)::text else null end,
             'queued', (v_phase = 'in_route')
           )
    from orders o left join stores s on s.id = o.store_id
    where o.id = p_order_id;

    return 'offered_' || v_phase;
  end if;

  -- Nadie disponible esta ronda --------------------------------------------
  if not exists (select 1 from deliverers d where d.status = 'approved' and d.is_online = true) then
    update orders set rider_search_status = 'needs_manual',
                      current_offer_rider_id = null, current_offer_expires_at = null
    where id = p_order_id;
    perform notify_admin_no_rider(p_order_id, 'Sin repartidores en línea');
    return 'needs_manual_no_riders';
  end if;

  -- Todos los elegibles ya fueron consultados esta ronda -> avisar y reiniciar
  perform notify_admin_no_rider(p_order_id, 'Nadie aceptó (ronda ' || v_round || ')');
  if v_round >= v_max_rounds then
    update orders set rider_search_status = 'needs_manual',
                      current_offer_rider_id = null, current_offer_expires_at = null
    where id = p_order_id;
    return 'needs_manual_max_rounds';
  end if;

  update orders set dispatch_round = v_round + 1 where id = p_order_id;
  return public.dispatch_offer_next(p_order_id);   -- nueva ronda desde fase libres
end $$;

-- 6. Iniciar el despacho (lo llama el aliado) --------------------------------
create or replace function public.start_dispatch(p_order_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_is_store boolean;
begin
  perform set_config('dispatch.bypass', '1', true);
  -- Solo la tienda dueña del pedido o un admin pueden iniciar el despacho
  if not (public.is_admin() or exists (
            select 1 from orders o where o.id = p_order_id
              and o.store_id in (select public.my_store_ids()))) then
    return 'forbidden';
  end if;

  -- Validar que la distancia del delivery no exceda el máximo configurado
  if exists (
    select 1 from orders o, lateral (
      select coalesce((value::jsonb->>'max_distance_km')::float, 8.0) as max_km
      from config where key = 'delivery_fees'
    ) c
    where o.id = p_order_id
      and o.delivery_distance is not null
      and o.delivery_distance > (c.max_km * 1000)
  ) then
    return 'out_of_range';
  end if;

  update orders set
    rider_search_status     = 'searching',
    rider_search_started_at = now(),
    deliverer_id            = null,
    current_offer_rider_id  = null,
    current_offer_expires_at= null,
    dispatch_phase          = null,
    dispatch_round          = 1,
    is_queued               = false
  where id = p_order_id;

  delete from order_dispatch_attempts where order_id = p_order_id;
  return public.dispatch_offer_next(p_order_id);
end $$;
grant execute on function public.start_dispatch(uuid) to authenticated;

-- 7. Aceptar la oferta (lo llama el rider) -----------------------------------
create or replace function public.accept_offer(p_order_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_rider uuid; v_n int;
begin
  perform set_config('dispatch.bypass', '1', true);
  v_rider := public.my_rider_id();
  if v_rider is null then return false; end if;

  update orders set
    status                   = 'assigned',
    rider_search_status      = 'assigned',
    deliverer_id             = v_rider,
    current_offer_rider_id   = null,
    current_offer_expires_at = null,
    pickup_code   = coalesce(pickup_code,   upper(substr(md5(random()::text), 1, 4))),
    delivery_code = coalesce(delivery_code, upper(substr(md5(random()::text), 1, 4)))
  where id = p_order_id
    and current_offer_rider_id = v_rider
    and rider_search_status = 'searching'
    and deliverer_id is null
    and status not in ('delivered','cancelled','returned');

  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;
grant execute on function public.accept_offer(uuid) to authenticated;

-- 8. Trigger: rider rechaza -> registrar y ofrecer al siguiente --------------
create or replace function public.on_rider_rejection()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_round int;
begin
  perform set_config('dispatch.bypass', '1', true);
  select greatest(coalesce(dispatch_round,1),1) into v_round from orders where id = NEW.order_id;
  insert into order_dispatch_attempts(order_id, rider_id, round, kind)
  values (NEW.order_id, NEW.rider_id, v_round, 'rejected');

  update orders set current_offer_rider_id = null, current_offer_expires_at = null
  where id = NEW.order_id and current_offer_rider_id = NEW.rider_id;

  if exists (select 1 from orders where id = NEW.order_id and rider_search_status = 'searching') then
    perform public.dispatch_offer_next(NEW.order_id);
  end if;
  return NEW;
end $$;

drop trigger if exists trg_rider_rejection on public.order_rejections;
create trigger trg_rider_rejection after insert on public.order_rejections
for each row execute function public.on_rider_rejection();

-- 9. Tick periódico (pg_cron): timeouts de ofertas ignoradas ------------------
create or replace function public.dispatch_tick()
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  perform set_config('dispatch.bypass', '1', true);
  -- Ofertas expiradas (rider ignoró): marcar ignored, liberar y ofrecer siguiente
  for r in
    select id, current_offer_rider_id, greatest(coalesce(dispatch_round,1),1) as round
    from orders
    where rider_search_status = 'searching'
      and current_offer_rider_id is not null
      and current_offer_expires_at is not null
      and current_offer_expires_at <= now()
  loop
    insert into order_dispatch_attempts(order_id, rider_id, round, kind)
    values (r.id, r.current_offer_rider_id, r.round, 'ignored');
    update orders set current_offer_rider_id = null, current_offer_expires_at = null where id = r.id;
    perform public.dispatch_offer_next(r.id);
  end loop;

  -- Pedidos en búsqueda sin oferta activa (recién iniciados o reactivados)
  for r in
    select id from orders
    where rider_search_status = 'searching'
      and current_offer_rider_id is null and deliverer_id is null
  loop
    perform public.dispatch_offer_next(r.id);
  end loop;
end $$;

-- 10. Programar el tick con pg_cron ------------------------------------------
-- (En Supabase: Database -> Extensions -> habilitar pg_cron, o el create de abajo)
create extension if not exists pg_cron;
-- Ejecuta dispatch_tick cada minuto. pg_cron NO soporta sub-minutos ('15 seconds'),
-- así que usamos el formato cron estándar. El timeout real de oferta es 45s, pero
-- ejecutar cada 60s es aceptable: la diferencia máxima es 15s adicionales.
-- Para mejor granularidad se puede usar un scheduler externo (Edge Function + cron).
select cron.unschedule('godeli-dispatch-tick')
  where exists (select 1 from cron.job where jobname = 'godeli-dispatch-tick');
select cron.schedule('godeli-dispatch-tick', '* * * * *', $$ select public.dispatch_tick(); $$);
