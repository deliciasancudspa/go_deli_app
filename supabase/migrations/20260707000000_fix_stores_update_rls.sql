-- ============================================================================
-- Fix: política stores_update — asegura que admins puedan modificar status/is_active
-- ============================================================================
-- Problema: al aprobar/rechazar tiendas desde admin.html, el update fallaba con
-- "new row violates row-level security policy for table stores".
-- Causa probable: is_admin() no retornaba true o la política no estaba aplicada.
-- Solución: re-crear las funciones auxiliares y la política con un enfoque más
-- robusto, usando un check directo en vez de subqueries autoreferenciadas.

-- 1. Asegurar que las funciones auxiliares existen y son correctas ─────────────

CREATE OR REPLACE FUNCTION public.app_user_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM users WHERE auth_id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS(SELECT 1 FROM users WHERE auth_id = auth.uid() AND role = 'admin')
$$;

-- 2. Re-crear política stores_update ───────────────────────────────────────────

DROP POLICY IF EXISTS stores_update ON public.stores;

-- Permitir UPDATE al owner de la tienda O al admin.
-- El admin puede modificar cualquier campo (incluyendo status, is_active, sponsored).
-- El dueño NO puede modificar status ni is_active (solo el admin puede aprobar/rechazar).
CREATE POLICY stores_update ON public.stores FOR UPDATE TO authenticated
USING (
  owner_id = public.app_user_id()
  OR public.is_admin()
)
WITH CHECK (
  public.is_admin()
  OR (
    -- Dueño: no puede cambiar status ni is_active
    owner_id = public.app_user_id()
    AND status IS NOT DISTINCT FROM (SELECT s2.status FROM public.stores s2 WHERE s2.id = stores.id)
    AND is_active IS NOT DISTINCT FROM (SELECT s2.is_active FROM public.stores s2 WHERE s2.id = stores.id)
  )
);

-- 3. También re-crear stores_insert por si acaso ───────────────────────────────

DROP POLICY IF EXISTS stores_insert ON public.stores;
CREATE POLICY stores_insert ON public.stores FOR INSERT TO authenticated
WITH CHECK (owner_id = public.app_user_id() OR public.is_admin());

-- 4. Asegurar RLS habilitado en stores ─────────────────────────────────────────

ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;
