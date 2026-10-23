#!/bin/bash
# Copies demo-data renders (never real usage) from build/v2/marketing into the website.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/build/v2/marketing"
DST="$ROOT/site/assets/img"
mkdir -p "$DST"
for locale in zh en; do
  for scheme in light dark; do
    cp "$SRC/05-home-ranked-$locale-$scheme.png" "$DST/home-$locale-$scheme.png"
    cp "$SRC/10-dimension-routing-$locale-$scheme.png" "$DST/dimension-$locale-$scheme.png"
    cp "$SRC/21-path-screen-$locale-$scheme.png" "$DST/path-$locale-$scheme.png"
    cp "$SRC/04-today-done-$locale-$scheme.png" "$DST/today-done-$locale-$scheme.png"
  done
  cp "$SRC/70-share-$locale.png" "$DST/share-$locale.png"
done
sips -Z 1200 "$DST"/*.png >/dev/null
ls "$DST" | wc -l | tr -d ' '
