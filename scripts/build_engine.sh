#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep PyInstaller's cache inside this worktree, including --clean operations.
export PYINSTALLER_CONFIG_DIR="$PWD/build/pyinstaller-cache"
# Resolve the local package when analyzing the entry point under scripts/.
export PYTHONPATH="$PWD${PYTHONPATH:+:$PYTHONPATH}"
.venv/bin/python -m PyInstaller --onefile --name 365engine --clean --noconfirm \
  --exclude-module fastapi --exclude-module sqlalchemy --exclude-module cloud \
  --add-data agentfit/engine/content_pool.json:agentfit/engine \
  scripts/engine_entry.py
ls -lh dist/365engine
