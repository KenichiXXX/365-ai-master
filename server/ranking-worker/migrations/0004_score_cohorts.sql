-- Legacy rows remain in devices/score_counts/dim_counts. Their app_version
-- is not evidence of scoring arithmetic, so none is backfilled into a cohort.
CREATE TABLE cohort_devices (
    score_version TEXT NOT NULL,
    device_token TEXT NOT NULL,
    score INTEGER NOT NULL,
    routing INTEGER NOT NULL,
    timing INTEGER NOT NULL,
    context INTEGER NOT NULL,
    leverage INTEGER NOT NULL,
    app_version TEXT,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (score_version, device_token)
);
CREATE TABLE cohort_score_counts (
    score_version TEXT NOT NULL,
    score INTEGER NOT NULL,
    n INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (score_version, score)
);
CREATE TABLE cohort_dim_counts (
    score_version TEXT NOT NULL,
    dim TEXT NOT NULL,
    score INTEGER NOT NULL,
    n INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (score_version, dim, score)
);
