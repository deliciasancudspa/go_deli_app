-- ============================================================================
-- Go Business 2.0 — Caja y Pagos (Julio 2026)
-- ============================================================================
-- 1. Desglose de billetes/monedas en cash_sessions
-- 2. Entrada/salida de efectivo (voucher_number en cash_movements)
-- 3. Split de pagos (order_payments)
-- 4. Descuentos con tipo en orders
-- ============================================================================

-- 1. DESGLOSE DE BILLETES/MONEDAS ──────────────────────────────────────────
ALTER TABLE public.cash_sessions ADD COLUMN IF NOT EXISTS opening_breakdown JSONB;
ALTER TABLE public.cash_sessions ADD COLUMN IF NOT EXISTS closing_breakdown JSONB;

-- 2. COMPROBANTE EN MOVIMIENTOS ────────────────────────────────────────────
ALTER TABLE public.cash_movements ADD COLUMN IF NOT EXISTS voucher_number TEXT;

-- 3. DESCUENTOS CON TIPO ──────────────────────────────────────────────────
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_type TEXT DEFAULT 'fixed';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount_value INTEGER DEFAULT 0;

-- 4. SPLIT DE PAGOS ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.order_payments (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  order_id        UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  payment_method  TEXT NOT NULL,
  amount          INTEGER NOT NULL,
  voucher_number  TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_order_payments_order ON public.order_payments(order_id);

-- 5. POLITICAS RLS ────────────────────────────────────────────────────────
-- order_payments: mismo patrón que order_items (a través del pedido → tienda)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname='public' AND tablename='order_payments') THEN
    DROP POLICY IF EXISTS order_payments_select ON public.order_payments;
    CREATE POLICY order_payments_select ON public.order_payments FOR SELECT TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.stores s ON o.store_id = s.id
          WHERE o.id = order_payments.order_id AND s.owner_id = auth.uid()
        )
        OR public.is_admin()
      );

    DROP POLICY IF EXISTS order_payments_insert ON public.order_payments;
    CREATE POLICY order_payments_insert ON public.order_payments FOR INSERT TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.stores s ON o.store_id = s.id
          WHERE o.id = order_payments.order_id AND s.owner_id = auth.uid()
        )
        OR public.is_admin()
      );

    DROP POLICY IF EXISTS order_payments_update ON public.order_payments;
    CREATE POLICY order_payments_update ON public.order_payments FOR UPDATE TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.stores s ON o.store_id = s.id
          WHERE o.id = order_payments.order_id AND s.owner_id = auth.uid()
        )
        OR public.is_admin()
      );

    DROP POLICY IF EXISTS order_payments_delete ON public.order_payments;
    CREATE POLICY order_payments_delete ON public.order_payments FOR DELETE TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.orders o
          JOIN public.stores s ON o.store_id = s.id
          WHERE o.id = order_payments.order_id AND s.owner_id = auth.uid()
        )
        OR public.is_admin()
      );
  END IF;
END $$;
