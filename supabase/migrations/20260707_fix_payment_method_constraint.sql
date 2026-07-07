-- ============================================================================
-- Fix: Agregar 'pending' y 'mixed' al CHECK constraint de payment_method
-- ============================================================================
-- Contexto: El nuevo flujo POS crea la orden con payment_method='pending' antes
-- de mostrar el modal de pago. Al confirmar pagos con split, se actualiza a
-- 'mixed' o al método único usado.
-- ============================================================================

-- 1. Eliminar la constraint existente
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_method_check;

-- 2. Recrear con 'pending' y 'mixed' agregados
ALTER TABLE public.orders ADD CONSTRAINT orders_payment_method_check
  CHECK (payment_method = ANY (ARRAY[
    'cash'::text,
    'debit'::text,
    'credit'::text,
    'transfer'::text,
    'webpay'::text,
    'khipu'::text,
    'mercadopago'::text,
    'qr'::text,
    'go_wallet'::text,
    'card'::text,
    'pending'::text,
    'mixed'::text
  ])) NOT VALID;
