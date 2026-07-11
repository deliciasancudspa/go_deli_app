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

  -- Caso 3: No existe → crear perfil nuevo
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
