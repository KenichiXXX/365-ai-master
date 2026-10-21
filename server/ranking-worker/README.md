# Anonymous score ranking Worker

Accepts only a random device ID, overall score, four dimension scores, and app version.
No request body or IP logging, CORS, or outbound fetches. Rankings scan only the
101 score buckets per cohort. Device updates and bucket moves use one atomic D1
batch; updates within one hour leave all stored values unchanged. A tied score
is not counted as beaten. Overall and dimension comparisons use the accepted
stored row, including when a changed submission is throttled. Turning sharing
off in the app leaves its server row.

`POST /v1/score/1` is the currently supported comparable scoring endpoint. The
JSON body remains exactly `device_token,score,dims,app_version`; the response
includes `score_version: "1"`. Unknown versions return 404. Future arithmetic
versions require an explicit route allowlist update. Scores, devices and four
dimension bucket sets are isolated by score version in the `cohort_*` tables.
A UUID counts an opt-in installation, not a unique human; one person can have
multiple installations, and this self-selected sample is not representative of
all AI users. Percentiles remain null below 20 participating installations.

`POST /v1/score` and its existing tables remain legacy. Migration 0004 leaves
those rows untouched and does not infer a scoring version from `app_version`.
A legacy installation enters a comparable cohort only by making an explicitly
versioned submission. The synthetic second version used by unit tests calls the
internal handler directly and is not accepted by the public router.

## Local tests (dependencies already present)

```sh
npm test
```

Uses local D1 and applies all local `migrations/*.sql`. Test logs remain in
`.wrangler/`; Wrangler telemetry is disabled by the test command.

## Reviewer deployment

```sh
npx wrangler login
npx wrangler d1 create 365aimaster-ranking
```

Paste the database ID into `wrangler.toml` in place of `REPLACE_AFTER_CREATE`.

```sh
npx wrangler d1 migrations apply 365aimaster-ranking --remote
npx wrangler deploy
```

Replace the placeholder host in `macos/Sources/AIMaster/ScoreReporter.swift`
with the deployed `.workers.dev` host. The app refuses to send while `REPLACE`
is present. Deployment and real network reporting are reviewer actions.
