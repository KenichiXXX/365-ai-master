#!/usr/bin/env bash
# One-shot deploy: create (or reuse) the D1 database, apply migrations, deploy the worker,
# then smoke-test the live endpoint without leaving test data behind.
set -euo pipefail
cd "$(dirname "$0")"
DB=365aimaster-ranking

npx wrangler whoami >/dev/null

if ! npx wrangler d1 list --json | grep -q "\"name\": *\"$DB\""; then
    npx wrangler d1 create "$DB"
fi
DB_ID="$(npx wrangler d1 list --json | node -e '
  let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
    const db = JSON.parse(s).find(d => d.name === process.argv[1]);
    if (!db) process.exit(1);
    console.log(db.uuid);
  });' "$DB")"
sed -i '' "s/REPLACE_AFTER_CREATE/$DB_ID/" wrangler.toml
grep -q "$DB_ID" wrangler.toml

npx wrangler d1 migrations apply "$DB" --remote
DEPLOY_LOG="$(mktemp)"
npx wrangler deploy | tee "$DEPLOY_LOG"
URL="$(grep -oE 'https://[a-z0-9.-]+\.workers\.dev' "$DEPLOY_LOG" | head -1)"
[ -n "$URL" ] || { echo "Could not find the workers.dev URL in the deploy output" >&2; exit 1; }
echo "WORKER_URL=$URL"

echo "--- smoke: GET is 404"
curl -s -o /dev/null -w '%{http_code}\n' "$URL/v1/score"
echo "--- smoke: extra field is 422"
curl -s -w ' %{http_code}\n' -X POST "$URL/v1/score" -H 'Content-Type: application/json' \
  -d '{"device_token":"deploy-selftest-0001","score":50,"dims":{"routing":50,"timing":50,"context":50,"leverage":50},"app_version":"0","email":"x"}'
echo "--- smoke: valid payload is 200 (then removed again)"
curl -s -w ' %{http_code}\n' -X POST "$URL/v1/score" -H 'Content-Type: application/json' \
  -d '{"device_token":"deploy-selftest-0001","score":50,"dims":{"routing":50,"timing":50,"context":50,"leverage":50},"app_version":"0"}'
npx wrangler d1 execute "$DB" --remote --command \
  "UPDATE score_counts SET n = n - 1 WHERE score = (SELECT score FROM devices WHERE device_token = 'deploy-selftest-0001'); DELETE FROM devices WHERE device_token = 'deploy-selftest-0001';"
echo "--- after cleanup (expect total 0 / null):"
npx wrangler d1 execute "$DB" --remote --json --command "SELECT SUM(n) AS total, (SELECT COUNT(*) FROM devices) AS devices FROM score_counts;"
echo "DEPLOY_DONE $URL"
