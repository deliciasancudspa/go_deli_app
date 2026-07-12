-- ============================================================================
-- Extender handle_new_auth_user() para crear perfil completo de deliverer
-- ============================================================================
-- Cuando un rider se registra con confirmación de email, no hay sesión y la app
-- no puede insertar en deliverers/deliverer_bank_info. Este trigger lo hace
-- desde raw_user_meta_data con SECURITY DEFINER, completando el registro en un
-- solo paso y evitando que el rider tenga que llenar el formulario dos veces.
--
-- ⚠️ RIESGO: signature_image (PNG base64 ~50-200KB) podría exceder límites de
--    raw_user_meta_data en GoTrue. Si esto falla, Plan B:
--    - Excluir firma del metadata en el signUp de Flutter
--    - Modificar notify_admin RPC para aceptar anon
--    - App llama signUp sin firma → éxito → llama RPC con firma
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
  v_user_id uuid;
  v_deliverer_id uuid;
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
  )
  RETURNING id INTO v_user_id;

  -- Si es deliverer, crear perfil completo de repartidor
  IF NEW.raw_user_meta_data->>'role' = 'deliverer' THEN
    -- Crear deliverer
    INSERT INTO public.deliverers (
      user_id, vehicle_type, vehicle_plate, status, is_online, is_available, commune_id
    ) VALUES (
      v_user_id,
      COALESCE(NULLIF(NEW.raw_user_meta_data->>'vehicle', ''), 'Moto'),
      NULLIF(NEW.raw_user_meta_data->>'plate', ''),
      'pending', false, false,
      NULLIF(NEW.raw_user_meta_data->>'commune_id', '')::uuid
    )
    RETURNING id INTO v_deliverer_id;

    -- Crear datos bancarios
    INSERT INTO public.deliverer_bank_info (
      deliverer_id, bank_name, account_type, account_number, account_holder, rut
    ) VALUES (
      v_deliverer_id,
      COALESCE(NULLIF(NEW.raw_user_meta_data->>'bank_name', ''), 'BancoEstado'),
      COALESCE(NULLIF(NEW.raw_user_meta_data->>'account_type', ''), 'Cuenta Vista'),
      NULLIF(NEW.raw_user_meta_data->>'account_number', ''),
      NULLIF(NEW.raw_user_meta_data->>'account_holder', ''),
      NULLIF(NEW.raw_user_meta_data->>'account_rut', '')
    );

    -- Notificar al admin
    INSERT INTO public.notifications (
      type, emoji, target, is_read, title, message, data
    ) VALUES (
      'alert', '🛵', 'admin', false,
      '🛵 Nuevo repartidor registrado',
      COALESCE(NEW.raw_user_meta_data->>'name', SPLIT_PART(NEW.email, '@', 1))
        || ' · ' || COALESCE(NEW.raw_user_meta_data->>'vehicle', 'Moto')
        || ' · ' || NEW.email,
      jsonb_build_object(
        'name', NULLIF(NEW.raw_user_meta_data->>'name', ''),
        'rut', NULLIF(NEW.raw_user_meta_data->>'rut', ''),
        'phone', NULLIF(NEW.raw_user_meta_data->>'phone', ''),
        'email', NEW.email,
        'vehicle', NULLIF(NEW.raw_user_meta_data->>'vehicle', ''),
        'plate', NULLIF(NEW.raw_user_meta_data->>'plate', ''),
        'contract_accepted', true,
        'privacy_accepted', true,
        'geolocation_authorized', true,
        'accepted_at', NULLIF(NEW.raw_user_meta_data->>'signed_at', ''),
        'contract_version', '1.0',
        'signer_name', NULLIF(NEW.raw_user_meta_data->>'signer_name', ''),
        'signer_rut', NULLIF(NEW.raw_user_meta_data->>'signer_rut', ''),
        'signed_at', NULLIF(NEW.raw_user_meta_data->>'signed_at', ''),
        'signature_image', NULL  -- La firma se envía por separado vía RPC (pesa 50-200KB+ y puede exceder límites de raw_user_meta_data)
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- RPC: submit_rider_signature(email, signature_base64)
-- ============================================================================
-- Permite que la app envíe la firma del rider DESPUÉS del signUp, cuando no
-- hay sesión (email sin confirmar). La firma puede pesar 50-200KB+ y no debe
-- viajar en raw_user_meta_data porque GoTrue puede rechazar el payload.
--
-- Solo actualiza notificaciones de riders con status 'pending' (recién creados).
-- Acepta anon key → usa SECURITY DEFINER para burlar RLS.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.submit_rider_signature(
  p_email text,
  p_signature text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_deliverer_id uuid;
  v_notification_id uuid;
BEGIN
  -- Buscar el user por email
  SELECT id INTO v_user_id FROM public.users WHERE email = p_email LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Usuario no encontrado');
  END IF;

  -- Buscar el deliverer asociado
  SELECT id INTO v_deliverer_id FROM public.deliverers WHERE user_id = v_user_id LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Repartidor no encontrado');
  END IF;

  -- Buscar la notificación más reciente de este rider (creada por el trigger)
  SELECT id INTO v_notification_id FROM public.notifications
  WHERE data->>'email' = p_email
    AND type = 'alert'
    AND emoji = '🛵'
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    -- Actualizar la notificación existente con la firma
    UPDATE public.notifications
    SET data = data || jsonb_build_object('signature_image', p_signature)
    WHERE id = v_notification_id;
  ELSE
    -- No hay notificación previa, crear una nueva con la firma
    INSERT INTO public.notifications (type, emoji, target, is_read, title, message, data)
    SELECT
      'alert', '🛵', 'admin', false,
      '🛵 Nuevo repartidor registrado',
      u.name || ' · ' || COALESCE(d.vehicle_type, 'Moto') || ' · ' || p_email,
      jsonb_build_object(
        'name', u.name,
        'rut', NULL,
        'phone', u.phone,
        'email', p_email,
        'vehicle', d.vehicle_type,
        'plate', d.vehicle_plate,
        'contract_accepted', true,
        'privacy_accepted', true,
        'geolocation_authorized', true,
        'accepted_at', now()::text,
        'contract_version', '1.0',
        'signature_image', p_signature
      )
    FROM public.users u
    JOIN public.deliverers d ON d.user_id = u.id
    WHERE u.id = v_user_id;
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;
