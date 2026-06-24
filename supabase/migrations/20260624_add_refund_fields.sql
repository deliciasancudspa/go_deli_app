-- Campos para reembolsos Webpay (refund / anulación)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS refund_amount   NUMERIC(12,0);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS refund_status   TEXT;    -- null | partial | full
ALTER TABLE orders ADD COLUMN IF NOT EXISTS refund_response JSONB;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS refunded_at     TIMESTAMPTZ;

COMMENT ON COLUMN orders.refund_amount   IS 'Monto reembolsado al cliente (puede ser parcial)';
COMMENT ON COLUMN orders.refund_status   IS 'null = sin reembolso | partial = reembolso parcial | full = reembolso total';
COMMENT ON COLUMN orders.refund_response IS 'Respuesta de la API de Transbank al anular/reversar';
COMMENT ON COLUMN orders.refunded_at     IS 'Fecha y hora en que se ejecutó el reembolso';
