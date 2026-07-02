-- Permitir status "pending_payment" en órdenes que aún no tienen pago confirmado.
-- La app Flutter (checkout_screen.dart) inserta la orden con este status cuando
-- el método de pago es webpay/khipu. Así la tienda no ve la orden hasta que
-- webpay-return/khipu-notify confirme el pago y la mueva a "accepted".
--
-- Idempotente: si el constraint ya incluye pending_payment, no hace nada.
-- Si existe pero con otros valores, lo borra y recrea.

-- 1. Eliminar constraint viejo (sin pending_payment)
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;

-- 2. Crear constraint nuevo con pending_payment
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
CHECK (status IN (
    'pending_payment',  -- orden creada, esperando confirmación de pago (webpay/khipu)
    'pending',          -- orden activa, visible a la tienda
    'accepted',
    'preparing',
    'ready',
    'assigned',
    'picked_up',
    'on_the_way',
    'delivered',
    'cancelled',
    'returned'
));
