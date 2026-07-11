-- Backfill: crear perfiles solo para huérfanos cuyo email no exista ya en public.users
INSERT INTO public.users (auth_id, email, name, phone, role, nationality, national_id, national_id_type, region, city)
SELECT
  au.id,
  au.email,
  COALESCE(
    NULLIF(au.raw_user_meta_data->>'name', ''),
    NULLIF(au.raw_user_meta_data->>'full_name', ''),
    SPLIT_PART(au.email, '@', 1)
  ),
  NULLIF(au.raw_user_meta_data->>'phone', ''),
  COALESCE(NULLIF(au.raw_user_meta_data->>'role', ''), 'client'),
  NULLIF(au.raw_user_meta_data->>'nationality', ''),
  NULLIF(au.raw_user_meta_data->>'national_id', ''),
  NULLIF(au.raw_user_meta_data->>'national_id_type', ''),
  NULLIF(au.raw_user_meta_data->>'region', ''),
  NULLIF(au.raw_user_meta_data->>'city', '')
FROM auth.users au
LEFT JOIN public.users pu ON pu.auth_id = au.id
WHERE pu.id IS NULL
  AND NOT EXISTS (SELECT 1 FROM public.users WHERE email = au.email);
