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
