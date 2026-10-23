#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep PyInstaller's cache inside this worktree, including --clean operations.
export PYINSTALLER_CONFIG_DIR="$PWD/build/pyinstaller-cache"
# Resolve the local package when analyzing the entry point under scripts/.
export PYTHONPATH="$PWD${PYTHONPATH:+:$PYTHONPATH}"
# A Developer ID identity signs every bundled library too, so the hardened runtime can load them after extraction.
SIGNING=()
if [ -n "${SIGN_IDENTITY:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  SIGNING=(--codesign-identity "$SIGN_IDENTITY" --osx-entitlements-file macos/engine.entitlements)
fi
.venv/bin/python -m PyInstaller --onefile --name 365engine --clean --noconfirm \
  --exclude-module fastapi --exclude-module sqlalchemy --exclude-module cloud \
  --add-data agentfit/engine/content_pool.json:agentfit/engine \
  ${SIGNING[@]+"${SIGNING[@]}"} \
  scripts/engine_entry.py
ls -lh dist/365engine
