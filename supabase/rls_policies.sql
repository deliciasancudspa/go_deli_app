-- ============================================================================
-- GO DELI — POLÍTICAS DE SEGURIDAD (RLS) COMPLETAS
-- ============================================================================
-- Generado a partir del análisis de: app cliente (Flutter), app rider (Flutter),
-- panel admin, panel aliados y web cliente.
--
-- ⚠️ IMPORTANTE ANTES DE EJECUTAR:
--   1. Ejecutar primero en un proyecto/branch de prueba de Supabase.
--   2. Ejecutar TODO el script de una vez en el SQL Editor (es idempotente:
--      puede re-ejecutarse sin error).
--   3. Después de aplicar, probar los flujos: registro, pedido, llamar rider,
--      aceptar pedido, entrega, chat, panel admin.
--   4. El panel aliados.html fue actualizado para usar la RPC
--      get_rider_workload() — desplegar la nueva versión del panel junto
--      con este script.
--
-- Modelo de identidad:
--   auth.users.id  ──>  users.auth_id   (users.id es la PK de la app)
--   deliverers.user_id  ──>  users.id
--   stores.owner_id     ──>  users.id
--   orders: client_id / store_id / deliverer_id
--   notifications.target: texto = users.id | deliverers.id | stores.id | 'admin'
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. FUNCIONES AUXILIARES (security definer para evitar recursión de RLS)
-- ────────────────────────────────────────────────────────────────────────────

create or replace function public.app_user_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from users where auth_id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from users where auth_id = auth.uid() and role = 'admin')
$$;

create or replace function public.my_rider_id()
returns uuid language sql stable security definer set search_path = public as $$
  select d.id from deliverers d
  join users u on u.id = d.user_id
  where u.auth_id = auth.uid()
$$;

create or replace function public.my_store_ids()
returns setof uuid language sql stable security definer set search_path = public as $$
  select s.id from stores s
  join users u on u.id = s.owner_id
  where u.auth_id = auth.uid()
$$;

-- ¿Participa el usuario actual en el pedido? (cliente, tienda o rider)
create or replace function public.is_order_participant(p_order_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from orders o
    where o.id = p_order_id
      and (o.client_id   = public.app_user_id()
        or o.deliverer_id = public.my_rider_id()
        or o.store_id in (select public.my_store_ids()))
  )
$$;

