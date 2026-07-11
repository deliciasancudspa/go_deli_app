-- ============================================================================
-- Auto-crear perfil en public.users cuando se registra un auth.user
-- ============================================================================
-- Este trigger elimina la dependencia de RLS para el INSERT inicial:
-- - Si hay sesión (email confirmado o confirmación desactivada):
--   → la app inserta directo, el trigger no hace nada (ya existe)
-- - Si NO hay sesión (confirmación de email activada):
--   → la app no puede insertar (RLS bloquea), el trigger lo hace por ella
--
-- EJECUTAR EN: Supabase Dashboard → SQL Editor → pegar y Run
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Si la app ya insertó el perfil (sesión existente), no duplicar
  IF EXISTS (SELECT 1 FROM public.users WHERE auth_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  -- Insertar perfil básico desde los metadatos del registro
  -- COALESCE + NULLIF manejan campos faltantes, vacíos, o registros
  -- que no mandan metadata (web, Google Sign-In pre complete-profile, etc.)
  INSERT INTO public.users (
    auth_id,
    email,
    name,
    phone,
    role,
    nationality,
    national_id,
    national_id_type,
    region,
    city
  ) VALUES (
    NEW.id,
    NEW.email,
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'name', ''),
      NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
      SPLIT_PART(NEW.email, '@', 1)
    ),
    NULLIF(NEW.raw_user_meta_data->>'phone', ''),
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'role', ''),
      'client'
    ),
    NULLIF(NEW.raw_user_meta_data->>'nationality', ''),
    NULLIF(NEW.raw_user_meta_data->>'national_id', ''),
    NULLIF(NEW.raw_user_meta_data->>'national_id_type', ''),
    NULLIF(NEW.raw_user_meta_data->>'region', ''),
    NULLIF(NEW.raw_user_meta_data->>'city', '')
  );

  RETURN NEW;
END;
$$;

-- Eliminar trigger anterior si existe (para reprocesar sin errores)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Crear el trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();
