-- ============================================================================
-- FIX: Validación de saldo positivo en retiro + marcar pedidos como liquidados
-- ============================================================================

-- 1. Añadir last_settlement_at a deliverers ------------------------------------
ALTER TABLE public.deliverers
  ADD COLUMN IF NOT EXISTS last_settlement_at TIMESTAMPTZ;

-- 2. Reemplazar request_payment con validación de saldo -------------------------
CREATE OR REPLACE FUNCTION public.request_payment(
  p_amount INT
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rider             UUID;
  v_commission        INT := 990;
  v_net               INT;
  v_bank              JSONB;
  v_today             INT;
  v_last_settlement   TIMESTAMPTZ;
  v_card_earnings     NUMERIC := 0;
  v_cash_to_remit     NUMERIC := 0;
  v_cash_handled      NUMERIC := 0;
  v_cash_earnings     NUMERIC := 0;
  v_available_balance INT := 0;
BEGIN
  v_rider := public.my_rider_id();
  IF v_rider IS NULL THEN RETURN 'not_rider'; END IF;

  -- Validar que no haya retirado hoy
  SELECT COUNT(*) INTO v_today
  FROM public.rider_payment_requests
  WHERE rider_id = v_rider
    AND requested_at::date = CURRENT_DATE
    AND status != 'rejected';
  IF v_today > 0 THEN RETURN 'already_requested_today'; END IF;

  -- Validar monto mínimo
  IF p_amount < 2000 THEN RETURN 'amount_too_low'; END IF;

  -- Obtener la fecha del último retiro (solo pedidos posteriores están disponibles)
  SELECT last_settlement_at INTO v_last_settlement
  FROM public.deliverers WHERE id = v_rider;

  -- Calcular saldo disponible: solo pedidos con tarjeta no liquidados,
  -- menos el efectivo que el rider debe rendir a la plataforma.
  -- Fórmula: card_earnings (unsettled) - cash_to_remit (unsettled)
  -- cash_to_remit = cash_handled - cash_earnings

  -- Ganancias de tarjeta (unsettled)
  SELECT COALESCE(SUM(o.rider_fee), 0) INTO v_card_earnings
  FROM public.orders o
  WHERE o.deliverer_id = v_rider
    AND o.status = 'delivered'
    AND o.payment_method != 'cash'
    AND (v_last_settlement IS NULL OR o.created_at > v_last_settlement);

  -- Efectivo cobrado a clientes (unsettled)
  SELECT COALESCE(SUM(o.total), 0) INTO v_cash_handled
  FROM public.orders o
  WHERE o.deliverer_id = v_rider
    AND o.status = 'delivered'
    AND o.payment_method = 'cash'
    AND (v_last_settlement IS NULL OR o.created_at > v_last_settlement);

  -- Ganancias de efectivo (lo que le corresponde al rider de pedidos cash)
  SELECT COALESCE(SUM(o.rider_fee), 0) INTO v_cash_earnings
  FROM public.orders o
  WHERE o.deliverer_id = v_rider
    AND o.status = 'delivered'
    AND o.payment_method = 'cash'
    AND (v_last_settlement IS NULL OR o.created_at > v_last_settlement);

  -- Lo que el rider debe rendir del efectivo cobrado
  v_cash_to_remit := v_cash_handled - v_cash_earnings;

  -- Balance disponible = ganancias tarjeta - efectivo a rendir
  v_available_balance := (v_card_earnings - v_cash_to_remit)::INT;

  -- Si el saldo es negativo (debe rendir efectivo), no puede retirar
  IF v_available_balance <= 0 THEN
    RETURN 'negative_balance';
  END IF;

  -- El monto solicitado no puede superar el saldo disponible
  IF p_amount > v_available_balance THEN
    RETURN 'amount_exceeds_balance';
  END IF;

  v_net := p_amount - v_commission;

  -- Obtener datos bancarios
  SELECT jsonb_build_object(
    'bank_name', bi.bank_name,
    'account_type', bi.account_type,
    'account_number', bi.account_number,
    'account_holder', bi.account_holder,
    'rut', bi.rut
  ) INTO v_bank
  FROM public.deliverer_bank_info bi
  WHERE bi.deliverer_id = v_rider
  LIMIT 1;

  INSERT INTO public.rider_payment_requests (
    rider_id, amount, commission, net_amount, bank_info
  ) VALUES (v_rider, p_amount, v_commission, v_net, v_bank);

  -- Marcar pedidos como liquidados: actualizar last_settlement_at
  UPDATE public.deliverers
  SET last_settlement_at = NOW()
  WHERE id = v_rider;

  -- Notificar al admin
  INSERT INTO public.notifications(target, type, emoji, title, message, is_read, data)
  SELECT 'admin', 'payment_request', '💵',
         'Nueva solicitud de pago',
         u.name || ' solicita retirar $' || p_amount || ' (neto: $' || v_net || ')',
         FALSE,
         jsonb_build_object('request_id', currval('rider_payment_requests_id_seq'::regclass)::text, 'rider_id', v_rider)
  FROM public.users u WHERE u.id = (SELECT user_id FROM public.deliverers WHERE id = v_rider);

  RETURN 'ok';
END $$;
GRANT EXECUTE ON FUNCTION public.request_payment(INT) TO authenticated;
