#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
REPO="$(cd "$REPO" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.365aimaster.harvest.plist"
mkdir -p "$(dirname "$PLIST")" "$HOME/Library/Logs"
"$REPO/.venv/bin/python" - "$REPO" "$HOME" "$PLIST" <<'PYTHON'
from pathlib import Path
import plistlib
import sys

repo, home, destination = sys.argv[1:]
source = Path(repo) / "scripts/harvest/com.365aimaster.harvest.plist"
config = plistlib.loads(source.read_bytes())
config["ProgramArguments"] = [str(Path(repo) / "scripts/harvest/run_daily.sh"), repo]
log = str(Path(home) / "Library/Logs/365aimaster-harvest.log")
config["StandardOutPath"] = config["StandardErrorPath"] = log
config["EnvironmentVariables"]["PATH"] = f"/opt/homebrew/bin:/usr/local/bin:{home}/.local/bin:/usr/bin:/bin"
Path(destination).write_bytes(plistlib.dumps(config, sort_keys=False))
PYTHON
launchctl bootstrap "gui/$(id -u)" "$PLIST"
printf '%s\n' 'Installed daily rankings harvest at 07:30 local time.'
printf 'Uninstall: launchctl bootout gui/%s %q && rm %q\n' "$(id -u)" "$PLIST" "$PLIST"
