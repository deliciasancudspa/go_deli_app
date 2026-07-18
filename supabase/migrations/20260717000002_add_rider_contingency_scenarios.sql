-- ============================================================================
-- ESCENARIOS DE CONTINGENCIA DEL RIDER (2026-07-17)
-- ============================================================================
-- Agrega: tienda cerrada, cliente agresivo (SOS), cambio de dirección,
--         aviso de demora, pedido robado.
-- ============================================================================

-- 1. ACTUALIZAR rider_report_incident: agregar 'stolen' (pedido robado) -------
CREATE OR REPLACE FUNCTION public.rider_report_incident(
  p_order_id UUID,
  p_reason   TEXT,
  p_note     TEXT,
  p_lat      DOUBLE PRECISION,
  p_lng      DOUBLE PRECISION
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rider       UUID;
  v_order       orders%rowtype;
  v_store_name  TEXT;
  v_rider_name  TEXT;
  v_client_id   UUID;
  v_codigo      TEXT;
BEGIN
  PERFORM set_config('dispatch.bypass', '1', true);
  v_rider := public.my_rider_id();
  IF v_rider IS NULL THEN RETURN 'not_rider'; END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN 'order_not_found'; END IF;
  IF v_order.deliverer_id != v_rider THEN RETURN 'not_your_order'; END IF;
  IF v_order.status NOT IN ('assigned','picked_up','on_the_way') THEN RETURN 'invalid_status'; END IF;

  SELECT name INTO v_store_name FROM stores WHERE id = v_order.store_id;
  SELECT u.name INTO v_rider_name FROM deliverers d JOIN users u ON u.id = d.user_id WHERE d.id = v_rider;
  v_client_id := v_order.client_id;
  v_codigo := UPPER(SUBSTR(p_order_id::text, 1, 8));

  -- Si fue robado, NO re-despachar: la tienda debe rehacer el pedido
  IF p_reason = 'stolen' THEN
    UPDATE orders SET
      incident_lat            = p_lat,
      incident_lng            = p_lng,
      incident_reason         = p_reason,
      original_deliverer_id   = v_rider,
      return_reason           = p_reason,
      return_note             = p_note,
      returned_at             = NOW(),
      status                  = 'cancelled',
      deliverer_id            = NULL,
      current_offer_rider_id  = NULL,
      current_offer_expires_at = NULL,
      rider_search_status     = 'needs_manual'
    WHERE id = p_order_id;

    UPDATE deliverers SET is_available = FALSE WHERE id = v_rider;

    INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
    VALUES ('admin', 'rider_incident', '🚨', '🚨 Pedido ROBADO',
            v_rider_name || ' reportó ROBO del pedido #' || v_codigo || '. ' ||
            COALESCE(p_note, 'Sin detalles adicionales.'),
            FALSE,
            jsonb_build_object(
              'order_id', p_order_id, 'rider_id', v_rider, 'rider_name', v_rider_name,
              'reason', p_reason, 'note', p_note,
              'lat', p_lat, 'lng', p_lng, 'store_name', v_store_name,
              'needs_manual', true
            ));

    IF v_client_id IS NOT NULL THEN
      INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
      VALUES (v_client_id::text, 'order_update', '❌', 'Problema con tu pedido',
              'Tu pedido #' || v_codigo || ' tuvo un contratiempo. La tienda se contactará contigo.',
              FALSE, jsonb_build_object('order_id', p_order_id));
    END IF;

    RETURN 'ok';
  END IF;

  -- Otros incidentes: re-despachar
  UPDATE orders SET
    incident_lat            = p_lat,
    incident_lng            = p_lng,
    incident_reason         = p_reason,
    original_deliverer_id   = v_rider,
    return_reason           = p_reason,
    return_note             = p_note,
    returned_at             = NOW(),
    status                  = 'incident',
    deliverer_id            = NULL,
    current_offer_rider_id  = NULL,
    current_offer_expires_at = NULL,
    rider_search_status     = 'searching',
    dispatch_round          = 1,
    is_queued               = FALSE
  WHERE id = p_order_id;

  DELETE FROM order_dispatch_attempts WHERE order_id = p_order_id;
  UPDATE deliverers SET is_available = FALSE WHERE id = v_rider;

  INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
  VALUES ('admin', 'rider_incident', '🆘', '🚨 Incidente reportado',
          v_rider_name || ' reportó ' ||
          CASE p_reason
            WHEN 'vehicle_breakdown' THEN 'vehículo averiado'
            WHEN 'traffic_accident'  THEN 'accidente de tránsito'
            WHEN 'medical_emergency' THEN 'emergencia médica'
            WHEN 'damaged_order'     THEN 'pedido dañado'
            ELSE p_reason
          END || '. Pedido #' || v_codigo || ' en re-despacho.',
          FALSE,
          jsonb_build_object(
            'order_id', p_order_id, 'rider_id', v_rider, 'rider_name', v_rider_name,
            'reason', p_reason, 'note', p_note,
            'lat', p_lat, 'lng', p_lng, 'store_name', v_store_name
          ));

  IF v_client_id IS NOT NULL THEN
    INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
    VALUES (v_client_id::text, 'order_update', '🛵',
            'Tu repartidor tuvo un contratiempo',
            'Estamos reasignando tu pedido #' || v_codigo || '. Te avisaremos cuando un nuevo repartidor esté en camino.',
            FALSE, jsonb_build_object('order_id', p_order_id));
  END IF;

  PERFORM public.dispatch_offer_next(p_order_id);
  RETURN 'ok';
END $$;
GRANT EXECUTE ON FUNCTION public.rider_report_incident(UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

-- 2. Tienda cerrada -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rider_report_store_closed(
  p_order_id UUID,
  p_note     TEXT
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rider       UUID;
  v_order       orders%rowtype;
  v_rider_name  TEXT;
  v_store_name  TEXT;
  v_client_id   UUID;
  v_codigo      TEXT;
BEGIN
  PERFORM set_config('dispatch.bypass', '1', true);
  v_rider := public.my_rider_id();
  IF v_rider IS NULL THEN RETURN 'not_rider'; END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN 'order_not_found'; END IF;
  IF v_order.deliverer_id != v_rider THEN RETURN 'not_your_order'; END IF;
  IF v_order.status != 'assigned' THEN RETURN 'invalid_status'; END IF;

  SELECT u.name INTO v_rider_name FROM deliverers d JOIN users u ON u.id = d.user_id WHERE d.id = v_rider;
  SELECT name INTO v_store_name FROM stores WHERE id = v_order.store_id;
  v_client_id := v_order.client_id;
  v_codigo := UPPER(SUBSTR(p_order_id::text, 1, 8));

  UPDATE orders SET
    status        = 'cancelled',
    return_reason = 'store_closed',
    return_note   = p_note,
    returned_at   = NOW(),
    deliverer_id  = NULL
  WHERE id = p_order_id;

  INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
  VALUES ('admin', 'store_closed', '🏪', 'Tienda cerrada',
          v_rider_name || ' reportó que ' || v_store_name || ' estaba cerrada. Pedido #' || v_codigo || ' cancelado.',
          FALSE,
          jsonb_build_object(
            'order_id', p_order_id, 'rider_id', v_rider, 'rider_name', v_rider_name,
            'store_name', v_store_name, 'note', p_note
          ));

  IF v_client_id IS NOT NULL THEN
    INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
    VALUES (v_client_id::text, 'order_update', '🏪',
            'Tienda cerrada — Pedido #' || v_codigo,
            'Lamentablemente la tienda ' || v_store_name || ' estaba cerrada. Tu pedido fue cancelado. La tienda se contactará contigo.',
            FALSE, jsonb_build_object('order_id', p_order_id));
  END IF;

  RETURN 'ok';
END $$;
GRANT EXECUTE ON FUNCTION public.rider_report_store_closed(UUID, TEXT) TO authenticated;

-- 3. Alerta SOS (cliente agresivo) --------------------------------------------
CREATE OR REPLACE FUNCTION public.rider_sos_alert(
  p_order_id UUID,
  p_lat      DOUBLE PRECISION,
  p_lng      DOUBLE PRECISION,
  p_note     TEXT
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rider       UUID;
  v_order       orders%rowtype;
  v_rider_name  TEXT;
  v_rider_phone TEXT;
  v_codigo      TEXT;
BEGIN
  PERFORM set_config('dispatch.bypass', '1', true);
  v_rider := public.my_rider_id();
  IF v_rider IS NULL THEN RETURN 'not_rider'; END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN 'order_not_found'; END IF;
  IF v_order.deliverer_id != v_rider THEN RETURN 'not_your_order'; END IF;
  IF v_order.status NOT IN ('picked_up','on_the_way') THEN RETURN 'invalid_status'; END IF;

  SELECT u.name, u.phone INTO v_rider_name, v_rider_phone FROM deliverers d JOIN users u ON u.id = d.user_id WHERE d.id = v_rider;
  v_codigo := UPPER(SUBSTR(p_order_id::text, 1, 8));

  -- Marcar el pedido con alerta de seguridad (no cancelar, admin decide)
  UPDATE orders SET
    return_reason = 'safety_alert',
    return_note   = p_note,
    incident_lat  = p_lat,
    incident_lng  = p_lng
  WHERE id = p_order_id;

  -- SOS al admin (máxima prioridad)
  INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
  VALUES ('admin', 'sos_alert', '🆘', '🆘 ALERTA DE SEGURIDAD — Rider en peligro',
          v_rider_name || ' activó la alerta de seguridad en pedido #' || v_codigo || '. ' ||
          '📞 Tel rider: ' || COALESCE(v_rider_phone, 'No registrado') || '. ' ||
          COALESCE(p_note, ''),
          FALSE,
          jsonb_build_object(
            'order_id',   p_order_id,
            'rider_id',   v_rider,
            'rider_name', v_rider_name,
            'rider_phone', v_rider_phone,
            'lat',        p_lat,
            'lng',        p_lng,
            'note',       p_note,
            'priority',   'critical'
          ));

  RETURN 'ok';
END $$;
GRANT EXECUTE ON FUNCTION public.rider_sos_alert(UUID, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO authenticated;

-- 4. Avisar demora en tienda --------------------------------------------------
CREATE OR REPLACE FUNCTION public.rider_notify_delay(
  p_order_id UUID,
  p_minutes  INT,
  p_note     TEXT
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rider      UUID;
  v_order      orders%rowtype;
  v_client_id  UUID;
  v_codigo     TEXT;
BEGIN
  PERFORM set_config('dispatch.bypass', '1', true);
  v_rider := public.my_rider_id();
  IF v_rider IS NULL THEN RETURN 'not_rider'; END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN 'order_not_found'; END IF;
  IF v_order.deliverer_id != v_rider THEN RETURN 'not_your_order'; END IF;
  IF v_order.status != 'assigned' THEN RETURN 'invalid_status'; END IF;

  v_client_id := v_order.client_id;
  v_codigo := UPPER(SUBSTR(p_order_id::text, 1, 8));

  IF v_client_id IS NOT NULL THEN
    INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
    VALUES (v_client_id::text, 'order_update', '⏳',
            'Tu pedido sigue en preparación',
            'El repartidor está esperando en la tienda (~' || p_minutes || ' min de demora). ' ||
            COALESCE(p_note, ''),
            FALSE, jsonb_build_object('order_id', p_order_id));
  END IF;

  RETURN 'ok';
END $$;
GRANT EXECUTE ON FUNCTION public.rider_notify_delay(UUID, INT, TEXT) TO authenticated;

-- 5. Confirmar entrega sin código (verificación alternativa) -------------------
CREATE OR REPLACE FUNCTION public.rider_confirm_delivery_override(
  p_order_id UUID
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rider      UUID;
  v_order      orders%rowtype;
  v_rider_name TEXT;
  v_codigo     TEXT;
BEGIN
  PERFORM set_config('dispatch.bypass', '1', true);
  v_rider := public.my_rider_id();
  IF v_rider IS NULL THEN RETURN 'not_rider'; END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN 'order_not_found'; END IF;
  IF v_order.deliverer_id != v_rider THEN RETURN 'not_your_order'; END IF;
  IF v_order.status != 'on_the_way' THEN RETURN 'invalid_status'; END IF;

  SELECT u.name INTO v_rider_name FROM deliverers d JOIN users u ON u.id = d.user_id WHERE d.id = v_rider;
  v_codigo := UPPER(SUBSTR(p_order_id::text, 1, 8));

  UPDATE orders SET
    status                = 'delivered',
    delivery_verified_by  = 'rider_override',
    delivery_note         = 'Sin código — verificación alternativa'
  WHERE id = p_order_id;

  INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
  VALUES ('admin', 'delivery_override', '⚠️',
          'Entrega sin código',
          v_rider_name || ' confirmó entrega #' || v_codigo || ' sin código (verificación alternativa). Revisar.',
          FALSE,
          jsonb_build_object('order_id', p_order_id));

  RETURN 'ok';
END $$;
GRANT EXECUTE ON FUNCTION public.rider_confirm_delivery_override(UUID) TO authenticated;
