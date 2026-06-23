-- ============================================================================
-- GO DELI — Fix stores: updated_at trigger + compound index
-- ============================================================================
-- Fecha: 2026-06-23
-- Contexto: Pre-lanzamiento verificación de aliados
-- Issues corregidos:
--   1. stores no tenía trigger de auto-actualización de updated_at
--   2. Falta índice compuesto en stores(status, is_active) para las queries
--      de listado de tiendas (la consulta más frecuente del catálogo)
-- ============================================================================

-- 1. Asegurar que existe la columna updated_at
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'stores' AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE public.stores ADD COLUMN updated_at timestamptz DEFAULT now();
  END IF;
END $$;

-- 2. Crear función de actualización de timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END $$;

-- 3. Trigger de auto-actualización de updated_at (idempotente)
DROP TRIGGER IF EXISTS trg_stores_updated_at ON public.stores;
CREATE TRIGGER trg_stores_updated_at
  BEFORE UPDATE ON public.stores
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 4. Índice compuesto para la query más común del catálogo
--     SELECT ... FROM stores WHERE status = 'approved' AND is_active = true AND commune_id = ? ORDER BY ...
--     Sin este índice, con 200+ tiendas se hace sequential scan en cada carga.
CREATE INDEX IF NOT EXISTS idx_stores_status_active
  ON public.stores(status, is_active)
  WHERE status = 'approved' AND is_active = true;

-- 5. Índice para búsqueda por owner_id (usado en RLS y panel aliados)
CREATE INDEX IF NOT EXISTS idx_stores_owner_id
  ON public.stores(owner_id);

-- 6. Verificación final
DO $$
DECLARE
  v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM pg_indexes
  WHERE schemaname = 'public' AND tablename = 'stores'
    AND indexname IN ('idx_stores_status_active', 'idx_stores_owner_id');
  RAISE NOTICE 'Índices creados en stores: % (deberían ser 2)', v_count;
END $$;
