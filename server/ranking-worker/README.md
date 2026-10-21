# Anonymous score ranking Worker

Accepts only a random device ID, overall score, four dimension scores, and app version.
No request body or IP logging, CORS, or outbound fetches. Rankings scan only the
101-row `score_counts` table. Device updates and bucket moves use one atomic D1
batch; updates within one hour leave all stored values unchanged. A tied score
is not counted as beaten. Turning sharing off in the app leaves its server row.

## Local tests (dependencies already present)

```sh
npm test
```

Uses local D1 and applies `migrations/0001_init.sql`. Test logs remain in
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
