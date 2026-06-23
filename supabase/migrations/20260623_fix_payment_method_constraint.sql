-- Actualizar el CHECK constraint de payment_method para incluir webpay y khipu
-- La constraint original solo tenía 'cash' (y posiblemente 'card','transfer'),
-- por lo que los nuevos métodos WebPay/Khipu violaban la restricción.

DO $$
DECLARE
  v_name TEXT;
  v_existing TEXT;
BEGIN
  -- Buscar el nombre real del constraint
  SELECT con.conname INTO v_name
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
  WHERE rel.relname = 'orders'
    AND con.contype = 'c'
    AND con.conname LIKE '%payment%';

  IF v_name IS NOT NULL THEN
    -- Obtener la definición actual para logging
    SELECT pg_get_constraintdef(con.oid) INTO v_existing
    FROM pg_constraint con
    WHERE con.conname = v_name;

    RAISE NOTICE 'Constraint encontrado: % = %', v_name, v_existing;

    -- Eliminar el constraint viejo
    EXECUTE format('ALTER TABLE orders DROP CONSTRAINT %I', v_name);
  ELSE
    RAISE NOTICE 'No se encontró constraint de payment_method en orders';
  END IF;

  -- Crear nuevo constraint con los valores correctos
  ALTER TABLE orders ADD CONSTRAINT orders_payment_method_check
    CHECK (payment_method IN ('cash', 'webpay', 'khipu'));

  RAISE NOTICE 'Constraint orders_payment_method_check actualizado: cash, webpay, khipu';
END $$;
