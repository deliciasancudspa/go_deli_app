-- ============================================================================
-- Trigger: restaurar stock al cancelar o devolver una orden
-- Cuando una orden pasa a 'cancelled' o 'returned', se devuelve el stock
-- de cada producto y se registra en inventory_movements.
-- ============================================================================

-- 1. Función que restaura stock al cancelar/devolver
CREATE OR REPLACE FUNCTION public.restore_stock_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  item RECORD;
  prev_stock INTEGER;
  new_stock INTEGER;
BEGIN
  -- Solo actuar si la orden cambia A cancelled/returned desde otro estado
  -- (evita doble restauración si se actualiza dos veces al mismo estado)
  IF (NEW.status = 'cancelled' OR NEW.status = 'returned')
     AND (OLD.status IS DISTINCT FROM NEW.status) THEN

    -- Recorrer cada item de la orden y restaurar stock
    FOR item IN
      SELECT oi.menu_item_id, oi.quantity, mi.stock
      FROM public.order_items oi
      JOIN public.menu_items mi ON mi.id = oi.menu_item_id
      WHERE oi.order_id = NEW.id
        AND mi.stock IS NOT NULL  -- solo productos con gestión de stock
    LOOP
      prev_stock := item.stock;
      new_stock := item.stock + item.quantity;

      -- Restaurar stock
      UPDATE public.menu_items
      SET stock = new_stock
      WHERE id = item.menu_item_id;

      -- Registrar movimiento de inventario
      INSERT INTO public.inventory_movements (
        store_id,
        product_id,
        type,
        quantity,
        previous_stock,
        new_stock,
        reason,
        reference_type,
        reference_id
      ) VALUES (
        NEW.store_id,
        item.menu_item_id,
        'entrada',
        item.quantity,
        prev_stock,
        new_stock,
        CASE WHEN NEW.status = 'cancelled'
          THEN 'Cancelación de pedido'
          ELSE 'Devolución de pedido'
        END,
        'order',
        NEW.id
      );
    END LOOP;

  END IF;

  RETURN NEW;
END;
$$;

-- 2. Trigger AFTER UPDATE en orders
DROP TRIGGER IF EXISTS trg_restore_stock_on_cancel ON public.orders;
CREATE TRIGGER trg_restore_stock_on_cancel
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.restore_stock_on_cancel();
