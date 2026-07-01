-- Permitir status "pending_payment" en órdenes que aún no tienen pago confirmado.
-- La app Flutter (checkout_screen.dart) inserta la orden con este status cuando
-- el método de pago es webpay/khipu. Así la tienda no ve la orden hasta que
-- webpay-return/khipu-notify confirme el pago y la mueva a "accepted".
--
-- Buscar y modificar cualquier CHECK constraint existente sobre orders.status.
-- Si no existe el constraint, se crea uno nuevo con todos los valores válidos.

DO $$
DECLARE
  v_constraint_name text;
BEGIN
  -- Buscar constraint tipo CHECK que mencione la columna status
  SELECT con.conname INTO v_constraint_name
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  WHERE rel.relname = 'orders'
    AND con.contype = 'c'
    AND pg_get_constraintdef(con.oid) ILIKE '%status%';

  IF v_constraint_name IS NOT NULL THEN
    -- Hay un CHECK constraint existente: lo reemplazamos añadiendo pending_payment
    EXECUTE format('ALTER TABLE public.orders DROP CONSTRAINT %I', v_constraint_name);
  END IF;

  -- Crear constraint con todos los valores válidos (incluye pending_payment)
  -- Solo si no existe ya uno
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    WHERE rel.relname = 'orders'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) ILIKE '%status%'
      AND pg_get_constraintdef(con.oid) ILIKE '%pending_payment%'
  ) THEN
    EXECUTE $ALTER$
      ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
      CHECK (status IN (
        'pending_payment',  -- nuevo: orden creada, esperando pago (webpay/khipu)
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
      ))
    $ALTER$;
  END IF;
END $$;
