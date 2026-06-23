-- Campos para integración WebPay Plus (Transbank)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS webpay_token   TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS webpay_response JSONB;

-- Índice para lookup rápido al confirmar pago
CREATE INDEX IF NOT EXISTS idx_orders_webpay_token ON orders(webpay_token)
  WHERE webpay_token IS NOT NULL;

COMMENT ON COLUMN orders.webpay_token    IS 'Token devuelto por Transbank al crear la transacción WebPay';
COMMENT ON COLUMN orders.payment_status  IS 'pending | pending_webpay | paid | payment_failed';
COMMENT ON COLUMN orders.webpay_response IS 'Respuesta completa de Transbank al confirmar la transacción';
