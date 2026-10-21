CREATE TABLE subscriptions (
  provider_ref TEXT PRIMARY KEY,
  lic TEXT NOT NULL UNIQUE,
  revision INTEGER NOT NULL,
  status TEXT NOT NULL,
  snapshot_hash TEXT NOT NULL,
  paid_through TEXT,
  auto_renew INTEGER NOT NULL,
  terminal_revision INTEGER,
  management_url TEXT
);
CREATE TABLE subscription_events (
  event_id TEXT PRIMARY KEY,
  provider_ref TEXT NOT NULL,
  revision INTEGER NOT NULL,
  fingerprint TEXT NOT NULL
);
CREATE TABLE subscription_periods (
  order_ref TEXT PRIMARY KEY,
  provider_ref TEXT NOT NULL,
  period_start TEXT NOT NULL,
  paid_through TEXT NOT NULL,
  UNIQUE(provider_ref, period_start)
);
CREATE TABLE license_keys (
  lic TEXT NOT NULL,
  period_ref TEXT NOT NULL,
  exp TEXT NOT NULL,
  key TEXT NOT NULL UNIQUE,
  PRIMARY KEY(lic, period_ref)
);
CREATE TABLE manual_orders (
  order_ref TEXT PRIMARY KEY,
  lic TEXT NOT NULL UNIQUE
);
-- Preserve historical keys, including orders retried before idempotency existed.
INSERT INTO manual_orders(order_ref, lic)
SELECT order_ref, lic FROM (
  SELECT order_ref, lic,
    ROW_NUMBER() OVER (PARTITION BY order_ref ORDER BY created_at, lic) AS position
  FROM licenses WHERE order_ref IS NOT NULL
) WHERE position = 1;
CREATE TABLE license_refresh_limits (
  lic TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  attempts INTEGER NOT NULL
);
