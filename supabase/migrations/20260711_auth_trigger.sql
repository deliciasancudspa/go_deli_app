-- ============================================================================
-- Auto-crear perfil en public.users cuando se registra un auth.user
-- ============================================================================
-- Este trigger elimina la dependencia de RLS para el INSERT inicial:
-- - Si hay sesión (email confirmado o confirmación desactivada):
--   → la app inserta directo, el trigger no hace nada (ya existe)
-- - Si NO hay sesión (confirmación de email activada):
--   → la app no puede insertar (RLS bloquea), el trigger lo hace por ella
--
-- Maneja 3 casos:
-- 1. Perfil ya vinculado al auth_id → skip
-- 2. Perfil existe con el mismo email pero auth_id huérfano/antiguo → recuperar
-- 3. No existe perfil → crear desde metadatos (con fallbacks seguros)
--
-- EJECUTAR EN: Supabase Dashboard → SQL Editor → pegar y Run
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  existing_profile public.users%ROWTYPE;
BEGIN
  -- Caso 1: Ya existe perfil con este auth_id → no hacer nada
  IF EXISTS (SELECT 1 FROM public.users WHERE auth_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  -- Buscar perfil por email (puede tener auth_id antiguo huérfano o NULL)
  SELECT * INTO existing_profile FROM public.users
  WHERE email = NEW.email
  LIMIT 1;

  -- Caso 2: Existe perfil con este email → recuperarlo
  IF FOUND THEN
    UPDATE public.users SET
      auth_id = NEW.id,
      updated_at = now()
    WHERE id = existing_profile.id;
    RETURN NEW;
  END IF;

  -- Caso 3: No existe → crear perfil nuevo desde metadatos
  INSERT INTO public.users (
    auth_id, email, name, phone, role,
    nationality, national_id, national_id_type, region, city
  ) VALUES (
    NEW.id,
    NEW.email,
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'name', ''),
      NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
      SPLIT_PART(NEW.email, '@', 1)
    ),
    NULLIF(NEW.raw_user_meta_data->>'phone', ''),
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'role', ''), 'client'),
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
