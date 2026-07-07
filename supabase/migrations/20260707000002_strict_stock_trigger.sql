-- ============================================================================
-- Trigger ESTRICTO: rechazar order_items si no hay stock suficiente
-- Previene overselling cuando 2+ clientes compran el mismo producto simultáneamente
-- ============================================================================

-- Reemplazar la función anterior (que silenciosamente capeaba a 0)
CREATE OR REPLACE FUNCTION public.decrement_stock_on_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  current_stock INTEGER;
BEGIN
  -- Solo validar si el aliado gestiona stock (stock IS NOT NULL)
  SELECT stock INTO current_stock FROM public.menu_items WHERE id = NEW.menu_item_id;

  IF current_stock IS NOT NULL THEN
    -- Bloquear si no hay stock suficiente
    IF current_stock < NEW.quantity THEN
      RAISE EXCEPTION 'Stock insuficiente: solo quedan % unidades de este producto', current_stock;
    END IF;
    -- Descontar stock
    UPDATE public.menu_items SET stock = stock - NEW.quantity WHERE id = NEW.menu_item_id;
  END IF;

  RETURN NEW;
END;
$$;

-- Recrear el trigger como BEFORE INSERT (bloquea el INSERT si falla)
DROP TRIGGER IF EXISTS trg_decrement_stock ON public.order_items;
CREATE TRIGGER trg_decrement_stock
BEFORE INSERT ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.decrement_stock_on_order();
