#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
REPO="$(cd "$REPO" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.365aimaster.harvest.plist"
mkdir -p "$(dirname "$PLIST")" "$HOME/Library/Logs"
# launchd agents may not read ~/Documents (macOS privacy). Copy just what the harvest needs
# into Application Support and run it from there. Re-run this script after updating the code.
RUNTIME="$HOME/Library/Application Support/365AIMaster-harvest/runtime"
ORIGIN="$(git -C "$REPO" remote get-url origin)"
PYTHON="$(readlink -f "$REPO/.venv/bin/python")"
rm -rf "$RUNTIME"
mkdir -p "$RUNTIME/scripts/harvest"
# Copy the whole agentfit package: validation imports grow over time (e.g. engine/prices.py).
rsync -a --exclude '__pycache__' "$REPO/agentfit" "$RUNTIME/"
cp "$REPO/scripts/harvest/harvest.py" "$REPO/scripts/harvest/run_daily.sh" "$RUNTIME/scripts/harvest/"
"$PYTHON" - "$RUNTIME" "$HOME" "$PLIST" "$ORIGIN" "$PYTHON" "$REPO" <<'PYTHON'
from pathlib import Path
import plistlib
import sys

repo, home, destination, origin, python, source_repo = sys.argv[1:]
source = Path(source_repo) / "scripts/harvest/com.365aimaster.harvest.plist"
config = plistlib.loads(source.read_bytes())
config["ProgramArguments"] = [str(Path(repo) / "scripts/harvest/run_daily.sh"), repo]
log = str(Path(home) / "Library/Logs/365aimaster-harvest.log")
config["StandardOutPath"] = config["StandardErrorPath"] = log
config["EnvironmentVariables"]["PATH"] = f"/opt/homebrew/bin:/usr/local/bin:{home}/.local/bin:/usr/bin:/bin"
config["EnvironmentVariables"]["HARVEST_ORIGIN"] = origin
config["EnvironmentVariables"]["HARVEST_PYTHON"] = python
Path(destination).write_bytes(plistlib.dumps(config, sort_keys=False))
PYTHON
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
printf '%s\n' 'Installed daily rankings harvest at 07:30 local time.'
printf 'Uninstall: launchctl bootout gui/%s %q && rm %q\n' "$(id -u)" "$PLIST" "$PLIST"
