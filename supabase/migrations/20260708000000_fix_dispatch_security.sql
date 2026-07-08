-- ============================================================================
-- Fix: error de seguridad "order_rider_search_status_check" en GoRider al
-- rechazar/auto-rechazar solicitudes de viaje.
--
-- Problemas corregidos:
-- 1. dispatch_offer_next no seteaba dispatch.bypass (se perdió en migración
--    de filtro por comuna), causando que check_order_update_columns bloqueara
--    los UPDATEs a orders desde el trigger de rechazo.
-- 2. CHECK constraint order_rider_search_status_check posiblemente incompleto:
--    se asegura que incluya todos los valores válidos usados por el motor de
--    despacho, admin, y aliados.
-- 3. Agregar política INSERT en order_dispatch_attempts como defensa en
--    profundidad (los inserts vía security definer no la necesitan, pero
--    previene errores si cambia el owner de la función).
-- ============================================================================

-- 1. Re-crear dispatch_offer_next con dispatch.bypass --------------------------
create or replace function public.dispatch_offer_next(p_order_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_order      orders%rowtype;
  v_store_lat  double precision;
  v_store_lng  double precision;
  v_rider      uuid;
  v_round      int;
  v_phase      text;
  v_timeout    int := 45;
  v_max_rounds int := 3;
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

  -- FASE 1: riders LIBRES, MISMA COMUNA, ≤10km, ordenados por CERCANÍA.
  select d.id into v_rider
  from deliverers d
  where d.status = 'approved' and d.is_online = true
    and (v_order.commune_id is null or d.commune_id = v_order.commune_id)
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

  -- FASE 2: riders EN RUTA, MISMA COMUNA, ≤10km, por pedido más antiguo.
  if v_rider is null then
    select d.id into v_rider
    from deliverers d
    where d.status = 'approved' and d.is_online = true
      and (v_order.commune_id is null or d.commune_id = v_order.commune_id)
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

  -- Nadie disponible esta ronda
  if not exists (select 1 from deliverers d where d.status = 'approved' and d.is_online = true) then
    update orders set rider_search_status = 'needs_manual',
                      current_offer_rider_id = null, current_offer_expires_at = null
    where id = p_order_id;
    perform notify_admin_no_rider(p_order_id, 'Sin repartidores en línea');
    return 'needs_manual_no_riders';
  end if;

  -- Nadie disponible en la comuna / dentro de 10km esta ronda
  if not exists (
    select 1 from deliverers d
    where d.status = 'approved' and d.is_online = true
      and (v_order.commune_id is null or d.commune_id = v_order.commune_id)
      and (v_store_lat is null or v_store_lng is null
           or d.current_lat is null or d.current_lng is null
           or haversine_m(v_store_lat, v_store_lng, d.current_lat, d.current_lng) <= 10000)
  ) then
    update orders set rider_search_status = 'needs_manual',
                      current_offer_rider_id = null, current_offer_expires_at = null
    where id = p_order_id;
    perform notify_admin_no_rider(p_order_id, 'Sin riders en la comuna o a menos de 10km');
    return 'needs_manual_no_riders_commune';
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
  return public.dispatch_offer_next(p_order_id);
end $$;


-- 2. Corregir CHECK constraint de rider_search_status --------------------------
-- Asegura que todos los valores usados en el sistema sean válidos.
-- Valores del motor de despacho: searching, assigned, needs_manual
-- Valores del admin/aliados:     cancelled, external
-- Valor inicial (sin despacho):  NULL
do $$
begin
  -- Eliminar ambas variantes del constraint (con y sin 's')
  if exists (
    select 1 from pg_constraint
    where conname = 'order_rider_search_status_check'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders drop constraint order_rider_search_status_check;
  end if;

  if exists (
    select 1 from pg_constraint
    where conname = 'orders_rider_search_status_check'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders drop constraint orders_rider_search_status_check;
  end if;

  -- Crear el constraint con todos los valores válidos
  alter table public.orders add constraint order_rider_search_status_check
  check (rider_search_status is null
      or rider_search_status in (
          'idle',          -- sin búsqueda activa (valor legacy usado por app rider)
          'searching',     -- motor de despacho buscando rider
          'assigned',      -- rider aceptó / fue asignado
          'needs_manual',  -- sin riders disponibles, necesita intervención manual
          'cancelled',     -- admin canceló el despacho
          'external'       -- rider externo asignado manualmente
      ));
end $$;


-- 3. Agregar política INSERT en order_dispatch_attempts ------------------------
-- (defensa en profundidad: los inserts son vía security definer, pero si cambia
--  el owner de la función, esta política previene errores de RLS)
drop policy if exists oda_insert on public.order_dispatch_attempts;
create policy oda_insert on public.order_dispatch_attempts for insert to authenticated
with check (public.is_admin());
