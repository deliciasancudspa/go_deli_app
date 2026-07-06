-- Campos para integración Mercado Pago
-- Patrón: mismo que webpay_token/khipu_payment_id en migraciones anteriores

ALTER TABLE orders ADD COLUMN IF NOT EXISTS mp_preference_id    TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS mp_payment_id       TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS mp_payment_response JSONB;

CREATE INDEX IF NOT EXISTS idx_orders_mp_preference_id ON orders(mp_preference_id)
  WHERE mp_preference_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_orders_mp_payment_id ON orders(mp_payment_id)
  WHERE mp_payment_id IS NOT NULL;

COMMENT ON COLUMN orders.mp_preference_id    IS 'ID de preferencia devuelto por Mercado Pago al crear la preferencia de pago';
COMMENT ON COLUMN orders.mp_payment_id       IS 'ID del pago confirmado por Mercado Pago';
COMMENT ON COLUMN orders.mp_payment_response IS 'Respuesta completa de Mercado Pago al verificar el pago';
