CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Caso 1: Ya existe perfil con este auth_id → no hacer nada
  IF EXISTS (SELECT 1 FROM public.users WHERE auth_id = NEW.id) THEN
    RETURN NEW;
  END IF;

  -- Caso 2: Existe perfil con este email pero sin auth_id (huérfano por cleanup anterior)
  -- → recuperarlo vinculando el nuevo auth_id
  UPDATE public.users
  SET auth_id = NEW.id,
      name = COALESCE(NULLIF(users.name, ''), NULLIF(NEW.raw_user_meta_data->>'name', ''), NULLIF(NEW.raw_user_meta_data->>'full_name', ''), SPLIT_PART(NEW.email, '@', 1)),
      phone = COALESCE(NULLIF(users.phone, ''), NULLIF(NEW.raw_user_meta_data->>'phone', '')),
      updated_at = now()
  WHERE email = NEW.email AND auth_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM public.users WHERE email = NEW.email AND auth_id IS NOT NULL);
  IF FOUND THEN
    RETURN NEW;
  END IF;

  -- Caso 3: Ni auth_id ni email existen → crear perfil nuevo
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
