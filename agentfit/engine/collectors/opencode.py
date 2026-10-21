"""Read OpenCode's local message database and legacy message JSON files."""
from pathlib import Path
import sqlite3

from agentfit.engine.collectors.base import register
from agentfit.engine.collectors._usage import allowed, event, number, readonly_db, record, signature
from agentfit.engine.scan_state import ScanState


def _message(row, identity=None, created=None):
    if row.get("role") != "assistant":
        return None
    try:
        usage = row["tokens"]
        cache = usage.get("cache") or {}
        return event("opencode", identity or row.get("id"),
                     (row.get("time") or {}).get("created") or created,
                     row.get("modelID") or (row.get("model") or {}).get("id") or "unknown",
                     usage.get("input", 0),
                     number(usage.get("output", 0)) + number(usage.get("reasoning", 0)),
                     cache.get("read", 0), cache.get("write", 0))
    except (KeyError, AttributeError, ValueError, TypeError, OverflowError, OSError):
        return None


class OpenCodeCollector:
    tool = "opencode"
    tier = "usage"

    def detect(self, home: Path) -> bool:
        return (home / ".local/share/opencode").is_dir()

    def inventory(self, home: Path) -> None:
        return None

    def scan(self, home: Path, state: ScanState) -> list:
        root = home / ".local/share/opencode"
        database = root / "opencode.db"
        files = ([database] if database.is_file() else []) + sorted((root / "storage/message").glob("ses_*/msg_*.json"))
        files = [p for p in files if allowed(p)]
        result = {}
        for path in files:
            sig = signature(path)
            cursor = state.state["tools"].get(self.tool, {}).get(str(path), {})
            if cursor.get("signature") == sig:
                events = state.cached_events(self.tool, path)
            else:
                events = []
                max_rowid = 0
                max_time = 0
                try:
                    if path == database:
                        with readonly_db(path) as db:
                            # Rows can be edited during streaming. Refresh changed databases
                            # instead of assuming the high-water mark is append-only.
                            for rowid, identity, created, raw in db.execute(
                                "SELECT rowid, id, time_created, data FROM message ORDER BY rowid"
                            ):
                                max_rowid = max(max_rowid, rowid)
                                if isinstance(created, int):
                                    max_time = max(max_time, created)
                                e = _message(record(raw), identity, created)
                                if e is not None:
                                    events.append(e)
                    else:
                        e = _message(record(path.read_text(encoding="utf-8")))
                        if e is not None:
                            events.append(e)
                except (OSError, UnicodeError, sqlite3.Error):
                    events = state.cached_events(self.tool, path)
                    for e in events:
                        result.setdefault(e.key, e)
                    continue
                state.set_events(self.tool, path, events)
                cursor = state.state["tools"][self.tool][str(path)]
                cursor.update(signature=sig, max_rowid=max_rowid, max_time=max_time)
            for e in events:
                result.setdefault(e.key, e)  # Database precedes legacy copies.
        state.forget_missing(self.tool, {str(p) for p in files})
        return list(result.values())


register(OpenCodeCollector())
