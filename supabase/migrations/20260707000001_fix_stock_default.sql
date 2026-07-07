-- ============================================================================
-- Corregir default de stock: NULL = "sin gestionar" (ilimitado)
-- Solo stock = 0 explícito muestra "Agotado" en la web/app
-- ============================================================================
ALTER TABLE public.menu_items ALTER COLUMN stock SET DEFAULT NULL;
