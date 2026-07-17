-- ============================================================================
-- REPORTE DE INCIDENTE DEL RIDER
-- ============================================================================
-- Permite que un rider reporte un accidente/emergencia durante una entrega.
-- El pedido se re-despacha automáticamente al siguiente rider disponible,
-- usando la ubicación del incidente como punto de recogida.
-- Las ganancias (rider_fee) van al nuevo rider que completa la entrega.
-- ============================================================================

-- 1. Columnas de incidente en orders ------------------------------------------
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS incident_lat           DOUBLE PRECISION;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS incident_lng           DOUBLE PRECISION;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS incident_reason        TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS original_deliverer_id  UUID;

-- 2. Agregar 'incident' al constraint de status -------------------------------
-- (idempotente: si ya existe no hace nada, si no lo agrega)
DO $$
BEGIN
  ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
  ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
  CHECK (status IN (
      'pending_payment',
      'pending',
      'accepted',
      'preparing',
      'ready',
      'assigned',
      'picked_up',
      'on_the_way',
      'delivered',
      'cancelled',
      'returned',
      'incident'
  ));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 3. RPC: rider_report_incident -----------------------------------------------
-- El rider reporta un incidente (accidente, avería, emergencia, pedido dañado).
-- El pedido se pone en status='incident' para auditoría y luego se re-despacha.
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

  -- Guardar incidente y resetear para re-despacho
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

  -- Limpiar intentos previos de despacho
  DELETE FROM order_dispatch_attempts WHERE order_id = p_order_id;

  -- Desactivar rider original (está varado, no puede tomar más pedidos)
  UPDATE deliverers SET is_available = FALSE WHERE id = v_rider;

  -- Notificar al admin
  INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
  VALUES ('admin', 'rider_incident', '🆘', '🚨 Incidente reportado',
          v_rider_name || ' reportó ' ||
          CASE p_reason
            WHEN 'vehicle_breakdown' THEN 'vehículo averiado'
            WHEN 'traffic_accident' THEN 'accidente de tránsito'
            WHEN 'medical_emergency' THEN 'emergencia médica'
            WHEN 'damaged_order'    THEN 'pedido dañado'
            ELSE p_reason
          END || '. Pedido #' || v_codigo || ' en re-despacho.',
          FALSE,
          jsonb_build_object(
            'order_id',    p_order_id,
            'rider_id',    v_rider,
            'rider_name',  v_rider_name,
            'reason',      p_reason,
            'note',        p_note,
            'lat',         p_lat,
            'lng',         p_lng,
            'store_name',  v_store_name
          ));

  -- Notificar al cliente
  IF v_client_id IS NOT NULL THEN
    INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
    VALUES (v_client_id::text, 'order_update', '🛵',
            'Tu repartidor tuvo un contratiempo',
            'Estamos reasignando tu pedido #' || v_codigo ||
            '. Te avisaremos cuando un nuevo repartidor esté en camino.',
            FALSE,
            jsonb_build_object('order_id', p_order_id));
  END IF;

  -- Iniciar re-despacho inmediato
  PERFORM public.dispatch_offer_next(p_order_id);

  RETURN 'ok';
