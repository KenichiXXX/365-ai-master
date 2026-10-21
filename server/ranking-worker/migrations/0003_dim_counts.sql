CREATE TABLE dim_counts (
    dim TEXT NOT NULL,
    score INTEGER NOT NULL,
    n INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (dim, score)
);
WITH RECURSIVE scores(score) AS (
    SELECT 0 UNION ALL SELECT score + 1 FROM scores WHERE score < 100
), dims(dim) AS (
    SELECT 'routing' UNION ALL SELECT 'timing' UNION ALL SELECT 'context' UNION ALL SELECT 'leverage'
)
INSERT INTO dim_counts(dim, score, n)
SELECT dim, score, 0 FROM dims CROSS JOIN scores;
WITH existing(dim, score) AS (
    SELECT 'routing', routing FROM devices UNION ALL
    SELECT 'timing', timing FROM devices UNION ALL
    SELECT 'context', context FROM devices UNION ALL
    SELECT 'leverage', leverage FROM devices
)
UPDATE dim_counts SET n = (
    SELECT COUNT(*) FROM existing WHERE existing.dim = dim_counts.dim AND existing.score = dim_counts.score
);
