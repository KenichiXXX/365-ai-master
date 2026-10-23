#!/bin/bash
# Renders every v2 screen from this Mac's real logs into build/v2/renders (gitignored) plus a contact sheet.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/v2"
SRC="$HOME/Library/Application Support/365AIMaster"
TOOLS=claude_code,codex,gemini_cli,opencode,qwen_code

rm -rf "$OUT/renders" "$OUT/state"
mkdir -p "$OUT/fixtures" "$OUT/state" "$OUT/renders"
for file in progress.json scan.json local_metrics.json; do
  if [ -f "$SRC/$file" ]; then cp "$SRC/$file" "$OUT/state/"; fi
done

python3 - "$SRC/content.json" "$ROOT/agentfit/engine/content_pool.json" "$OUT/fixtures/content.json" <<'PY'
import json, sys
downloaded, bundled, target = sys.argv[1:4]
try:
    content = json.load(open(downloaded, encoding="utf-8"))
except FileNotFoundError:
    content = json.load(open(bundled, encoding="utf-8"))
content["skills"] = json.load(open(bundled, encoding="utf-8"))["skills"]
json.dump(content, open(target, "w", encoding="utf-8"), ensure_ascii=False)
PY

for locale in zh en; do
  "$ROOT/dist/365engine" snapshot --json --locale "$locale" --tools "$TOOLS" \
    --content "$OUT/fixtures/content.json" --state-dir "$OUT/state" > "$OUT/fixtures/snapshot-$locale.json"
done

cd "$ROOT/macos"
RENDER_OUT="$OUT/renders" RENDER_SNAPSHOT_ZH="$OUT/fixtures/snapshot-zh.json" RENDER_SNAPSHOT_EN="$OUT/fixtures/snapshot-en.json" \
  swift test --filter V2RenderTests 2>&1 | grep -E "error|failed|passed|Executed" || true

python3 - "$OUT/renders" <<'PY'
import html, os, sys
folder = sys.argv[1]
names = sorted(f for f in os.listdir(folder) if f.endswith(".png"))
rows = "".join(f'<figure><img src="{html.escape(n)}"><figcaption>{html.escape(n)}</figcaption></figure>' for n in names)
open(os.path.join(folder, "index.html"), "w").write(
    '<!doctype html><meta charset="utf-8"><title>365 v2 renders</title><style>body{font:13px -apple-system;background:#ddd;'
    'display:flex;flex-wrap:wrap;gap:16px;padding:16px}figure{margin:0}img{width:400px;display:block;'
    'box-shadow:0 4px 16px rgba(0,0,0,.2);border-radius:12px}figcaption{padding:4px 0}</style>' + rows)
print(len(names), "renders in", folder)
PY

# Marketing shots use demo numbers so the public site never shows a real person's usage.
python3 - "$OUT/fixtures" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
folder = sys.argv[1]
now = datetime.now(timezone.utc)
for locale in ("zh", "en"):
    snap = json.load(open(f"{folder}/snapshot-{locale}.json", encoding="utf-8"))
    snap["overall"]["score"] = 72
    scores = {"routing": 58, "timing": 76, "context": 88, "leverage": 71}
    for dim in snap["dimensions"]:
        dim["score"] = scores[dim["key"]]
        lost = 100 - dim["score"]
        for index, deduction in enumerate(dim.get("deductions") or []):
            deduction["points"] = lost if index == 0 else 0
        dim["deductions"] = [d for d in (dim.get("deductions") or []) if d["points"] > 0]
    snap["progress_me"] = {"vs_yesterday": 2, "personal_best": 72, "week_delta": 4}
    usage = snap["usage_summary"]
    usage["tokens_7d"] = 18_420_000
    usage["price_estimate"].update(matched_subtotal_usd=642.0, coverage_pct=100.0)
    quota = {"plan_type": "pro", "recorded_at": now.isoformat(), "primary_pct": 38.0, "primary_window_min": 10080,
             "primary_resets_at": (now + timedelta(days=3, hours=5)).isoformat(), "secondary_pct": None,
             "secondary_window_min": None, "secondary_resets_at": None, "freshness": "fresh"}
    usage["codex_quota"] = quota
    snap["quota"] = {"codex": quota}
    snap["streak"] = {"days": 21, "label": snap.get("streak", {}).get("label")}
    book = snap["book"]
    plan = next(card for card in book["cards"] if card["id"] == "plan_mode")
    plan.update(lit=False, evidence_kind="ready", how=None)
    book["today"] = dict(plan)
    book["lit"] = sum(card["lit"] for card in book["cards"])
    days = snap["growth"]["days"]
    for offset, day in enumerate(days[-14:]):
        value = 60 + round(offset * 12 / 13)
        day.update(score=value, score_version="1", rule_version="1",
                   dims={"routing": value - 14, "timing": value + 4, "context": value + 16, "leverage": value - 1})
    json.dump(snap, open(f"{folder}/demo-{locale}.json", "w", encoding="utf-8"), ensure_ascii=False)
PY
rm -rf "$OUT/marketing" && mkdir -p "$OUT/marketing"
cd "$ROOT/macos"
RENDER_OUT="$OUT/marketing" RENDER_SNAPSHOT_ZH="$OUT/fixtures/demo-zh.json" RENDER_SNAPSHOT_EN="$OUT/fixtures/demo-en.json" \
  swift test --filter V2RenderTests 2>&1 | grep -E "error|failed|Executed 1 test" | tail -1 || true
echo "marketing shots: $(ls "$OUT/marketing" | wc -l | tr -d ' ')"
