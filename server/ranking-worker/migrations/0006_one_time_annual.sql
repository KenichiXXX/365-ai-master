CREATE TABLE one_time_orders (
  order_ref TEXT PRIMARY KEY,
  lic TEXT NOT NULL UNIQUE,
  revision INTEGER NOT NULL,
  status TEXT NOT NULL,
  snapshot_hash TEXT NOT NULL,
  paid_at TEXT,
  terminal_revision INTEGER
);
CREATE TABLE one_time_events (
  event_id TEXT PRIMARY KEY,
  fingerprint TEXT NOT NULL
);
