-- Fix: remove rider_lat/rider_lng check from check_order_update_columns trigger.
-- Those columns don't exist in the orders table, causing error 42703 when riders
-- accept offers (accept_offer → UPDATE orders → trigger fires → accesses new.rider_lat).
create or replace function public.check_order_update_columns()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_is_admin boolean;
  v_is_rider boolean;
  v_is_store boolean;
begin
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

-- Re-crear el trigger por si acaso
drop trigger if exists trg_check_order_update on public.orders;
create trigger trg_check_order_update
  before update on public.orders
  for each row execute function public.check_order_update_columns();
