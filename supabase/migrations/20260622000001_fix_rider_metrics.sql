-- ============================================================================
-- FIX: Métricas de rider (total_deliveries, total_earnings) no se actualizaban
-- ============================================================================
-- Bugs:
--   1. release_rider_on_delivery solo liberaba is_available, sin incrementar
--      total_deliveries ni total_earnings al completar una entrega.
--   2. Órdenes creadas sin rider_fee/delivery_distance (SQL directo, edge cases)
--      quedaban con rider_fee=0 → total_earnings no subía.
--
-- Fix 1: release_rider_on_delivery ahora incrementa las métricas.
-- Fix 2: Trigger BEFORE INSERT calcula delivery_distance + rider_fee como
--        safety net si vienen en NULL/0 (no interfiere con valores de la app).
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

-- 2. Función para calcular rider_fee automáticamente ----------------------------
create or replace function public.calculate_order_rider_fee()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_store_lat    double precision;
  v_store_lng    double precision;
  v_distance     double precision;
  v_config       jsonb;
  v_base_fee     int;
  v_fee_per_100m int;
begin
  -- Solo calcular si rider_fee falta o es 0, y tenemos coordenadas + tienda
  if (new.rider_fee is null or new.rider_fee = 0)
     and new.delivery_lat is not null
     and new.delivery_lng is not null
     and new.store_id is not null then

    -- Coordenadas de la tienda
    select s.lat, s.lng into v_store_lat, v_store_lng
    from stores s where s.id = new.store_id;

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

  return new;
end;
$$;

-- 3. Trigger BEFORE INSERT para auto-calcular rider_fee -------------------------
drop trigger if exists trg_calculate_rider_fee on public.orders;
create trigger trg_calculate_rider_fee
before insert on public.orders
for each row execute function public.calculate_order_rider_fee();
