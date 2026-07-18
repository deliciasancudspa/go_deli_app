-- ============================================================================
-- FIX: get_rider_performance() — ambiguous column + type mismatch
-- ============================================================================
-- 1. "total_deliveries" era ambiguo entre OUT parameter y columna de la vista
--    → Fix: calificar con alias (rp3.total_deliveries) en la subquery.
-- 2. total_earnings/total_tips/total_distance_km de la vista son NUMERIC,
--    no BIGINT → cambiamos RETURNS TABLE para que coincida.
-- ============================================================================

-- Necesitamos DROP porque CREATE OR REPLACE no permite cambiar tipos de retorno
DROP FUNCTION IF EXISTS public.get_rider_performance(UUID);

CREATE OR REPLACE FUNCTION public.get_rider_performance(
  p_rider_id UUID DEFAULT NULL
) RETURNS TABLE(
  rider_id           UUID,
  total_deliveries   BIGINT,
  cancellations      BIGINT,
  total_earnings     NUMERIC,
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

  -- Calcular ranking (solo contra riders aprobados, rp3 alias evita ambigüedad)
  SELECT COUNT(*) INTO v_total FROM public.deliverers WHERE status = 'approved';
  SELECT COUNT(*) + 1 INTO v_rank
  FROM public.rider_performance rp2
  JOIN public.deliverers d2 ON d2.id = rp2.rider_id AND d2.status = 'approved'
  WHERE rp2.total_deliveries > (SELECT rp3.total_deliveries FROM public.rider_performance rp3 WHERE rp3.rider_id = v_rider);

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
