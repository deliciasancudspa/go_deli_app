-- ============================================================================
-- FIX: Relajar RLS de deliverers para que el tracking de pedidos funcione
--      incluso cuando la orden aún no tiene rider asignado.
--
-- Problema: tracking_screen.dart hace una consulta anidada:
--   orders(*, stores(*), deliverers(*, users(*)))
-- Cuando la orden no tiene rider (pending/accepted/preparing/ready),
-- el RLS de deliverers bloqueaba el recurso embebido y PostgREST
-- fallaba toda la consulta, mostrando "No se pudo cargar el pedido".
--
-- Fix: Permitir que cualquier usuario autenticado pueda leer la tabla
--      deliverers. Los repartidores son trabajadores públicos; su nombre,
--      teléfono y ubicación ya se comparten con los clientes a los que
--      entregan pedidos.
-- ============================================================================

drop policy if exists deliverers_select on public.deliverers;
create policy deliverers_select on public.deliverers for select to authenticated
using (
  public.is_admin()
  or id in (select deliverer_id from orders where client_id = public.app_user_id())
  or id in (select deliverer_id from orders where store_id in (select public.my_store_ids()))
  or user_id = public.app_user_id()   -- el propio rider se ve a sí mismo
  or true                             -- cualquier usuario autenticado puede ver riders
);
