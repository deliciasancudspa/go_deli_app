-- ============================================================================
-- FEATURES V2: 10 mejoras GoRider (2026-07-18)
-- ============================================================================
-- Tablas: rider_payment_requests, rider_ratings, rider_challenges,
--         rider_challenge_progress
-- ALTER:  orders ADD tip_amount
-- RPCs:   request_payment, process_payment_request, rate_rider,
--         get_heatmap_data, get_rider_performance, get_active_challenges
-- Vistas: rider_rating_stats, rider_performance
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TABLAS NUEVAS
-- ═══════════════════════════════════════════════════════════════════════════

-- 1.1 Solicitudes de pago instantáneo ----------------------------------------
CREATE TABLE IF NOT EXISTS public.rider_payment_requests (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id    UUID REFERENCES public.deliverers(id) NOT NULL,
  amount      INT NOT NULL CHECK (amount > 0),
  commission  INT DEFAULT 990,
  net_amount  INT NOT NULL CHECK (net_amount > 0),
  status      TEXT DEFAULT 'pending'
              CHECK (status IN ('pending','approved','rejected','completed')),
  bank_info   JSONB,
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  processed_by UUID REFERENCES public.users(id),
  admin_note  TEXT
);

-- 1.2 Calificaciones de riders ------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rider_ratings (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id   UUID REFERENCES public.orders(id) UNIQUE NOT NULL,
  rider_id   UUID REFERENCES public.deliverers(id) NOT NULL,
  client_id  UUID REFERENCES public.users(id) NOT NULL,
  rating     INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment    TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 1.3 Desafíos / gamificación -------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rider_challenges (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title        TEXT NOT NULL,
  description  TEXT,
  type         TEXT NOT NULL CHECK (type IN ('streak','peak_pay','badge','mission')),
  target_count INT,
  bonus_amount INT,
  multiplier   DECIMAL(3,2),
  badge_emoji  TEXT,
  starts_at    TIMESTAMPTZ,
  ends_at      TIMESTAMPTZ,
  commune_id   UUID REFERENCES public.communes(id),
  is_active    BOOLEAN DEFAULT true,
  created_by   UUID REFERENCES public.users(id),
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- 1.4 Progreso de riders en desafíos ------------------------------------------
CREATE TABLE IF NOT EXISTS public.rider_challenge_progress (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id      UUID REFERENCES public.deliverers(id) NOT NULL,
  challenge_id  UUID REFERENCES public.rider_challenges(id) NOT NULL,
  current_count INT DEFAULT 0,
  completed     BOOLEAN DEFAULT false,
  completed_at  TIMESTAMPTZ,
  bonus_paid    BOOLEAN DEFAULT false,
  UNIQUE(rider_id, challenge_id)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. ALTERS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS tip_amount INT DEFAULT 0;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. VISTAS
-- ═══════════════════════════════════════════════════════════════════════════

-- 3.1 Promedio de rating por rider --------------------------------------------
CREATE OR REPLACE VIEW public.rider_rating_stats AS
SELECT
  rider_id,
  ROUND(AVG(rating)::numeric, 1) as avg_rating,
  COUNT(*) as total_ratings
FROM public.rider_ratings
GROUP BY rider_id;

-- 3.2 Métricas de desempeño por rider -----------------------------------------
CREATE OR REPLACE VIEW public.rider_performance AS
SELECT
  d.id as rider_id,
  d.user_id,
  COUNT(o.id) FILTER (WHERE o.status = 'delivered') as total_deliveries,
  COUNT(o.id) FILTER (WHERE o.status IN ('cancelled','returned')) as cancellations,
  SUM(o.rider_fee) FILTER (WHERE o.status = 'delivered') as total_earnings,
  SUM(o.tip_amount) FILTER (WHERE o.status = 'delivered') as total_tips,
  SUM(o.delivery_distance) FILTER (WHERE o.status = 'delivered') as total_distance_km,
  COALESCE(r.avg_rating, 0) as avg_rating,
  COALESCE(r.total_ratings, 0) as rating_count
FROM public.deliverers d
LEFT JOIN public.orders o ON o.deliverer_id = d.id
LEFT JOIN public.rider_rating_stats r ON r.rider_id = d.id
GROUP BY d.id, d.user_id, r.avg_rating, r.total_ratings;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPCs
-- ═══════════════════════════════════════════════════════════════════════════

-- 4.1 Rider solicita pago (1 vez al día) --------------------------------------
CREATE OR REPLACE FUNCTION public.request_payment(
  p_amount INT
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rider      UUID;
  v_commission INT := 990;
  v_net        INT;
  v_bank       JSONB;
  v_today      INT;
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

-- 4.2 Admin procesa solicitud de pago -----------------------------------------
CREATE OR REPLACE FUNCTION public.process_payment_request(
  p_request_id UUID,
  p_status     TEXT,
  p_note       TEXT DEFAULT NULL
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin      UUID;
  v_request    public.rider_payment_requests%rowtype;
  v_rider_name TEXT;
BEGIN
  -- Solo admin
  IF NOT public.is_admin() THEN RETURN 'not_admin'; END IF;

  v_admin := public.app_user_id();

  SELECT * INTO v_request FROM public.rider_payment_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RETURN 'not_found'; END IF;
  IF v_request.status != 'pending' AND p_status != 'completed' THEN
    RETURN 'already_processed';
  END IF;
  -- 'completed' solo desde 'approved'
  IF p_status = 'completed' AND v_request.status != 'approved' THEN
    RETURN 'must_approve_first';
  END IF;

  SELECT u.name INTO v_rider_name FROM public.deliverers d
  JOIN public.users u ON u.id = d.user_id WHERE d.id = v_request.rider_id;

  UPDATE public.rider_payment_requests SET
    status       = p_status,
    processed_at = CASE WHEN p_status IN ('approved','rejected','completed') THEN NOW() ELSE processed_at END,
    processed_by = CASE WHEN p_status IN ('approved','rejected','completed') THEN v_admin ELSE processed_by END,
    admin_note   = COALESCE(p_note, admin_note)
  WHERE id = p_request_id;

  -- Si se completa, registrar en rider_payments
  IF p_status = 'completed' THEN
    INSERT INTO public.rider_payments(deliverer_id, amount, status, created_at)
    VALUES (v_request.rider_id, v_request.net_amount, 'completed', NOW());
  END IF;

  -- Notificar al rider
  INSERT INTO public.notifications(target, type, emoji, title, message, is_read, data)
  VALUES (v_request.rider_id::text, 'payment_update', '💵',
    CASE p_status
      WHEN 'approved' THEN 'Pago aprobado'
      WHEN 'rejected' THEN 'Pago rechazado'
      WHEN 'completed' THEN 'Pago transferido'
      ELSE 'Pago actualizado'
    END,
    CASE p_status
      WHEN 'approved' THEN 'Tu solicitud de retiro por $' || v_request.net_amount || ' fue aprobada. El administrador realizará la transferencia.'
      WHEN 'rejected' THEN 'Tu solicitud de retiro fue rechazada. Motivo: ' || COALESCE(p_note, 'No especificado')
      WHEN 'completed' THEN 'Tu pago de $' || v_request.net_amount || ' fue transferido. Debería llegar a tu cuenta en minutos.'
      ELSE 'Tu solicitud fue actualizada.'
    END,
    FALSE, jsonb_build_object('request_id', p_request_id));

  RETURN 'ok';
END $$;
GRANT EXECUTE ON FUNCTION public.process_payment_request(UUID, TEXT, TEXT) TO authenticated;

-- 4.3 Cliente califica al rider -----------------------------------------------
CREATE OR REPLACE FUNCTION public.rate_rider(
  p_order_id UUID,
  p_rating   INT,
  p_comment  TEXT DEFAULT NULL
) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_client    UUID;
  v_order     public.orders%rowtype;
BEGIN
  v_client := public.app_user_id();
  IF v_client IS NULL THEN RETURN 'not_authenticated'; END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN 'order_not_found'; END IF;
  IF v_order.client_id != v_client THEN RETURN 'not_your_order'; END IF;
  IF v_order.status != 'delivered' THEN RETURN 'not_delivered'; END IF;
  IF v_order.deliverer_id IS NULL THEN RETURN 'no_rider'; END IF;

  -- Verificar que no haya sido calificado ya
  IF EXISTS (SELECT 1 FROM public.rider_ratings WHERE order_id = p_order_id) THEN
    RETURN 'already_rated';
  END IF;

  INSERT INTO public.rider_ratings (order_id, rider_id, client_id, rating, comment)
  VALUES (p_order_id, v_order.deliverer_id, v_client, p_rating, p_comment);

  -- Marcar orden como calificada
  UPDATE public.orders SET rated = true, rated_at = NOW() WHERE id = p_order_id;

  -- Notificar al rider (opcional, no queremos spamear)
  IF p_rating >= 4 THEN
    INSERT INTO public.notifications(target, type, emoji, title, message, is_read, data)
    VALUES (v_order.deliverer_id::text, 'rider_rating', '⭐',
            '¡Nueva calificación!', 'Un cliente te calificó con ' || p_rating || ' estrellas ⭐',
            FALSE, jsonb_build_object('order_id', p_order_id, 'rating', p_rating));
  END IF;

  RETURN 'ok';
END $$;
GRANT EXECUTE ON FUNCTION public.rate_rider(UUID, INT, TEXT) TO authenticated;

-- 4.4 Datos para mapa de calor ------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_heatmap_data(
  p_commune_id UUID DEFAULT NULL
) RETURNS TABLE(
  lat                DOUBLE PRECISION,
  lng                DOUBLE PRECISION,
  pending_count      INT,
  potential_earnings BIGINT
) LANGUAGE sql STABLE AS $$
  SELECT
    ROUND(s.lat::numeric, 3)::double precision as lat,
    ROUND(s.lng::numeric, 3)::double precision as lng,
    COUNT(*)::int as pending_count,
    SUM(o.total)::bigint as potential_earnings
  FROM public.orders o
  JOIN public.stores s ON s.id = o.store_id
  WHERE o.status IN ('pending','accepted','preparing','ready')
    AND o.deliverer_id IS NULL
    AND o.rider_search_status = 'searching'
    AND (p_commune_id IS NULL OR o.commune_id = p_commune_id)
  GROUP BY ROUND(s.lat::numeric, 3), ROUND(s.lng::numeric, 3)
  HAVING COUNT(*) >= 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_heatmap_data(UUID) TO authenticated;

-- 4.5 Métricas de desempeño para un rider -------------------------------------
CREATE OR REPLACE FUNCTION public.get_rider_performance(
  p_rider_id UUID DEFAULT NULL
) RETURNS TABLE(
  rider_id           UUID,
  total_deliveries   BIGINT,
  cancellations      BIGINT,
  total_earnings     BIGINT,
  total_tips         BIGINT,
  total_distance_km  BIGINT,
  avg_rating         NUMERIC,
  rating_count       BIGINT,
  top_percent        INT
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rider UUID;
  v_total INT;
  v_rank  INT;
BEGIN
  v_rider := COALESCE(p_rider_id, public.my_rider_id());
  IF v_rider IS NULL THEN RETURN; END IF;

  -- Calcular ranking
  SELECT COUNT(*) INTO v_total FROM public.deliverers WHERE status = 'approved';
  SELECT COUNT(*) + 1 INTO v_rank
  FROM public.rider_performance rp2
  WHERE rp2.total_deliveries > (SELECT total_deliveries FROM public.rider_performance WHERE rider_id = v_rider);

  RETURN QUERY
  SELECT
    rp.rider_id,
    rp.total_deliveries,
    rp.cancellations,
    rp.total_earnings,
    rp.total_tips,
    rp.total_distance_km,
    rp.avg_rating,
    rp.rating_count,
    CASE WHEN v_total > 0 THEN ((v_rank::decimal / v_total) * 100)::int ELSE 100 END as top_percent
  FROM public.rider_performance rp
  WHERE rp.rider_id = v_rider;
END $$;
GRANT EXECUTE ON FUNCTION public.get_rider_performance(UUID) TO authenticated;

-- 4.6 Desafíos activos con progreso del rider ---------------------------------
CREATE OR REPLACE FUNCTION public.get_active_challenges(
  p_rider_id UUID DEFAULT NULL
) RETURNS TABLE(
  challenge_id   UUID,
  title          TEXT,
  description    TEXT,
  type           TEXT,
  target_count   INT,
  bonus_amount   INT,
  multiplier     DECIMAL,
  badge_emoji    TEXT,
  ends_at        TIMESTAMPTZ,
  current_count  INT,
  completed      BOOLEAN,
  bonus_paid     BOOLEAN
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rider UUID;
BEGIN
  v_rider := COALESCE(p_rider_id, public.my_rider_id());
  IF v_rider IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    c.id,
    c.title,
    c.description,
    c.type,
    c.target_count,
    c.bonus_amount,
    c.multiplier,
    c.badge_emoji,
    c.ends_at,
    COALESCE(cp.current_count, 0) as current_count,
    COALESCE(cp.completed, false) as completed,
    COALESCE(cp.bonus_paid, false) as bonus_paid
  FROM public.rider_challenges c
  LEFT JOIN public.rider_challenge_progress cp ON cp.challenge_id = c.id AND cp.rider_id = v_rider
  WHERE c.is_active = true
    AND (c.starts_at IS NULL OR c.starts_at <= NOW())
    AND (c.ends_at IS NULL OR c.ends_at >= NOW())
    AND (c.commune_id IS NULL OR c.commune_id = (SELECT commune_id FROM public.deliverers WHERE id = v_rider))
  ORDER BY c.type, c.ends_at;
END $$;
GRANT EXECUTE ON FUNCTION public.get_active_challenges(UUID) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. TRIGGERS
-- ═══════════════════════════════════════════════════════════════════════════

-- 5.1 Actualizar progreso de desafíos al completar entrega --------------------
CREATE OR REPLACE FUNCTION public.update_challenge_progress_on_delivery()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_challenge RECORD;
  v_new_count INT;
BEGIN
  -- Solo cuando el pedido pasa a 'delivered'
  IF NEW.status = 'delivered' AND OLD.status != 'delivered' AND NEW.deliverer_id IS NOT NULL THEN
    -- Actualizar progreso en todos los desafíos activos tipo 'streak' y 'mission'
    FOR v_challenge IN
      SELECT c.id, c.target_count, c.bonus_amount, c.type
      FROM public.rider_challenges c
      WHERE c.is_active = true
        AND (c.starts_at IS NULL OR c.starts_at <= NOW())
        AND (c.ends_at IS NULL OR c.ends_at >= NOW())
        AND c.type IN ('streak', 'mission')
    LOOP
      -- Insertar o actualizar progreso
      INSERT INTO public.rider_challenge_progress (rider_id, challenge_id, current_count)
      VALUES (NEW.deliverer_id, v_challenge.id, 1)
      ON CONFLICT (rider_id, challenge_id)
      DO UPDATE SET
        current_count = rider_challenge_progress.current_count + 1,
        completed = CASE
          WHEN rider_challenge_progress.current_count + 1 >= v_challenge.target_count THEN true
          ELSE false
        END,
        completed_at = CASE
          WHEN rider_challenge_progress.current_count + 1 >= v_challenge.target_count
            AND rider_challenge_progress.completed_at IS NULL THEN NOW()
          ELSE rider_challenge_progress.completed_at
        END
      WHERE rider_challenge_progress.completed = false;

      -- Verificar si se completó ahora
      SELECT current_count INTO v_new_count
      FROM public.rider_challenge_progress
      WHERE rider_id = NEW.deliverer_id AND challenge_id = v_challenge.id;

      IF v_new_count >= v_challenge.target_count THEN
        -- Notificar al rider
        INSERT INTO public.notifications(target, type, emoji, title, message, is_read, data)
        VALUES (NEW.deliverer_id::text, 'challenge_complete', '🏆',
                '¡Desafío completado!',
                'Completaste el desafío y ganaste un bono de $' || v_challenge.bonus_amount,
                FALSE,
                jsonb_build_object('challenge_id', v_challenge.id, 'bonus', v_challenge.bonus_amount));

        -- Notificar al admin
        INSERT INTO public.notifications(target, type, emoji, title, message, is_read, data)
        VALUES ('admin', 'challenge_bonus', '🏆',
                'Bono por pagar',
                (SELECT u.name FROM public.deliverers d JOIN public.users u ON u.id = d.user_id WHERE d.id = NEW.deliverer_id)
                || ' completó un desafío. Bono: $' || v_challenge.bonus_amount,
                FALSE,
                jsonb_build_object('rider_id', NEW.deliverer_id, 'challenge_id', v_challenge.id, 'bonus', v_challenge.bonus_amount));
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END $$;

-- Aplicar el trigger (solo si no existe ya)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_update_challenge_progress'
  ) THEN
    CREATE TRIGGER trg_update_challenge_progress
      AFTER UPDATE OF status ON public.orders
      FOR EACH ROW EXECUTE FUNCTION public.update_challenge_progress_on_delivery();
  END IF;
END $$;

-- 5.2 Notificar admin de nueva solicitud de pago ------------------------------
CREATE OR REPLACE FUNCTION public.notify_admin_payment_request()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.notifications(target, type, emoji, title, message, is_read, data)
  SELECT 'admin', 'payment_request', '💵',
         'Nueva solicitud de retiro',
         u.name || ' solicita retirar $' || NEW.amount || ' (neto: $' || NEW.net_amount || ')',
         FALSE,
         jsonb_build_object('request_id', NEW.id, 'rider_id', NEW.rider_id)
  FROM public.deliverers d
  JOIN public.users u ON u.id = d.user_id
  WHERE d.id = NEW.rider_id;
  RETURN NEW;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'trg_notify_payment_request'
  ) THEN
    CREATE TRIGGER trg_notify_payment_request
      AFTER INSERT ON public.rider_payment_requests
      FOR EACH ROW EXECUTE FUNCTION public.notify_admin_payment_request();
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. RLS POLICIES
-- ═══════════════════════════════════════════════════════════════════════════

-- 6.1 rider_payment_requests --------------------------------------------------
DROP POLICY IF EXISTS "rider_payment_requests_select" ON public.rider_payment_requests;
CREATE POLICY "rider_payment_requests_select" ON public.rider_payment_requests
  FOR SELECT USING (
    rider_id = public.my_rider_id()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "rider_payment_requests_insert" ON public.rider_payment_requests;
CREATE POLICY "rider_payment_requests_insert" ON public.rider_payment_requests
  FOR INSERT WITH CHECK (
    rider_id = public.my_rider_id()
  );

DROP POLICY IF EXISTS "rider_payment_requests_update" ON public.rider_payment_requests;
CREATE POLICY "rider_payment_requests_update" ON public.rider_payment_requests
  FOR UPDATE USING (public.is_admin());

ALTER TABLE public.rider_payment_requests ENABLE ROW LEVEL SECURITY;

-- 6.2 rider_ratings -----------------------------------------------------------
DROP POLICY IF EXISTS "rider_ratings_select" ON public.rider_ratings;
CREATE POLICY "rider_ratings_select" ON public.rider_ratings
  FOR SELECT USING (
    rider_id = public.my_rider_id()
    OR client_id = public.app_user_id()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "rider_ratings_insert" ON public.rider_ratings;
CREATE POLICY "rider_ratings_insert" ON public.rider_ratings
  FOR INSERT WITH CHECK (
    client_id = public.app_user_id()
  );

ALTER TABLE public.rider_ratings ENABLE ROW LEVEL SECURITY;

-- 6.3 rider_challenges --------------------------------------------------------
DROP POLICY IF EXISTS "rider_challenges_select" ON public.rider_challenges;
CREATE POLICY "rider_challenges_select" ON public.rider_challenges
  FOR SELECT USING (
    public.my_rider_id() IS NOT NULL
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "rider_challenges_admin" ON public.rider_challenges;
CREATE POLICY "rider_challenges_admin" ON public.rider_challenges
  FOR ALL USING (public.is_admin());

ALTER TABLE public.rider_challenges ENABLE ROW LEVEL SECURITY;

-- 6.4 rider_challenge_progress ------------------------------------------------
DROP POLICY IF EXISTS "rider_challenge_progress_select" ON public.rider_challenge_progress;
CREATE POLICY "rider_challenge_progress_select" ON public.rider_challenge_progress
  FOR SELECT USING (
    rider_id = public.my_rider_id()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "rider_challenge_progress_insert" ON public.rider_challenge_progress;
CREATE POLICY "rider_challenge_progress_insert" ON public.rider_challenge_progress
  FOR INSERT WITH CHECK (
    rider_id = public.my_rider_id()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS "rider_challenge_progress_update" ON public.rider_challenge_progress;
CREATE POLICY "rider_challenge_progress_update" ON public.rider_challenge_progress
  FOR UPDATE USING (public.is_admin());

ALTER TABLE public.rider_challenge_progress ENABLE ROW LEVEL SECURITY;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. GRANTS para vistas
-- ═══════════════════════════════════════════════════════════════════════════

GRANT SELECT ON public.rider_rating_stats TO authenticated;
GRANT SELECT ON public.rider_performance TO authenticated;
