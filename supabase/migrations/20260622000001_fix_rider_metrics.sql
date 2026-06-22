-- ============================================================================
-- FIX: Métricas de rider + fixed_fee / platform_fee desde config de tienda
-- ============================================================================
-- Bugs:
--   1. release_rider_on_delivery solo liberaba is_available, sin incrementar
--      total_deliveries ni total_earnings al completar una entrega.
--   2. Órdenes creadas sin rider_fee/delivery_distance quedaban en 0/NULL.
--   3. orders.fixed_fee usaba DEFAULT 3000 ignorando stores.fixed_fee.
--   4. orders.platform_fee siempre 0 — no se calculaba desde commission_pct.
--
-- Fix 1: release_rider_on_delivery ahora incrementa las métricas.
-- Fix 2: Trigger BEFORE INSERT auto-calcula:
--        • delivery_distance (haversine store→delivery)
--        • rider_fee (base_fee + distancia × fee_per_100m)
--        • fixed_fee (desde stores.fixed_fee, no el DEFAULT)
--        • platform_fee (subtotal × stores.commission_pct / 100)
--        No interfiere con valores explícitos de la app (solo NULL o 0).
-- ============================================================================

-- 1. Actualizar release_rider_on_delivery --------------------------------------
create or replace function public.release_rider_on_delivery()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  remaining_orders int;
begin
  if new.status = 'delivered' and old.status != 'delivered' and new.deliverer_id is not null then
    -- Incrementar métricas del rider
    update deliverers
    set total_deliveries = total_deliveries + 1,
        total_earnings   = total_earnings + coalesce(new.rider_fee, 0)
    where id = new.deliverer_id;

    -- Contar pedidos activos restantes
    select count(*) into remaining_orders
    from orders
    where deliverer_id = new.deliverer_id
      and status in ('assigned','picked_up','on_the_way')
      and id != new.id;

    -- Si tiene menos de 2 pedidos activos, volver a disponible
    if remaining_orders < 2 then
      update deliverers set is_available = true where id = new.deliverer_id;
    end if;
  end if;
  return new;
end;
$$;

-- 2. Función para calcular fees automáticamente desde la tienda y config ---------
create or replace function public.calculate_order_fees()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_store_lat    double precision;
  v_store_lng    double precision;
  v_store_fixed  numeric;
  v_store_pct    numeric;
  v_distance     double precision;
  v_config       jsonb;
  v_base_fee     int;
  v_fee_per_100m int;
begin
  if new.store_id is not null then
    -- Obtener config de la tienda: coordenadas, fixed_fee, commission_pct
    select s.lat, s.lng, s.fixed_fee, s.commission_pct
    into v_store_lat, v_store_lng, v_store_fixed, v_store_pct
    from stores s where s.id = new.store_id;

    -- --- fixed_fee: usar el de la tienda, no el DEFAULT 3000 ----------------
    if new.fixed_fee is null or new.fixed_fee = 0 or new.fixed_fee = 3000 then
      new.fixed_fee := coalesce(v_store_fixed, 3000);
    end if;

    -- --- platform_fee: subtotal × commission_pct / 100 ----------------------
    if (new.platform_fee is null or new.platform_fee = 0)
       and new.subtotal is not null and new.subtotal > 0 then
      new.platform_fee := round(new.subtotal * coalesce(v_store_pct, 7) / 100.0);
    end if;

    -- --- rider_fee + delivery_distance (requiere coordenadas) ---------------
    if (new.rider_fee is null or new.rider_fee = 0)
       and new.delivery_lat is not null
       and new.delivery_lng is not null then

      if v_store_lat is not null and v_store_lng is not null then
        -- Calcular distancia con la función haversine existente
        v_distance := public.haversine_m(v_store_lat, v_store_lng, new.delivery_lat, new.delivery_lng);
        if new.delivery_distance is null or new.delivery_distance = 0 then
          new.delivery_distance := round(v_distance);
        end if;

        -- Leer fórmula de tarifas del config global
        select value::jsonb into v_config from config where key = 'delivery_fees';

        v_base_fee     := coalesce((v_config->>'base_fee')::int, 2000);
        v_fee_per_100m := coalesce((v_config->>'fee_per_100m')::int, 35);

        -- rider_fee = base_fee + (distancia_m / 100) * fee_per_100m
        new.rider_fee := v_base_fee + round((v_distance / 100.0) * v_fee_per_100m);
      end if;
    end if;
  end if;

  return new;
end;
$$;

-- 3. Trigger BEFORE INSERT para auto-calcular fees ------------------------------
drop trigger if exists trg_calculate_order_fees on public.orders;
create trigger trg_calculate_order_fees
before insert on public.orders
for each row execute function public.calculate_order_fees();
