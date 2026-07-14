-- ============================================================================
-- FIX: Eliminar FK constraint en current_offer_rider_id para resolver
--      el error PGRST201 en tracking de pedidos.
--
-- Problema: orders tiene 2 FK a deliverers (deliverer_id + current_offer_rider_id).
--           PostgREST no puede resolver cuál usar al embedear "deliverers" en
--           consultas como tracking_screen.dart y web.html.
--
--           Esto rompía la pantalla de seguimiento para TODOS los pedidos,
--           tuvieran rider o no.
--
-- Fix:     Droppear el FK de current_offer_rider_id. La columna se conserva,
--          el dispatch engine la sigue usando sin problemas (solo la setea/limpia,
--          nunca hace JOINs por esta columna).
--
-- NOTA:    Esto revierte el fix de RLS 20260713000001 porque ya no es necesario.
--          El verdadero problema era la doble FK, no el RLS de deliverers.
-- ============================================================================

-- 1. Droppear FK constraint de current_offer_rider_id
alter table public.orders drop constraint if exists orders_current_offer_rider_id_fkey;

-- 2. Restaurar RLS de deliverers a su estado original (el fix de RLS ya no es necesario)
drop policy if exists deliverers_select on public.deliverers;
create policy deliverers_select on public.deliverers for select to authenticated
using (
  public.is_admin()
  or id in (select deliverer_id from orders where client_id = public.app_user_id())
  or id in (select deliverer_id from orders where store_id in (select public.my_store_ids()))
  or user_id = public.app_user_id()  -- el propio rider se ve a sí mismo
);
