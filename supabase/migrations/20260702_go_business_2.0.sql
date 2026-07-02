-- ============================================================================
-- Go Business 2.0 — Migración no-destructiva
-- ============================================================================
-- Solo ADD COLUMN IF NOT EXISTS y CREATE TABLE IF NOT EXISTS.
-- No se modifica ni elimina ningún dato existente.
-- ============================================================================

-- 1. ÓRDENES ────────────────────────────────────────────────────────────────
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_source            TEXT DEFAULT 'GO_DELI';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_mode              TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS go_rider_platform_fee   INTEGER DEFAULT 2500;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS platform_commission     INTEGER;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_method         TEXT DEFAULT 'go_rider';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS pos_created_by          UUID REFERENCES public.users(id);
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_name           TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_phone          TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_address        TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_lat            DOUBLE PRECISION;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS customer_lng            DOUBLE PRECISION;

CREATE INDEX IF NOT EXISTS idx_orders_order_source ON public.orders(order_source);
CREATE INDEX IF NOT EXISTS idx_orders_order_mode   ON public.orders(order_mode);

-- 2. TIENDAS ────────────────────────────────────────────────────────────────
ALTER TABLE public.stores ADD COLUMN IF NOT EXISTS delivery_methods      JSONB DEFAULT '["go_rider"]';
ALTER TABLE public.stores ADD COLUMN IF NOT EXISTS delivery_priority     TEXT DEFAULT 'go_rider';
ALTER TABLE public.stores ADD COLUMN IF NOT EXISTS payment_methods       JSONB DEFAULT '["cash","debit","credit","transfer"]';
ALTER TABLE public.stores ADD COLUMN IF NOT EXISTS delivery_fee_max      INTEGER DEFAULT 2500;
ALTER TABLE public.stores ADD COLUMN IF NOT EXISTS accepts_cash_for_rider BOOLEAN DEFAULT true;

-- 3. MENÚ ───────────────────────────────────────────────────────────────────
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS sku                  TEXT;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS barcode              TEXT;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS stock                INTEGER DEFAULT 0;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS stock_min            INTEGER DEFAULT 5;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS option_group_ids     TEXT[];
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS lab_code             TEXT;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS concentration        TEXT;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS isp_registry         TEXT;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS requires_prescription BOOLEAN DEFAULT false;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS sell_by_weight       BOOLEAN DEFAULT false;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS variable_weight      BOOLEAN DEFAULT false;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS brand                TEXT;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS lot_number           TEXT;
ALTER TABLE public.menu_items ADD COLUMN IF NOT EXISTS expiration_date      DATE;

-- 4. VARIANTES DE PRODUCTO ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.product_variants (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  product_id  UUID NOT NULL REFERENCES public.menu_items(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  price       INTEGER NOT NULL DEFAULT 0,
  sku         TEXT,
  barcode     TEXT,
  stock       INTEGER DEFAULT 0,
  stock_min   INTEGER DEFAULT 5,
  image_url   TEXT,
  sort_order  INTEGER DEFAULT 0,
  is_active   BOOLEAN DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_variants_product ON public.product_variants(product_id);

-- 5. GRUPOS DE OPCIONES ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.option_groups (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id       UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  name           TEXT NOT NULL,
  is_required    BOOLEAN DEFAULT false,
  min_selections INTEGER DEFAULT 0,
  max_selections INTEGER DEFAULT 0,
  sort_order     INTEGER DEFAULT 0,
  is_active      BOOLEAN DEFAULT true,
  created_at     TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_option_groups_store ON public.option_groups(store_id);

-- 6. ÍTEMS DE OPCIONES ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.option_items (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  group_id   UUID NOT NULL REFERENCES public.option_groups(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  surcharge  INTEGER DEFAULT 0,
  sort_order INTEGER DEFAULT 0,
  is_active  BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_option_items_group ON public.option_items(group_id);

-- 7. PRODUCTO ↔ OPCIONES ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.menu_item_option_groups (
  item_id  UUID REFERENCES public.menu_items(id) ON DELETE CASCADE,
  group_id UUID REFERENCES public.option_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, group_id)
);

-- 8. INVENTARIO ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.inventory_movements (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id        UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  product_id      UUID REFERENCES public.menu_items(id) ON DELETE SET NULL,
  variant_id      UUID REFERENCES public.product_variants(id) ON DELETE SET NULL,
  type            TEXT NOT NULL CHECK (type IN ('entrada','salida','ajuste')),
  quantity        INTEGER NOT NULL,
  previous_stock  INTEGER,
  new_stock       INTEGER,
  reason          TEXT,
  reference_type  TEXT,
  reference_id    UUID,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inv_mov_store   ON public.inventory_movements(store_id);
CREATE INDEX IF NOT EXISTS idx_inv_mov_product ON public.inventory_movements(product_id);

-- 9. SESIONES DE CAJA ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cash_sessions (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  store_id        UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  opened_by       UUID REFERENCES public.users(id),
  closed_by       UUID REFERENCES public.users(id),
  opening_amount  INTEGER NOT NULL DEFAULT 0,
  closing_amount  INTEGER,
  expected_amount INTEGER,
  difference      INTEGER,
  status          TEXT DEFAULT 'open' CHECK (status IN ('open','closed')),
  notes           TEXT,
  opened_at       TIMESTAMPTZ DEFAULT now(),
  closed_at       TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_cash_sessions_store ON public.cash_sessions(store_id);

-- 10. MOVIMIENTOS DE CAJA ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cash_movements (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id      UUID REFERENCES public.cash_sessions(id) ON DELETE CASCADE,
  store_id        UUID NOT NULL REFERENCES public.stores(id) ON DELETE CASCADE,
  type            TEXT NOT NULL CHECK (type IN ('venta','retiro','ingreso','ajuste')),
  amount          INTEGER NOT NULL,
  payment_method  TEXT,
  description     TEXT,
  order_id        UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  created_by      UUID REFERENCES public.users(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cash_movements_session ON public.cash_movements(session_id);
CREATE INDEX IF NOT EXISTS idx_cash_movements_store   ON public.cash_movements(store_id);
