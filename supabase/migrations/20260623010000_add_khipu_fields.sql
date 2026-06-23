-- Campos para integración Khipu (transferencia bancaria)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS khipu_payment_id TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS khipu_response   JSONB;

CREATE INDEX IF NOT EXISTS idx_orders_khipu_payment_id ON orders(khipu_payment_id)
  WHERE khipu_payment_id IS NOT NULL;

COMMENT ON COLUMN orders.khipu_payment_id IS 'ID de pago devuelto por Khipu al crear el cobro';
COMMENT ON COLUMN orders.khipu_response   IS 'Respuesta completa de Khipu al confirmar el pago vía webhook';
