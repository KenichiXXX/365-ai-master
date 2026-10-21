"""Small shared validation and read-only cache helpers for usage collectors."""
import json
import os
import re
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path

from agentfit.engine.events import CompactEvent


def allowed(path: Path, root: Path | None = None) -> bool:
    try:
        resolved = path.resolve()
        if root is not None and not resolved.is_relative_to(root.absolute()):
            return False
        parts = path.parts + resolved.parts
    except (OSError, RuntimeError):
        return False
    return not any(word in part.lower() for part in parts
                   for word in ("auth", "credential", "keychain", "oauth"))


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
    if not isinstance(key, str) or not key or not identifier(model):
        raise ValueError("Missing usage identity")
    return CompactEvent(tool=tool, key=safe_key(key), ts=timestamp(ts), model=model,
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


def identifier(value):
    """Only bounded machine identifiers, never arbitrary arguments or prose."""
    return value if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.:@/+-]{0,95}", value) else None


def safe_files(paths, root, state, tool):
    """Validate resolved paths before opening, including symlinked ancestors."""
    result = []
    for path in paths:
        companions = [Path(str(path) + suffix) for suffix in ("-wal", "-shm")] if path.suffix == ".db" else []
        if not allowed(path, root) or any(not allowed(p, root) for p in companions):
            state.issue(tool, "unsupported")
            continue
        try:
            if path.is_file():
                result.append(path)
        except PermissionError:
            state.issue(tool, "permission_denied")
    return result


def safe_key(value):
    if identifier(value):
        return value
    # Session/model composite identities are bounded and contain no arguments.
    match = re.match(r"([0-9]{1,3}):", value) if isinstance(value, str) else None
    if match:
        start, length = match.end(), int(match[1])
        if (value[start + length:start + length + 1] == ":"
                and identifier(value[start:start + length])
                and identifier(value[start + length + 1:])):
            return value
    # Qwen request keys encode three validated identifiers for reconciliation.
    try:
        parts = json.loads(value)
        if isinstance(parts, list) and len(parts) == 3 and all(identifier(v) for v in parts):
            return value
    except (ValueError, TypeError):
        pass
    return sha256(str(value).encode()).hexdigest()


def source_files(root, state=None, tool=""):
    """Walk without following directory links; permission errors are not emptiness."""
    def failed(exc):
        if state is not None and not isinstance(exc, FileNotFoundError):
            state.issue(tool, "permission_denied" if isinstance(exc, PermissionError) else "partial")
    if not allowed(root, root):
        if state is not None:
            state.issue(tool, "unsupported")
        return []
    result = []
    for directory, dirs, names in os.walk(root, onerror=failed):
        for name in list(dirs):
            path = Path(directory) / name
            if not allowed(path, root):
                dirs.remove(name)
                if state is not None:
                    state.issue(tool, "unsupported")
        result.extend(Path(directory) / name for name in names)
    return sorted(result)
