"""Gemini CLI JSON journals and conversation databases, parsed locally."""
from pathlib import Path
import sqlite3

from agentfit.engine.collectors.base import register
from agentfit.engine.collectors._usage import allowed, event, number, readonly_db, record, signature
from agentfit.engine.scan_state import ScanState


ROOTS = ("tmp", "antigravity-cli/conversations", "antigravity/conversations",
         "antigravity-ide/conversations", "gemini-cli/conversations")


def _varint(data, position):
    value = 0
    for shift in range(0, 70, 7):
        if position >= len(data):
            raise ValueError("Truncated integer")
        byte = data[position]
        position += 1
        if shift == 63 and byte > 1:
            raise ValueError("Oversized integer")
        value |= (byte & 127) << shift
        if byte < 128:
            return value, position
    raise ValueError("Oversized integer")


def _fields(data):
    if not isinstance(data, bytes):
        raise ValueError("Invalid binary record")
    fields = {}
    pos = 0
    while pos < len(data):
        tag, pos = _varint(data, pos)
        number, wire = tag >> 3, tag & 7
        if number == 0:
            raise ValueError("Invalid field")
        if wire == 0:
            value, pos = _varint(data, pos)
        elif wire in (1, 2, 5):
            if wire == 2:
                length, pos = _varint(data, pos)
            else:
                length = 8 if wire == 1 else 4
            end = pos + length
            if end > len(data):
                raise ValueError("Truncated field")
            value, pos = data[pos:end], end
        else:
            raise ValueError("Unsupported wire type")
        fields.setdefault((number, wire), []).append(value)
    return fields


def _one(fields, number, wire, default=None):
    return fields.get((number, wire), [default])[-1]


def _database(path):
    events = []
    with readonly_db(path) as db:
        steps = {}
        if db.execute("SELECT 1 FROM sqlite_master WHERE name='steps' AND type='table'").fetchone():
            for index, metadata in db.execute("SELECT idx, metadata FROM steps"):
                try:
                    steps[index] = _one(_fields(_one(_fields(metadata), 1, 2)), 1, 0)
                except (ValueError, TypeError):
                    continue
        for index, blob in db.execute("SELECT idx, data FROM gen_metadata ORDER BY idx"):
            try:
                row = _fields(blob)
                references = []
                for packed in row.get((2, 2), []):
                    pos = 0
                    while pos < len(packed):
                        ref, pos = _varint(packed, pos)
                        references.append(ref)
                fallback = next((steps[r] for r in references if steps.get(r) is not None), None)
            except (ValueError, TypeError):
                continue
            for ordinal, generation in enumerate(row.get((1, 2), [])):
                try:
                    data = _fields(generation)
                    usage = _fields(_one(data, 4, 2))
                    ts = fallback
                    timing = _one(data, 9, 2)
                    if timing is not None:
                        nested = _one(_fields(timing), 4, 2)
                        if nested is not None:
                            ts = _one(_fields(nested), 1, 0, fallback)
                    if not isinstance(ts, int) or not 946684800 <= ts <= 1 << 34:
                        continue
                    inp = _one(usage, 2, 0, 0)
                    cached = _one(usage, 5, 0, 0)
                    thoughts = _one(usage, 9, 0, 0)
                    output = _one(usage, 3, 0, 0)  # Includes thoughts in this format.
                    response = _one(usage, 10, 0)
                    if response is not None:
                        output = response + thoughts
                    if max(inp, cached, output, thoughts) > 10**9:
                        continue
                    model = _one(data, 19, 2, b"unknown").decode("utf-8")
                    events.append(event("gemini_cli", f"{path.stem}:{index}:{ordinal}",
                                        ts, model, inp, output, cached))
                except (ValueError, TypeError, UnicodeError, OverflowError, OSError):
                    continue
    return path.stem, events


def _journal(path):
    messages = {}
    session = path.stem
    if path.suffix == ".json":
        rows = [record(path.read_text(encoding="utf-8"))]
    else:
        with path.open(encoding="utf-8") as stream:
            rows = [record(line) for line in stream if line.endswith("\n")]
    for row in rows:
        if isinstance(row.get("$rewindTo"), str):
            keys = list(messages)
            boundary = keys.index(row["$rewindTo"]) if row["$rewindTo"] in messages else 0
            messages = {key: messages[key] for key in keys[:boundary]}
            continue
        if isinstance(row.get("id"), str):
            messages[row["id"]] = row
            continue
        update = row.get("$set", row.get("$push", row))
        if not isinstance(update, dict):
            continue
        if isinstance(update.get("sessionId"), str):
            session = update["sessionId"]
        batch = update.get("messages")
        if isinstance(batch, list):
            if "$set" in row:
                messages.clear()
            for message in batch:
                if isinstance(message, dict) and isinstance(message.get("id"), str):
                    messages[message["id"]] = message
    events = []
    for identity, message in messages.items():
        if message.get("type") != "gemini" or not isinstance(message.get("tokens"), dict):
            continue
        usage = message["tokens"]
        try:
            cached = number(usage.get("cached", 0))
            events.append(event("gemini_cli", f"{len(session)}:{session}:{identity}",
                                message.get("timestamp"), message.get("model") or "unknown",
                                max(0, number(usage.get("input", 0)) - cached),
                                number(usage.get("output", 0)) + number(usage.get("thoughts", 0)), cached))
        except (ValueError, TypeError, OverflowError, OSError):
            continue
    return session, events


class GeminiCollector:
    tool = "gemini_cli"
    tier = "usage"

    def detect(self, home: Path) -> bool:
        return (home / ".gemini").is_dir()

    def inventory(self, home: Path) -> None:
        return None

    def scan(self, home: Path, state: ScanState) -> list:
        files = set()
        for directory in ROOTS:
            root = home / ".gemini" / directory
            for pattern in ("**/session-*.json", "**/session-*.jsonl", "*/chats/**/*.jsonl", "**/*.db"):
                files.update(p for p in root.glob(pattern) if p.is_file() and allowed(p)
                             and p.name != "conversation_summaries.db")
        sessions = {}
        for path in sorted(files):
            sig = signature(path)
            cursor = state.state["tools"].get(self.tool, {}).get(str(path), {})
            if cursor.get("signature") == sig:
                session, events = cursor["session"], state.cached_events(self.tool, path)
            else:
                try:
                    session, events = _database(path) if path.suffix == ".db" else _journal(path)
                except (OSError, UnicodeError, sqlite3.Error):
                    session, events = cursor.get("session", path.stem), state.cached_events(self.tool, path)
                else:
                    state.set_events(self.tool, path, events)
                    state.state["tools"][self.tool][str(path)].update(signature=sig, session=session)
            # Migrated journals supersede legacy snapshots of the same session.
            priority = ({".json":1, ".jsonl":2, ".db":3}[path.suffix], sig[0][2])
            if session not in sessions or priority > sessions[session][0]:
                sessions[session] = (priority, events)
        state.forget_missing(self.tool, {str(p) for p in files})
        return [e for _, events in sessions.values() for e in events]


register(GeminiCollector())
