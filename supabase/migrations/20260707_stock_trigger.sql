-- ============================================================================
-- Trigger: descontar stock de menu_items al insertar en order_items
-- Cubre TODAS las fuentes: GoDeli app, POS, y futuras integraciones.
-- ============================================================================

-- 1. Función que descuenta stock
CREATE OR REPLACE FUNCTION public.decrement_stock_on_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.menu_items
  SET stock = GREATEST(stock - NEW.quantity, 0)
  WHERE id = NEW.menu_item_id
    AND stock IS NOT NULL;  -- solo si el aliado gestiona stock (stock != null)
  RETURN NEW;
END;
$$;

-- 2. Trigger AFTER INSERT en order_items
DROP TRIGGER IF EXISTS trg_decrement_stock ON public.order_items;
CREATE TRIGGER trg_decrement_stock
AFTER INSERT ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.decrement_stock_on_order();