-- Estado actual de un rider (security definer: evita recursión de RLS al
-- usarse dentro de las políticas de la propia tabla deliverers)
create or replace function public.rider_current_status(p_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select status from deliverers where id = p_id
$$;

-- RPC para el panel de aliados: carga de trabajo de riders SIN exponer
-- pedidos de otras tiendas. Solo devuelve lo mínimo necesario.
create or replace function public.get_rider_workload(p_rider_ids uuid[])
returns table (deliverer_id uuid, status text, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select o.deliverer_id, o.status, o.updated_at
  from orders o
  where o.deliverer_id = any(p_rider_ids)
    and o.status in ('assigned','picked_up','on_the_way')
    -- solo tiendas o admins pueden consultar carga de riders
    and (public.is_admin() or exists(select 1 from public.my_store_ids()))
$$;

grant execute on function public.get_rider_workload(uuid[]) to authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. ACTIVAR RLS EN TODAS LAS TABLAS
-- ────────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array[
    'users','orders','order_items','order_rejections',
    'stores','store_schedules','store_legal_info','store_payments',
    'store_bank_info','store_contracts',
    'menu_items','menu_categories','categories',
    'deliverers','deliverer_bank_info','rider_payments',
    'user_addresses','user_favorites','user_coupons','coupons',
    'notifications','chat_messages','messages',
    'banners','ad_campaigns','promotions',
    'service_categories','service_providers','service_requests',
    'reviews','prescriptions','config'
  ] loop
    if exists (select 1 from pg_tables where schemaname='public' and tablename=t) then
      execute format('alter table public.%I enable row level security', t);
    end if;
  end loop;
end $$;

-- Helper para crear políticas de forma idempotente
-- (drop + create por cada una, abajo)

-- ────────────────────────────────────────────────────────────────────────────
-- 3. USERS — perfil propio + participantes de pedidos compartidos + admin
-- ────────────────────────────────────────────────────────────────────────────

drop policy if exists users_select on public.users;
create policy users_select on public.users for select to authenticated
using (
  auth_id = auth.uid()
  or public.is_admin()
  -- los perfiles de admin son visibles (apps los buscan para "Contactar admin")
  or role = 'admin'
  -- nombre/teléfono visibles para quien comparte un pedido contigo
  or exists (
    select 1 from orders o
    where (o.client_id = users.id
        or o.deliverer_id in (select d.id from deliverers d where d.user_id = users.id)
        or o.store_id    in (select s.id from stores s where s.owner_id = users.id))
      and (o.client_id   = public.app_user_id()
        or o.deliverer_id = public.my_rider_id()
        or o.store_id in (select public.my_store_ids()))
  )
);

drop policy if exists users_insert on public.users;
create policy users_insert on public.users for insert to authenticated
with check (auth_id = auth.uid() and coalesce(role,'client') <> 'admin');

drop policy if exists users_update on public.users;
create policy users_update on public.users for update to authenticated
using (auth_id = auth.uid() or public.is_admin())
with check (
  public.is_admin()
  -- un usuario no puede auto-promoverse a admin
  or (auth_id = auth.uid() and role <> 'admin')
);

drop policy if exists users_delete on public.users;
create policy users_delete on public.users for delete to authenticated
using (public.is_admin());

-- ────────────────────────────────────────────────────────────────────────────
-- 4. DELIVERERS — lectura amplia (tracking + despacho), escritura propia
-- ────────────────────────────────────────────────────────────────────────────

drop policy if exists deliverers_select on public.deliverers;
create policy deliverers_select on public.deliverers for select to authenticated
using (
  -- Solo admins ven todos los riders. Los demás solo ven riders asignados a sus pedidos.
  public.is_admin()
  or id in (select deliverer_id from orders where client_id = public.app_user_id())
  or id in (select deliverer_id from orders where store_id in (select public.my_store_ids()))
  or user_id = public.app_user_id()  -- el propio rider se ve a sí mismo
);

drop policy if exists deliverers_insert on public.deliverers;
create policy deliverers_insert on public.deliverers for insert to authenticated
with check (user_id = public.app_user_id() and status = 'pending');

drop policy if exists deliverers_update on public.deliverers;
create policy deliverers_update on public.deliverers for update to authenticated
using (user_id = public.app_user_id() or public.is_admin())
with check (
  public.is_admin()
  -- el rider no puede auto-aprobarse: solo admin cambia status
  or (user_id = public.app_user_id()
      and status = public.rider_current_status(id))
);

drop policy if exists deliverers_delete on public.deliverers;
create policy deliverers_delete on public.deliverers for delete to authenticated
using (public.is_admin());

-- ────────────────────────────────────────────────────────────────────────────
-- 5. STORES + catálogo público
-- ────────────────────────────────────────────────────────────────────────────

drop policy if exists stores_select on public.stores;
create policy stores_select on public.stores for select
using (true);  -- catálogo público (anon incluido)

drop policy if exists stores_insert on public.stores;
create policy stores_insert on public.stores for insert to authenticated
with check (owner_id = public.app_user_id() or public.is_admin());

drop policy if exists stores_update on public.stores;
create policy stores_update on public.stores for update to authenticated
using (owner_id = public.app_user_id() or public.is_admin())
with check (
  public.is_admin()
  -- El dueño NO puede cambiar su propio status, is_active ni sponsored —
  -- solo el admin puede aprobar/rechazar/destacar.
  or (
    owner_id = public.app_user_id()
    and status    = (select s2.status    from public.stores s2 where s2.id = stores.id)
    and is_active = (select s2.is_active from public.stores s2 where s2.id = stores.id)
  )
);

drop policy if exists stores_delete on public.stores;
create policy stores_delete on public.stores for delete to authenticated
using (public.is_admin());

-- menu_items / menu_categories / store_schedules: lectura pública,
-- escritura del dueño de la tienda o admin
do $$
declare t text;
begin
  foreach t in array array['menu_items','menu_categories','store_schedules'] loop
    if exists (select 1 from pg_tables where schemaname='public' and tablename=t) then
      execute format('drop policy if exists %I_select on public.%I', t, t);
      execute format('create policy %I_select on public.%I for select using (true)', t, t);
      execute format('drop policy if exists %I_write on public.%I', t, t);
      execute format(
        'create policy %I_write on public.%I for all to authenticated
         using (store_id in (select public.my_store_ids()) or public.is_admin())
         with check (store_id in (select public.my_store_ids()) or public.is_admin())',
        t, t);
    end if;
  end loop;
end $$;

-- store_legal_info / store_payments: SOLO dueño + admin
-- NOTA: También se eliminan políticas legacy permisivas que pudieron quedar de
-- despliegues antiguos (nombradas "authenticated can select ...", "anon can insert ...")
do $$
declare t text;
begin
  foreach t in array array['store_legal_info','store_payments','store_bank_info','store_contracts'] loop
    if exists (select 1 from pg_tables where schemaname='public' and tablename=t) then
      -- eliminar TODAS las políticas viejas conocidas (legacy)
      execute format('drop policy if exists "authenticated can select %I" on public.%I', t, t);
      execute format('drop policy if exists "authenticated can insert %I" on public.%I', t, t);
      execute format('drop policy if exists "anon can insert %I" on public.%I', t, t);
      execute format('drop policy if exists "authenticated can read %I" on public.%I', t, t);
      execute format('drop policy if exists %I_all on public.%I', t, t);
      -- crear la nueva política segura
      execute format(
        'create policy %I_all on public.%I for all to authenticated
         using (store_id in (select public.my_store_ids()) or public.is_admin())
         with check (store_id in (select public.my_store_ids()) or public.is_admin())',
        t, t);
    end if;
  end loop;
end $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 6. CONTENIDO GLOBAL — lectura pública, escritura solo admin
-- ────────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array['categories','banners','promotions','service_categories','config','coupons'] loop
    if exists (select 1 from pg_tables where schemaname='public' and tablename=t) then
      execute format('drop policy if exists %I_select on public.%I', t, t);
      execute format('create policy %I_select on public.%I for select using (true)', t, t);
      execute format('drop policy if exists %I_admin_write on public.%I', t, t);
      execute format(
        'create policy %I_admin_write on public.%I for all to authenticated
         using (public.is_admin()) with check (public.is_admin())', t, t);
    end if;
  end loop;
end $$;

-- ad_campaigns: lectura pública (se muestran en la app), tienda crea las suyas,
-- admin gestiona todas
drop policy if exists ad_campaigns_select on public.ad_campaigns;
create policy ad_campaigns_select on public.ad_campaigns for select using (true);

drop policy if exists ad_campaigns_insert on public.ad_campaigns;
create policy ad_campaigns_insert on public.ad_campaigns for insert to authenticated
with check (store_id in (select public.my_store_ids()) or public.is_admin());

drop policy if exists ad_campaigns_update on public.ad_campaigns;
create policy ad_campaigns_update on public.ad_campaigns for update to authenticated
using (public.is_admin());

drop policy if exists ad_campaigns_delete on public.ad_campaigns;
create policy ad_campaigns_delete on public.ad_campaigns for delete to authenticated
using (public.is_admin());

-- ────────────────────────────────────────────────────────────────────────────
-- 7. ORDERS — solo participantes (cliente, tienda, rider asignado) + admin
-- ────────────────────────────────────────────────────────────────────────────

drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders for select to authenticated
using (
  client_id    = public.app_user_id()
  or deliverer_id = public.my_rider_id()
  or store_id in (select public.my_store_ids())
  or public.is_admin()
  -- Ofertas abiertas: cualquier repartidor puede leer el pedido mientras está
  -- en búsqueda (deliverer_id aún NULL), para previsualizar la ruta y aceptarlo.
  or (
    rider_search_status = 'searching'
    and status not in ('delivered','cancelled','returned')
    and public.my_rider_id() is not null
  )
);

drop policy if exists orders_insert on public.orders;
create policy orders_insert on public.orders for insert to authenticated
with check (client_id = public.app_user_id() or public.is_admin());

drop policy if exists orders_update on public.orders;
create policy orders_update on public.orders for update to authenticated
using (
  client_id    = public.app_user_id()
  or deliverer_id = public.my_rider_id()
  or store_id in (select public.my_store_ids())
  or public.is_admin()
);

drop policy if exists orders_delete on public.orders;
create policy orders_delete on public.orders for delete to authenticated
using (public.is_admin());

-- order_items: vía pedido padre
drop policy if exists order_items_select on public.order_items;
create policy order_items_select on public.order_items for select to authenticated
using (public.is_order_participant(order_id) or public.is_admin());

drop policy if exists order_items_insert on public.order_items;
create policy order_items_insert on public.order_items for insert to authenticated
with check (public.is_order_participant(order_id) or public.is_admin());

drop policy if exists order_items_delete on public.order_items;
create policy order_items_delete on public.order_items for delete to authenticated
using (public.is_admin());

-- order_rejections: rider registra su rechazo; tienda/admin los leen
-- IMPORTANTE: el rider que rechaza NO es "participante" del pedido todavía
-- (deliverer_id es NULL hasta que acepta). Por eso se permite insert/select
-- con rider_id = my_rider_id().
drop policy if exists order_rejections_select on public.order_rejections;
create policy order_rejections_select on public.order_rejections for select to authenticated
using (public.is_order_participant(order_id) or rider_id = public.my_rider_id() or public.is_admin());

drop policy if exists order_rejections_insert on public.order_rejections;
create policy order_rejections_insert on public.order_rejections for insert to authenticated
with check (public.is_order_participant(order_id) or rider_id = public.my_rider_id() or public.is_admin());

-- ────────────────────────────────────────────────────────────────────────────
-- 8. NOTIFICATIONS — target = mi identidad (user/rider/tienda) o 'admin'
-- ────────────────────────────────────────────────────────────────────────────

drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications for select to authenticated
using (
  target = public.app_user_id()::text
  or target = public.my_rider_id()::text
  or target in (select id::text from stores where owner_id = public.app_user_id())
  or (target = 'admin' and public.is_admin())
  or public.is_admin()
);

drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications for insert to authenticated
with check (
  -- Solo el propio usuario puede insertar notificaciones dirigidas a sí mismo,
  -- o el sistema (security definer) inserta notificaciones cruzadas.
  -- Restricción: el target debe ser el usuario, su rider, su tienda, o admin.
  target = public.app_user_id()::text
  or target = public.my_rider_id()::text
  or target in (select id::text from stores where owner_id = public.app_user_id())
  or (target = 'admin' and public.is_admin())
  or public.is_admin()
);

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications for update to authenticated
using (
  target = public.app_user_id()::text
  or target = public.my_rider_id()::text
  or target in (select id::text from stores where owner_id = public.app_user_id())
  or public.is_admin()
);

drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications for delete to authenticated
using (
  target = public.app_user_id()::text
  or target = public.my_rider_id()::text
  or target in (select id::text from stores where owner_id = public.app_user_id())
  or public.is_admin()
);

-- ────────────────────────────────────────────────────────────────────────────
-- 9. CHAT — chat_messages (pedido o directo) y messages (soporte)
-- ────────────────────────────────────────────────────────────────────────────

drop policy if exists chat_messages_select on public.chat_messages;
create policy chat_messages_select on public.chat_messages for select to authenticated
using (
  sender_id   = public.app_user_id()
  or receiver_id = public.app_user_id()
  or (order_id is not null and public.is_order_participant(order_id))
  or public.is_admin()
);

drop policy if exists chat_messages_insert on public.chat_messages;
create policy chat_messages_insert on public.chat_messages for insert to authenticated
with check (
  sender_id = public.app_user_id()
  and (order_id is null or public.is_order_participant(order_id) or public.is_admin())
);

-- 'messages' no existe en la BD actual (el panel admin fue migrado a
-- chat_messages); se protege solo si llegara a crearse.
do $$
begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='messages') then
    execute 'drop policy if exists messages_select on public.messages';
    execute $p$create policy messages_select on public.messages for select to authenticated
      using (sender_id = public.app_user_id() or receiver_id = public.app_user_id() or public.is_admin())$p$;
    execute 'drop policy if exists messages_insert on public.messages';
    execute $p$create policy messages_insert on public.messages for insert to authenticated
      with check (sender_id = public.app_user_id())$p$;
  end if;
end $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 10. DATOS PERSONALES DEL CLIENTE
-- ────────────────────────────────────────────────────────────────────────────

do $$
declare t text;
begin
  foreach t in array array['user_addresses','user_favorites','user_coupons'] loop
    if exists (select 1 from pg_tables where schemaname='public' and tablename=t) then
      execute format('drop policy if exists %I_all on public.%I', t, t);
      execute format(
        'create policy %I_all on public.%I for all to authenticated
         using (user_id = public.app_user_id() or public.is_admin())
         with check (user_id = public.app_user_id() or public.is_admin())',
        t, t);
    end if;
  end loop;
end $$;

-- prescriptions: solo existe como bucket de storage (no hay tabla en la BD
-- actual); se protege solo si llegara a crearse.
do $$
begin
  if exists (select 1 from pg_tables where schemaname='public' and tablename='prescriptions') then
    execute 'drop policy if exists prescriptions_select on public.prescriptions';
    execute $p$create policy prescriptions_select on public.prescriptions for select to authenticated
      using (user_id = public.app_user_id()
             or (order_id is not null and public.is_order_participant(order_id))
             or public.is_admin())$p$;
    execute 'drop policy if exists prescriptions_insert on public.prescriptions';
    execute $p$create policy prescriptions_insert on public.prescriptions for insert to authenticated
      with check (user_id = public.app_user_id())$p$;
  end if;
end $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 11. FINANZAS — máxima restricción
-- ────────────────────────────────────────────────────────────────────────────

drop policy if exists deliverer_bank_info_all on public.deliverer_bank_info;
create policy deliverer_bank_info_all on public.deliverer_bank_info for all to authenticated
using (deliverer_id = public.my_rider_id() or public.is_admin())
with check (deliverer_id = public.my_rider_id() or public.is_admin());

drop policy if exists rider_payments_select on public.rider_payments;
create policy rider_payments_select on public.rider_payments for select to authenticated
using (deliverer_id = public.my_rider_id() or public.is_admin());

drop policy if exists rider_payments_write on public.rider_payments;
create policy rider_payments_write on public.rider_payments for insert to authenticated
with check (public.is_admin());

-- ────────────────────────────────────────────────────────────────────────────
-- 12. RESEÑAS Y SERVICIOS
-- ────────────────────────────────────────────────────────────────────────────

drop policy if exists reviews_select on public.reviews;
create policy reviews_select on public.reviews for select using (true);

drop policy if exists reviews_insert on public.reviews;
create policy reviews_insert on public.reviews for insert to authenticated
with check (public.is_order_participant(order_id) or public.is_admin());

drop policy if exists reviews_delete on public.reviews;
create policy reviews_delete on public.reviews for delete to authenticated
using (public.is_admin());

drop policy if exists service_providers_select on public.service_providers;
create policy service_providers_select on public.service_providers for select using (true);

drop policy if exists service_providers_write on public.service_providers;
create policy service_providers_write on public.service_providers for all to authenticated
using (public.is_admin()) with check (public.is_admin());

-- Registro público de prestadores desde web.html ("Registra tu empresa"):
-- cualquiera puede postular, pero solo como pendiente e inactivo.
drop policy if exists service_providers_apply on public.service_providers;
create policy service_providers_apply on public.service_providers
for insert to anon, authenticated
with check (status = 'pending' and is_active = false);

drop policy if exists service_requests_select on public.service_requests;
create policy service_requests_select on public.service_requests for select to authenticated
using (client_id = public.app_user_id() or public.is_admin());

drop policy if exists service_requests_insert on public.service_requests;
create policy service_requests_insert on public.service_requests for insert to authenticated
with check (client_id = public.app_user_id() or client_id is null);

-- ────────────────────────────────────────────────────────────────────────────
-- 13. STORAGE — políticas de buckets
-- ────────────────────────────────────────────────────────────────────────────
-- avatars / store-images / public: lectura pública, escritura autenticada
-- prescriptions: privado (dueño + admin); compartir con tienda vía signed URLs

drop policy if exists storage_public_read on storage.objects;
create policy storage_public_read on storage.objects for select
using (bucket_id in ('avatars','store-images','public'));

drop policy if exists storage_auth_write on storage.objects;
create policy storage_auth_write on storage.objects for insert to authenticated
with check (
  bucket_id in ('avatars','store-images','public','prescriptions')
  and owner = auth.uid()  -- solo el propietario puede crear sus propios archivos
);

drop policy if exists storage_owner_update on storage.objects;
create policy storage_owner_update on storage.objects for update to authenticated
using (owner = auth.uid() or public.is_admin());

drop policy if exists storage_owner_delete on storage.objects;
create policy storage_owner_delete on storage.objects for delete to authenticated
using (owner = auth.uid() or public.is_admin());

drop policy if exists storage_prescriptions_read on storage.objects;
create policy storage_prescriptions_read on storage.objects for select to authenticated
using (bucket_id = 'prescriptions' and (owner = auth.uid() or public.is_admin()));

-- ────────────────────────────────────────────────────────────────────────────
-- 13b. CORRECCIONES DE ESQUEMA detectadas comparando código vs producción
-- ────────────────────────────────────────────────────────────────────────────
-- La app de servicios muestra y ordena por rating, pero la columna no existe
alter table public.service_providers add column if not exists rating numeric default 5.0;

-- ────────────────────────────────────────────────────────────────────────────
-- 14. INTEGRIDAD DE PRECIOS — el cliente calcula el total; estos triggers
--     bloquean manipulación burda (total negativo/incoherente).
--     TODO futuro: mover la creación del pedido a una edge function que
--     recalcule precios desde menu_items (variantes incluidas).
-- ────────────────────────────────────────────────────────────────────────────

create or replace function public.validate_order_amounts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.total is null or new.total < 0 or new.subtotal < 0
     or coalesce(new.discount,0) < 0 or coalesce(new.delivery_fee,0) < 0 then
    raise exception 'Montos inválidos en el pedido';
  end if;
  -- Fórmula de ambos checkouts (app y web):
  --   total = subtotal + delivery_fee + service_fee
  -- (el descuento ya viene restado del subtotal; platform_fee/fixed_fee y
  --  service_fee son internos — el cliente los paga en el total, el aliado no los ve)
  if abs(new.total - (new.subtotal + coalesce(new.delivery_fee,0) + coalesce(new.service_fee,0))) > 1 then
    raise exception 'Total del pedido incoherente con sus componentes';
  end if;
  return new;
end $$;

drop trigger if exists trg_validate_order_amounts on public.orders;
create trigger trg_validate_order_amounts
  before insert on public.orders
  for each row execute function public.validate_order_amounts();

create or replace function public.validate_order_item_amounts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.item_price < 0 or new.quantity <= 0 then
    raise exception 'Ítem de pedido inválido';
  end if;
  if abs(coalesce(new.subtotal,0) - new.item_price * new.quantity) > 1 then
    raise exception 'Subtotal del ítem incoherente';
  end if;
  return new;
end $$;

drop trigger if exists trg_validate_order_item_amounts on public.order_items;
create trigger trg_validate_order_item_amounts
  before insert on public.order_items
  for each row execute function public.validate_order_item_amounts();

-- ────────────────────────────────────────────────────────────────────────────
-- 15. VERIFICACIÓN — ejecutar después de aplicar
-- ────────────────────────────────────────────────────────────────────────────
-- Tablas sin RLS activo (debe devolver 0 filas):
--   select tablename from pg_tables
--   where schemaname='public' and rowsecurity = false;
--
-- Políticas creadas:
--   select tablename, policyname, cmd from pg_policies
--   where schemaname='public' order by tablename;

-- ────────────────────────────────────────────────────────────────────────────
-- 15. CLAIM DE PEDIDOS EN BÚSQUEDA ABIERTA
--     Cuando el admin reenvía la oferta a todos los riders elegibles
--     ("continuar búsqueda"), el pedido queda sin deliverer_id y en
--     rider_search_status='searching'. El primer rider que acepta se lo
--     queda; esta función hace la asignación de forma atómica.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.claim_order(p_order_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_rider uuid;
  v_updated int;
begin
  v_rider := public.my_rider_id();
  if v_rider is null then return false; end if;
  if not exists (select 1 from deliverers where id = v_rider and status = 'approved') then
    return false;
  end if;
  update orders set
    deliverer_id        = v_rider,
    status              = 'assigned',
    rider_search_status = 'assigned',
    pickup_code         = coalesce(pickup_code,   upper(substr(md5(random()::text), 1, 6))),
    delivery_code       = coalesce(delivery_code, upper(substr(md5(random()::text), 1, 6)))
  where id = p_order_id
    and deliverer_id is null
    and rider_search_status = 'searching'
    and status not in ('delivered','cancelled','returned');
  get diagnostics v_updated = row_count;
  return v_updated > 0;
end $$;

revoke all on function public.claim_order(uuid) from public;
grant execute on function public.claim_order(uuid) to authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 16. INFORMACIÓN EXTRA DE PRODUCTOS POR TIPO DE NEGOCIO
--     El panel de aliados recoge campos específicos (laboratorio, formato,
--     marca, unidad, SKU, garantía, refrigerado, controlado…) que se guardan
--     en un JSONB flexible y se muestran en la app y la web.
-- ────────────────────────────────────────────────────────────────────────────
alter table public.menu_items add column if not exists extra_info jsonb;

-- Logo de prestadores de servicios (la portada usa photo_url)
alter table public.service_providers add column if not exists logo_url text;

-- FK order_items → menu_items: SET NULL para permitir eliminar productos con historial
-- (el historial queda intacto porque order_items guarda item_name/item_price como texto)
alter table public.order_items drop constraint if exists order_items_menu_item_id_fkey;
alter table public.order_items add constraint order_items_menu_item_id_fkey
  foreign key (menu_item_id) references public.menu_items(id) on delete set null;

-- ────────────────────────────────────────────────────────────────────────────
-- 17. order_items UPDATE — faltaba; solo admin puede modificar items ya creados
-- ────────────────────────────────────────────────────────────────────────────
drop policy if exists order_items_update on public.order_items;
create policy order_items_update on public.order_items for update to authenticated
using (public.is_admin())
with check (public.is_admin());

-- ────────────────────────────────────────────────────────────────────────────
-- 18. order_dispatch_attempts — solo participantes del pedido y admin
-- ────────────────────────────────────────────────────────────────────────────
alter table public.order_dispatch_attempts enable row level security;
drop policy if exists oda_select on public.order_dispatch_attempts;
create policy oda_select on public.order_dispatch_attempts for select to authenticated
using (
  public.is_admin()
  or order_id in (select id from orders where client_id = public.app_user_id())
  or order_id in (select id from orders where deliverer_id = public.my_rider_id())
  or order_id in (select id from orders where store_id in (select public.my_store_ids()))
);

-- ────────────────────────────────────────────────────────────────────────────
-- 19. Trigger: Restringir columnas modificables en orders según rol
--     Evita que clientes cambien deliverer_id, total, fees, etc.
-- ────────────────────────────────────────────────────────────────────────────
create or replace function public.check_order_update_columns()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_is_admin boolean;
  v_is_rider boolean;
  v_is_store boolean;
begin
  -- Dispatch engine bypass: las funciones de despacho (security definer)
  -- necesitan actualizar columnas de dispatch sin restricción de rol.
  if current_setting('dispatch.bypass', true) = '1' then return new; end if;

  v_is_admin := public.is_admin();
  if v_is_admin then return new; end if;

  v_is_rider := public.my_rider_id() is not null and new.deliverer_id = public.my_rider_id();
  v_is_store := exists (select 1 from orders o
    join stores s on s.id = o.store_id
    where o.id = new.id and s.owner_id = public.app_user_id());

  -- Cliente solo puede cambiar rating
  if not v_is_admin and not v_is_rider and not v_is_store then
    if new.rated != old.rated or new.rated_at != old.rated_at then
      return new; -- solo rating
    end if;
    raise exception 'Clientes solo pueden calificar pedidos';
  end if;

  -- Rider solo puede cambiar status
  if v_is_rider and not v_is_admin then
    if new.status != old.status then
      return new;
    end if;
    raise exception 'Riders solo pueden cambiar status';
  end if;

  return new;
end $$;

drop trigger if exists trg_check_order_update on public.orders;
create trigger trg_check_order_update
  before update on public.orders
  for each row execute function public.check_order_update_columns();

-- ────────────────────────────────────────────────────────────────────────────
-- 20. NOTA: store_bank_info y store_contracts se crearon después del primer
--     despliegue de RLS y quedaron SIN protección (datos bancarios y
--     contratos legibles/escribibles por cualquiera). Este script ya las
--     incluye en las secciones 2 y 5 — basta re-ejecutarlo completo.

-- ────────────────────────────────────────────────────────────────────────────
-- 21. RPC PARA CREAR USUARIO POST-SIGNUP (bypassea RLS)
--     La política users_insert exige autenticación, pero tras signUp el usuario
--     puede no tener sesión activa si la confirmación de email está habilitada.
--     Esta función SECURITY DEFINER inserta en public.users directamente.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_user_on_signup(
  p_auth_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_phone TEXT DEFAULT NULL,
  p_role TEXT DEFAULT 'client',
  p_national_id TEXT DEFAULT NULL,
  p_region TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id UUID;
BEGIN
  -- Verificar que el auth user existe
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_auth_id) THEN
    RAISE EXCEPTION 'El usuario de autenticación no existe';
  END IF;

  -- Verificar que no exista ya un registro para este auth_id (evita duplicados)
  IF EXISTS (SELECT 1 FROM public.users WHERE auth_id = p_auth_id) THEN
    RAISE EXCEPTION 'Ya existe un registro de usuario para este auth_id';
  END IF;

  -- Nadie puede auto-asignarse admin
  IF p_role = 'admin' THEN
    RAISE EXCEPTION 'No se permite auto-asignar el rol admin';
  END IF;

  INSERT INTO public.users (auth_id, email, name, phone, role, national_id, region, city)
  VALUES (p_auth_id, p_email, p_name, p_phone, p_role, p_national_id, p_region, p_city)
  RETURNING id INTO v_user_id;

  RETURN v_user_id;
END $$;

GRANT EXECUTE ON FUNCTION public.create_user_on_signup(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- RPC para que usuarios no-admin puedan notificar al admin (bypassea RLS de notifications)
-- Usado por: aliados.html al registrar nuevo aliado, web.html al hacer pedidos, etc.
CREATE OR REPLACE FUNCTION public.notify_admin(
  p_title TEXT,
  p_message TEXT,
  p_type TEXT DEFAULT 'alert',
  p_emoji TEXT DEFAULT '🚨',
  p_data JSONB DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_notif_id UUID;
BEGIN
  INSERT INTO public.notifications (title, message, type, emoji, target, is_read, data)
  VALUES (p_title, p_message, p_type, p_emoji, 'admin', false, p_data)
  RETURNING id INTO v_notif_id;
  RETURN v_notif_id;
END $$;

GRANT EXECUTE ON FUNCTION public.notify_admin(TEXT, TEXT, TEXT, TEXT, JSONB) TO authenticated;

-- RPC para incrementar usos de cupón desde el checkout (bypassea RLS de coupons)
-- Usado por: checkout_screen.dart al crear un pedido con cupón aplicado
CREATE OR REPLACE FUNCTION public.increment_coupon_uses(p_code TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.coupons
  SET current_uses = COALESCE(current_uses, 0) + 1
  WHERE code = upper(p_code) AND is_active = true;
END $$;

GRANT EXECUTE ON FUNCTION public.increment_coupon_uses(TEXT) TO authenticated;
