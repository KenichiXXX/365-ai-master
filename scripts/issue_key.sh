#!/bin/bash
set -euo pipefail
: "${ADMIN_TOKEN:?Set ADMIN_TOKEN}"
: "${LICENSE_ISSUE_URL:?Set LICENSE_ISSUE_URL to https://your-worker.workers.dev/v1/license/issue}"
if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/issue_key.sh <order_ref>" >&2
  exit 2
fi
case "$LICENSE_ISSUE_URL" in
  https://*/v1/license/issue) ;;
  *) echo "LICENSE_ISSUE_URL must be an HTTPS license issue endpoint" >&2; exit 2 ;;
esac
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
payload="$("$script_dir/../.venv/bin/python" -c 'import json,sys
order = sys.argv[1]
if not order.strip() or len(order) > 64:
    raise SystemExit("order_ref must contain 1 to 64 characters")
print(json.dumps({"order_ref": order, "days": 365}))' "$1")"
curl --fail-with-body --silent --show-error --request POST \
  --header "Authorization: Bearer $ADMIN_TOKEN" \
  --header 'Content-Type: application/json' \
  --data "$payload" "$LICENSE_ISSUE_URL"
