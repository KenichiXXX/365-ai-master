CREATE TABLE devices (
    device_token TEXT PRIMARY KEY,
    score INTEGER NOT NULL,
    routing INTEGER,
    timing INTEGER,
    context INTEGER,
    leverage INTEGER,
    app_version TEXT,
    updated_at TEXT NOT NULL
);
CREATE TABLE score_counts (score INTEGER PRIMARY KEY, n INTEGER NOT NULL DEFAULT 0);
WITH RECURSIVE scores(score) AS (
    SELECT 0 UNION ALL SELECT score + 1 FROM scores WHERE score < 100
)
INSERT INTO score_counts(score, n) SELECT score, 0 FROM scores;
