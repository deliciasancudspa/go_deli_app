-- ============================================================================
-- Go Business 2.0 — Mejoras POS v2 (Julio 2026)
-- ============================================================================
-- 1. Timestamp de cancelación en orders
-- 2. Detalles de variantes/opciones en order_items (para tickets y comandas)
-- ============================================================================

-- 1. TIMESTAMP DE CANCELACIÓN ─────────────────────────────────────────────────
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- 2. DETALLES DE VARIANTES/OPCIONES ──────────────────────────────────────────
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS variant_details TEXT;
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS option_details TEXT;