END $$;
GRANT EXECUTE ON FUNCTION public.rider_report_incident(UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

-- 4. Modificar dispatch_offer_next: usar ubicación del incidente como pickup --
-- cuando el pedido viene de un re-despacho por incidente.
CREATE OR REPLACE FUNCTION public.dispatch_offer_next(p_order_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order      orders%rowtype;
  v_store_lat  double precision;
  v_store_lng  double precision;
  v_rider      uuid;
  v_round      int;
  v_phase      text;
  v_timeout    int := 45;
  v_max_rounds int := 3;
BEGIN
  PERFORM set_config('dispatch.bypass', '1', true);
  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN 'not_found'; END IF;
  IF v_order.rider_search_status IS DISTINCT FROM 'searching' THEN RETURN 'not_searching'; END IF;
  IF v_order.deliverer_id IS NOT NULL THEN RETURN 'already_assigned'; END IF;

  -- ═══ Pickup: ubicación del incidente si existe, si no la tienda ═══
  IF v_order.incident_lat IS NOT NULL AND v_order.incident_lng IS NOT NULL THEN
    v_store_lat := v_order.incident_lat;
    v_store_lng := v_order.incident_lng;
  ELSE
    SELECT s.lat, s.lng INTO v_store_lat, v_store_lng FROM stores s WHERE s.id = v_order.store_id;
  END IF;

  v_round := GREATEST(COALESCE(v_order.dispatch_round, 0), 1);
  IF v_order.dispatch_round IS DISTINCT FROM v_round THEN
    UPDATE orders SET dispatch_round = v_round WHERE id = p_order_id;
  END IF;

  -- FASE 1: riders LIBRES
  SELECT d.id INTO v_rider
  FROM deliverers d
  WHERE d.status = 'approved' AND d.is_online = true
    AND (v_order.commune_id IS NULL OR d.commune_id IS NULL OR d.commune_id = v_order.commune_id)
    AND (v_store_lat IS NULL OR v_store_lng IS NULL
         OR d.current_lat IS NULL OR d.current_lng IS NULL
         OR haversine_m(v_store_lat, v_store_lng, d.current_lat, d.current_lng) <= 10000)
    AND NOT EXISTS (SELECT 1 FROM order_dispatch_attempts a
                    WHERE a.order_id = p_order_id AND a.round = v_round AND a.rider_id = d.id)
    AND NOT EXISTS (SELECT 1 FROM orders o2
                    WHERE o2.deliverer_id = d.id AND o2.status IN ('assigned','picked_up','on_the_way'))
    AND NOT EXISTS (SELECT 1 FROM orders o3
                    WHERE o3.current_offer_rider_id = d.id AND o3.current_offer_expires_at > now())
  ORDER BY CASE WHEN v_store_lat IS NULL OR d.current_lat IS NULL THEN 1 ELSE 0 END,
           haversine_m(v_store_lat, v_store_lng, d.current_lat, d.current_lng) ASC
  LIMIT 1;
  v_phase := 'free';

  -- FASE 2: riders EN RUTA
  IF v_rider IS NULL THEN
    SELECT d.id INTO v_rider
    FROM deliverers d
    WHERE d.status = 'approved' AND d.is_online = true
      AND (v_order.commune_id IS NULL OR d.commune_id IS NULL OR d.commune_id = v_order.commune_id)
      AND (v_store_lat IS NULL OR v_store_lng IS NULL
           OR d.current_lat IS NULL OR d.current_lng IS NULL
           OR haversine_m(v_store_lat, v_store_lng, d.current_lat, d.current_lng) <= 10000)
      AND NOT EXISTS (SELECT 1 FROM order_dispatch_attempts a
                      WHERE a.order_id = p_order_id AND a.round = v_round AND a.rider_id = d.id)
      AND NOT EXISTS (SELECT 1 FROM orders o3
                      WHERE o3.current_offer_rider_id = d.id AND o3.current_offer_expires_at > now())
      AND NOT EXISTS (SELECT 1 FROM orders o4
                      WHERE o4.deliverer_id = d.id AND o4.is_queued = true
                        AND o4.status IN ('assigned','picked_up','on_the_way'))
      AND EXISTS (SELECT 1 FROM orders o5
                  WHERE o5.deliverer_id = d.id AND o5.status = 'on_the_way')
    ORDER BY (SELECT MIN(o6.updated_at) FROM orders o6
              WHERE o6.deliverer_id = d.id AND o6.status = 'on_the_way') ASC
    LIMIT 1;
    v_phase := 'in_route';
  END IF;

  IF v_rider IS NOT NULL THEN
    UPDATE orders SET
      current_offer_rider_id   = v_rider,
      current_offer_expires_at = now() + make_interval(secs => v_timeout),
      dispatch_phase           = v_phase,
      is_queued                = (v_phase = 'in_route'),
      status                   = CASE WHEN status = 'incident' THEN 'assigned' ELSE status END
    WHERE id = p_order_id;

    INSERT INTO order_dispatch_attempts(order_id, rider_id, round, kind)
    VALUES (p_order_id, v_rider, v_round, 'offered');

    INSERT INTO notifications(target, type, emoji, title, message, is_read, data)
    SELECT v_rider::text, 'order_offer', '🛵',
           CASE WHEN o.incident_lat IS NOT NULL
                THEN '🆘 Pedido de rescate'
                ELSE 'Nuevo pedido disponible' END,
           coalesce(s.emoji,'🍽️') || ' ' || coalesce(s.name,'Tienda') || ' — ' || coalesce(o.delivery_address,''),
           false,
           jsonb_build_object(
             'order_id', p_order_id,
             'store_name', s.name, 'store_emoji', s.emoji,
             'delivery_address', o.delivery_address,
             'delivery_reference', o.delivery_reference,
             'total', o.total, 'payment_method', o.payment_method,
             'rider_fee', o.rider_fee,
             'distance_km', CASE WHEN o.delivery_distance IS NOT NULL
                                 THEN round((o.delivery_distance/1000.0)::numeric, 1)::text ELSE null END,
             'queued', (v_phase = 'in_route'),
             'is_rescue', (o.incident_lat IS NOT NULL),
             'incident_reason', o.incident_reason,
             'pickup_lat', COALESCE(o.incident_lat, s.lat),
             'pickup_lng', COALESCE(o.incident_lng, s.lng)
           )
    FROM orders o LEFT JOIN stores s ON s.id = o.store_id
    WHERE o.id = p_order_id;

    RETURN 'offered_' || v_phase;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM deliverers d WHERE d.status = 'approved' AND d.is_online = true) THEN
    UPDATE orders SET rider_search_status = 'needs_manual',
                      current_offer_rider_id = null, current_offer_expires_at = null
    WHERE id = p_order_id;
    PERFORM notify_admin_no_rider(p_order_id, 'Sin repartidores en línea');
    RETURN 'needs_manual_no_riders';
  END IF;

  PERFORM notify_admin_no_rider(p_order_id, 'Nadie aceptó (ronda ' || v_round || ')');
  IF v_round >= v_max_rounds THEN
    UPDATE orders SET rider_search_status = 'needs_manual',
                      current_offer_rider_id = null, current_offer_expires_at = null
    WHERE id = p_order_id;
    RETURN 'needs_manual_max_rounds';
  END IF;

  UPDATE orders SET dispatch_round = v_round + 1 WHERE id = p_order_id;
  RETURN public.dispatch_offer_next(p_order_id);
END $$;
