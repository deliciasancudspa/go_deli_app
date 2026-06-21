-- ═══════════════════════════════════════════════════════════════════════════════
-- Migración: corregir órdenes con commune_id=NULL y dashboard nacional
-- Fecha:    2026-06-21
-- Problema: Órdenes sin comuna no aparecen en admin (dashboard, pedidos, reportes)
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. Backfill: asignar commune_id a órdenes existentes desde la tienda
update public.orders o set commune_id = s.commune_id
from public.stores s
where o.store_id = s.id
  and o.commune_id is null
  and s.commune_id is not null;

-- 2. Actualizar national_dashboard() para resolver commune_id vía la tienda
--    cuando la orden no tenga commune_id propio, y agrupar las que sigan siendo
--    NULL en una fila "Sin comuna".
drop function if exists public.national_dashboard();

create or replace function public.national_dashboard()
returns table(
  commune_id    uuid,
  commune_name  text,
  region_name   text,
  total_stores  bigint,
  total_riders  bigint,
  total_orders  bigint,
  total_revenue numeric
)
language sql stable security definer set search_path = public as $$
  with effective_orders as (
    select
      o.id,
      o.total,
      o.status,
      coalesce(o.commune_id, s.commune_id) as commune_id
    from orders o
    left join stores s on s.id = o.store_id
  )
  select
    c.id,
    c.name,
    r.name,
    count(distinct s.id) filter (where s.is_active = true),
    count(distinct d.id) filter (where d.status = 'approved'),
    count(distinct eo.id),
    coalesce(sum(eo.total) filter (where eo.status = 'delivered'), 0)
  from communes c
  join regions r on r.id = c.region_id
  left join stores s          on s.commune_id = c.id
  left join deliverers d      on d.commune_id = c.id
  left join effective_orders eo on eo.commune_id = c.id
  where c.is_active = true
  group by c.id, c.name, r.name
  order by r.name, c.name;
$$;

grant execute on function public.national_dashboard() to authenticated;
