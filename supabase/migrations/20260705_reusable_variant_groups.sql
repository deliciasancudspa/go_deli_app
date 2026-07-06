-- ============================================================================
-- Go Business 2.0 — Grupos reutilizables de variantes y opciones
-- ============================================================================
-- Permite crear grupos de variantes (Tamaño, Color, etc.) y grupos de opciones
-- (Extras, Salsas, etc.) a nivel tienda, y asignarlos a múltiples productos.
-- ============================================================================

-- 1. GRUPOS DE VARIANTES REUTILIZABLES ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.variant_groups (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id   UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0,
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_variant_groups_store ON public.variant_groups(store_id);

-- 2. ÍTEMS DE GRUPOS DE VARIANTES ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.variant_items (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id       UUID NOT NULL REFERENCES public.variant_groups(id) ON DELETE CASCADE,
  name           TEXT NOT NULL,
  price_modifier INTEGER DEFAULT 0,
  sort_order     INTEGER DEFAULT 0,
  is_active      BOOLEAN DEFAULT true,
  created_at     TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_variant_items_group ON public.variant_items(group_id);

-- 3. PRODUCTO ↔ GRUPOS DE VARIANTES ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.menu_item_variant_groups (
  item_id  UUID REFERENCES public.menu_items(id) ON DELETE CASCADE,
  group_id UUID REFERENCES public.variant_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, group_id)
);
