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
using (true);  -- tiendas eligen riders online; clientes ven ubicación en tracking

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
using (owner_id = public.app_user_id() or public.is_admin());

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
do $$
declare t text;
begin
  foreach t in array array['store_legal_info','store_payments'] loop
    if exists (select 1 from pg_tables where schemaname='public' and tablename=t) then
      execute format('drop policy if exists %I_all on public.%I', t, t);
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
drop policy if exists order_rejections_select on public.order_rejections;
create policy order_rejections_select on public.order_rejections for select to authenticated
using (public.is_order_participant(order_id) or public.is_admin());

drop policy if exists order_rejections_insert on public.order_rejections;
create policy order_rejections_insert on public.order_rejections for insert to authenticated
with check (public.is_order_participant(order_id) or public.is_admin());

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
with check (true);  -- apps crean notificaciones cruzadas (tienda→rider, rider→admin…)

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
with check (bucket_id in ('avatars','store-images','public','prescriptions'));

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
  -- Fórmula de ambos checkouts (app y web): total = subtotal + delivery_fee
  -- (el descuento ya viene restado del subtotal; platform_fee/fixed_fee son
  -- comisiones del lado tienda y no se cobran al cliente)
  if abs(new.total - (new.subtotal + coalesce(new.delivery_fee,0))) > 1 then
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
