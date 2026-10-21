#!/usr/bin/env bash
set -euo pipefail

CHECKOUT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
CLONE="$HOME/Library/Application Support/365AIMaster-harvest/repo"
LOG="$HOME/Library/Logs/365aimaster-harvest.log"
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
printf '\nHarvest started %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
ORIGIN="$(git -C "$CHECKOUT" remote get-url origin)"
REMOTE_CONTENT="$(git ls-remote --heads "$ORIGIN" refs/heads/content)"

if [[ ! -d "$CLONE/.git" ]]; then
    mkdir -p "$(dirname "$CLONE")"
    if [[ -n "$REMOTE_CONTENT" ]]; then
        git clone --single-branch --branch content "$ORIGIN" "$CLONE"
    else
        git init --initial-branch=content "$CLONE"
        cd "$CLONE"
        git checkout --orphan content
        git remote add origin "$ORIGIN"
        printf '%s\n' '# 365 AI Master public content' '' \
            'daily.json contains public Skill and Agent rankings. stars-history.json tracks public repository stars.' > README.md
        git add README.md
        git commit -m "content: initialize public rankings branch"
    fi
fi

cd "$CLONE"
[[ "$(git symbolic-ref --short HEAD)" == content ]] || { echo "Refusing non-content branch" >&2; exit 3; }
[[ "$(git remote get-url origin)" == "$ORIGIN" ]] || { echo "Unexpected origin" >&2; exit 3; }
git config remote.origin.fetch "+refs/heads/content:refs/remotes/origin/content"
git config branch.content.remote origin
git config branch.content.merge refs/heads/content
if [[ -n "$REMOTE_CONTENT" ]]; then
    git pull --ff-only
fi
"$CHECKOUT/.venv/bin/python" "$CHECKOUT/scripts/harvest/harvest.py" \
    --base "$CHECKOUT/agentfit/engine/content_pool.json" \
    --out "$CLONE/daily.json" --history "$CLONE/stars-history.json"
if ! git ls-files --error-unmatch daily.json >/dev/null 2>&1 || ! git diff --quiet HEAD -- daily.json; then
    git add daily.json stars-history.json
    git commit -m "content: daily $(date +%F)"
    git push origin content
fi
