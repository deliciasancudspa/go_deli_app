-- Guardar URL de retorno para clientes web (no se puede pasar como query param
-- en el return_url de Transbank porque interfiere con los parámetros de redirect)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS web_return_url TEXT;

COMMENT ON COLUMN orders.web_return_url IS 'URL base de la app web para redirigir tras pago Webpay/Khipu (no se pasa en el return_url de Transbank)';
