"""Small shared validation and read-only cache helpers for usage collectors."""
from contextlib import contextmanager
from datetime import datetime, timezone
import json
from pathlib import Path
import sqlite3

from agentfit.engine.events import CompactEvent


def allowed(path: Path) -> bool:
    try:
        parts = path.parts + path.resolve().parts
    except (OSError, RuntimeError):
        return False
    return not any(word in part.lower() for part in parts
                   for word in ("auth", "token", "credential", "keychain"))


def number(value=0) -> int:
    if value is None:
        return 0
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError("Invalid usage count")
    return value


def timestamp(value) -> str:
    if isinstance(value, bool):
        raise ValueError("Invalid timestamp")
    if isinstance(value, (int, float)):
        value = datetime.fromtimestamp(value / 1000 if value > 10**11 else value, timezone.utc)
    elif isinstance(value, str):
        value = datetime.fromisoformat(value.replace("Z", "+00:00"))
    else:
        raise ValueError("Missing timestamp")
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def event(tool, key, ts, model, inp=0, out=0, cached=0, written=0):
    if not isinstance(key, str) or not key or not isinstance(model, str) or not model:
        raise ValueError("Missing usage identity")
    return CompactEvent(tool=tool, key=key, ts=timestamp(ts), model=model,
                        input=number(inp), output=number(out),
                        cache_read=number(cached), cache_write=number(written))


def record(raw):
    try:
        value = json.loads(raw)
        return value if isinstance(value, dict) else {}
    except (ValueError, TypeError):
        return {}


def signature(path):
    result = []
    for candidate in (path, Path(str(path) + "-wal")):
        try:
            stat = candidate.stat()
            result.append([stat.st_ino, stat.st_size, stat.st_mtime_ns])
        except FileNotFoundError:
            result.append(None)
    return result


@contextmanager
def readonly_db(path):
    # as_uri escapes ?, # and % without importing any network modules.
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=1)
    try:
        db.execute("PRAGMA query_only=ON")
        yield db
    finally:
        db.close()
