# Anonymous score ranking Worker

Ranking routes accept only a random device ID, overall score, four dimension scores, and app version.
The Worker has no application request-body or IP logging, CORS, or outbound fetches. Subscription billing is isolated from ranking data. Rankings scan only the
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


## Subscription contract and release blocker

Task 34 adds `src/subscriptions.js`, a normalized `PaymentProvider` boundary, and migration `0005_subscriptions.sql`. Local D1 tests inject a fake through an internal module API. The public router always uses the unavailable Waffo adapter. Request bodies, query parameters, and environment flags cannot select the fake.

`POST /v1/waffo/webhook` currently returns HTTP 503 with `status: unavailable`. `TODO(WAFFO_VERIFIED_INTEGRATION)` requires official documentation, authenticated sandbox fixtures, and real renewal, refund, cancellation, and receipt recovery checks. No guessed provider protocol or live checkout is implemented.

`POST /v1/license/refresh` accepts exactly `{lic, key}`, bounded to 1024 bytes. It requires an authentic known AIM1 proof, including an expired proof after a genuine renewal. No account or app admin token is needed. It reconciles provider state, uses the same license ID and verified paid-through boundary, and returns the persisted period key without expiry inflation. Refund/revocation blocks refresh. Cancellation retains the paid period. Provider outages fail closed. Ten authenticated attempts per license per UTC minute are allowed. All license responses use `Cache-Control: no-store`.

Manual `POST /v1/license/issue` remains admin-only and is now idempotent by order reference, including concurrent retries. Legacy signed keys remain valid and do not become subscriptions. There is no listing endpoint. Billing tables contain no ranking UUID, raw webhook, card, email, or usage event. The issued-key registry is sensitive server data; keys appear only in explicit no-store key responses and never application logs.

See [Activation keys](../../docs/license.md) for normalized provider fields, UTC inclusive-expiry conversion, persistence/retry semantics, response codes, and offline revocation limits. No production migration, secret setup, deployment, or real merchant action was run for this task.
