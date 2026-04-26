-- ================================================================
-- Create isolated schemas for each service
-- ================================================================
CREATE SCHEMA IF NOT EXISTS products;
CREATE SCHEMA IF NOT EXISTS orders;
CREATE SCHEMA IF NOT EXISTS auth;

-- ================================================================
-- products schema  (productcatalogservice)
-- ================================================================
CREATE TABLE IF NOT EXISTS products.catalog (
    id                       TEXT PRIMARY KEY,
    name                     TEXT    NOT NULL,
    description              TEXT    NOT NULL DEFAULT '',
    picture                  TEXT    NOT NULL DEFAULT '',
    price_usd_currency_code  TEXT    NOT NULL DEFAULT 'USD',
    price_usd_units          BIGINT  NOT NULL DEFAULT 0,
    price_usd_nanos          INT     NOT NULL DEFAULT 0,
    categories               TEXT    NOT NULL DEFAULT ''
);

INSERT INTO products.catalog VALUES
  ('OLJCESPC7Z', 'Sunglasses',
   'Add a modern touch to your outfits with these sleek aviator sunglasses.',
   '/static/img/products/sunglasses.jpg', 'USD', 19, 990000000, 'accessories'),
  ('66VCHSJNUP', 'Tank Top',
   'Perfectly cropped cotton tank, with a scooped neckline.',
   '/static/img/products/tank-top.jpg', 'USD', 18, 990000000, 'clothing,tops'),
  ('1YMWWN1N4O', 'Watch',
   'This gold-tone stainless steel watch will make a statement.',
   '/static/img/products/watch.jpg', 'USD', 109, 990000000, 'accessories')
ON CONFLICT (id) DO NOTHING;

-- ================================================================
-- orders schema  (checkoutservice)
-- ================================================================
CREATE TABLE IF NOT EXISTS orders.orders (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        TEXT        NOT NULL,
    status         TEXT        NOT NULL DEFAULT 'pending',
    total_currency TEXT        NOT NULL DEFAULT 'USD',
    total_units    BIGINT      NOT NULL DEFAULT 0,
    total_nanos    INT         NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders.order_items (
    id           UUID   PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id     UUID   NOT NULL REFERENCES orders.orders(id) ON DELETE CASCADE,
    product_id   TEXT   NOT NULL,
    quantity     INT    NOT NULL DEFAULT 1,
    unit_currency TEXT  NOT NULL DEFAULT 'USD',
    unit_units   BIGINT NOT NULL DEFAULT 0,
    unit_nanos   INT    NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON orders.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_id       ON orders.orders(user_id);

-- ================================================================
-- auth schema  (authservice)
-- ================================================================
CREATE TABLE IF NOT EXISTS auth.sessions (
    token      TEXT        PRIMARY KEY,
    user_id    TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '24 hours'
);

CREATE TABLE IF NOT EXISTS auth.users (
    id            TEXT        PRIMARY KEY,
    email         TEXT        UNIQUE NOT NULL,
    password_hash TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id    ON auth.sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON auth.sessions(expires_at);