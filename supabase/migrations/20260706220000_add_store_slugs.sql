-- ============================================================================
-- SLUGS ÚNICOS POR TIENDA — URLs amigables tipo godeli.cl/mi-tienda
-- ============================================================================
-- Agrega un slug único a cada tienda para generar enlaces cortos y QR.
-- El slug se puede elegir manualmente o se autogenera del nombre.

-- 1. Columna slug (única, opcional, solo lowercase alfanumérico + guiones)
ALTER TABLE public.stores ADD COLUMN IF NOT EXISTS slug TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_stores_slug ON public.stores(slug) WHERE slug IS NOT NULL;

-- 2. RPC para verificar disponibilidad de slug (el aliado escribe y ve si está libre)
CREATE OR REPLACE FUNCTION public.check_slug_available(
  p_slug TEXT,
  p_store_id UUID DEFAULT NULL
) RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.stores
    WHERE slug = p_slug
      AND (p_store_id IS NULL OR id <> p_store_id)
  );
$$;
GRANT EXECUTE ON FUNCTION public.check_slug_available(TEXT, UUID) TO authenticated;

-- 3. RPC para resolver slug → store_id (usada por tienda.html y web.html)
CREATE OR REPLACE FUNCTION public.resolve_slug(p_slug TEXT)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM public.stores WHERE slug = p_slug AND is_active = true LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.resolve_slug(TEXT) TO anon, authenticated;

-- 4. Trigger para autogenerar slug desde el nombre si no se especifica uno
--    Solo se autogenera en INSERT si el slug viene NULL/vacío.
CREATE OR REPLACE FUNCTION public.autogenerate_slug()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_base TEXT;
  v_slug TEXT;
  v_counter INT := 0;
BEGIN
  -- Si ya tiene slug, normalizarlo (limpiar, lowercase, guiones)
  IF NEW.slug IS NOT NULL AND NEW.slug <> '' THEN
    NEW.slug := regexp_replace(
                  regexp_replace(lower(trim(NEW.slug)), '[^a-z0-9\-]', '-', 'g'),
                  '-+', '-', 'g');
    NEW.slug := trim(NEW.slug, '-');
    -- Si después de limpiar quedó vacío, regenerar desde nombre
    IF NEW.slug = '' THEN NEW.slug := NULL; END IF;
  END IF;

  -- Autogenerar desde el nombre si sigue sin slug
  IF NEW.slug IS NULL OR NEW.slug = '' THEN
    v_base := regexp_replace(
                regexp_replace(lower(trim(NEW.name)), '[^a-z0-9\-]', '-', 'g'),
                '-+', '-', 'g');
    v_base := trim(v_base, '-');
    IF v_base = '' THEN v_base := 'tienda'; END IF;

    v_slug := v_base;
    -- Intentar slug base, luego base-2, base-3... hasta encontrar uno libre
    LOOP
      IF NOT EXISTS (SELECT 1 FROM public.stores WHERE slug = v_slug AND id <> NEW.id) THEN
        EXIT;
      END IF;
      v_counter := v_counter + 1;
      v_slug := v_base || '-' || v_counter;
    END LOOP;
    NEW.slug := v_slug;
  END IF;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_autogenerate_slug ON public.stores;
CREATE TRIGGER trg_autogenerate_slug
  BEFORE INSERT OR UPDATE OF name, slug ON public.stores
  FOR EACH ROW EXECUTE FUNCTION public.autogenerate_slug();

-- 5. Backfill: generar slugs para tiendas existentes que no tengan uno
UPDATE public.stores SET slug = NULL WHERE slug = '';
DO $$
DECLARE
  r RECORD;
  v_slug TEXT;
  v_base TEXT;
  v_counter INT;
BEGIN
  FOR r IN SELECT id, name FROM public.stores WHERE slug IS NULL LOOP
    v_base := regexp_replace(
                regexp_replace(lower(trim(r.name)), '[^a-z0-9\-]', '-', 'g'),
                '-+', '-', 'g');
    v_base := trim(v_base, '-');
    IF v_base = '' THEN v_base := 'tienda'; END IF;

    v_slug := v_base;
    v_counter := 0;
    LOOP
      IF NOT EXISTS (SELECT 1 FROM public.stores WHERE slug = v_slug AND id <> r.id) THEN
        EXIT;
      END IF;
      v_counter := v_counter + 1;
      v_slug := v_base || '-' || v_counter;
    END LOOP;

    UPDATE public.stores SET slug = v_slug WHERE id = r.id;
  END LOOP;
END $$;
