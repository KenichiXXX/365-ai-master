"""Invented fixtures exercise usage formats, not reference implementation code."""
import json
from pathlib import Path
import shutil
import sqlite3

import pytest

from agentfit.engine.collectors.gemini import GeminiCollector
from agentfit.engine.collectors.opencode import OpenCodeCollector
from agentfit.engine.collectors.qwen import QwenCollector
from agentfit.engine.scan_state import ScanState

FIX = Path(__file__).parent / "fixtures"


def setup_home(home, kind):
    if kind == "gemini":
        target = home / ".gemini/tmp/project/chats/session-example.json"
        source = FIX / "gemini/session-example.json"
    elif kind == "qwen":
        target = home / ".qwen/usage_record.jsonl"
        source = FIX / "qwen/usage_record.jsonl"
    else:
        target = home / ".local/share/opencode/opencode.db"
        target.parent.mkdir(parents=True)
        with sqlite3.connect(target) as db:
            db.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, data TEXT)")
            db.executemany("INSERT INTO message VALUES (?, ?, ?, ?)", [
                ("o1", "demo-o", 1792497600000, (FIX / "opencode/message.json").read_text()),
                ("bad", "demo-o", 1792497600001, "{broken"),
                ("bad-shape", "demo-o", 1792497600002, "[]"),
            ])
        return target
    target.parent.mkdir(parents=True)
    shutil.copyfile(source, target)
    return target


@pytest.mark.parametrize("kind,cls,expected", [
    ("gemini", GeminiCollector, (60, 16, 30, 0, "gemini-example")),
    ("opencode", OpenCodeCollector, (70, 14, 20, 5, "example-model")),
    ("qwen", QwenCollector, (60, 17, 40, 0, "qwen-example")),
])
def test_usage_contract_and_persisted_rescan(tmp_path, kind, cls, expected):
    collector = cls()
    assert not collector.detect(tmp_path)
    path = setup_home(tmp_path, kind)
    before = path.read_bytes()
    assert collector.detect(tmp_path)
    assert collector.tier == "usage" and collector.inventory(tmp_path) is None
    state = ScanState(tmp_path / "state.json")
    events = collector.scan(tmp_path, state)
    assert len(events) == 1
    e = events[0]
    assert (e.input, e.output, e.cache_read, e.cache_write, e.model) == expected
    assert e.tool == collector.tool and e.dt().year == 2026
    assert not e.tool_calls and not e.skill_calls and e.cwd is None and e.turn_start == 0
    state.save()
    assert collector.scan(tmp_path, ScanState(state.path)) == events
    assert path.read_bytes() == before


@pytest.mark.parametrize("kind,cls", [("gemini", GeminiCollector), ("opencode", OpenCodeCollector), ("qwen", QwenCollector)])
def test_bad_records_are_skipped(tmp_path, kind, cls):
    path = setup_home(tmp_path, kind)
    if kind == "gemini":
        doc = json.loads(path.read_text())
        doc["messages"].extend([None, [], {"id":"bad2", "type":"gemini", "timestamp":"invalid", "tokens":{"input": "oops"}}])
        path.write_text(json.dumps(doc))
    elif kind == "qwen":
        with path.open("a") as f:
            f.write('oops\n[]\n' + json.dumps({"version":1,"sessionId":"bad","timestamp":"invalid","models":{"m":{"inputTokens":"oops"}}}) + '\n')
    assert len(cls().scan(tmp_path, ScanState(tmp_path / "state.json"))) == 1


def test_qwen_replaces_summary_and_handles_partial_append(tmp_path):
    path = setup_home(tmp_path, "qwen")
    collector = QwenCollector(); state = ScanState(tmp_path / "state.json")
    original = collector.scan(tmp_path, state)
    row = json.loads(path.read_text()); row["models"]["qwen-example"]["inputTokens"] = 200
    with path.open("a") as f: f.write(json.dumps(row))
    assert collector.scan(tmp_path, state) == original
    with path.open("a") as f: f.write("\n")
    updated = collector.scan(tmp_path, state)
    assert len(updated) == 1 and updated[0].input == 160
    path.write_text(json.dumps({**row, "sessionId":"new-session"}) + "\n")
    assert collector.scan(tmp_path, state)[0].key != original[0].key


def test_opencode_updates_existing_rows_and_reads_wal(tmp_path, monkeypatch):
    path = setup_home(tmp_path, "opencode")
    collector = OpenCodeCollector(); state = ScanState(tmp_path / "state.json")
    collector.scan(tmp_path, state)
    real_connect = sqlite3.connect
    def checked_connect(database, **kwargs):
        assert database.endswith("?mode=ro") and kwargs["uri"] is True
        db = real_connect(database, **kwargs)
        with pytest.raises(sqlite3.OperationalError):
            db.execute("CREATE TABLE forbidden (x)")
        return db
    with real_connect(path) as writer:
        writer.execute("PRAGMA journal_mode=WAL")
        row = json.loads((FIX / "opencode/message.json").read_text())
        row["tokens"]["input"] = 99
        writer.execute("UPDATE message SET data=? WHERE id='o1'", (json.dumps(row),))
        writer.execute("INSERT INTO message VALUES ('o2','s',1792497600000,?)", (json.dumps(row),))
        writer.commit()
        monkeypatch.setattr(sqlite3, "connect", checked_connect)
        events = collector.scan(tmp_path, state)
        assert len(events) == 2 and sum(e.input for e in events) == 198
    state.save()
    assert len(collector.scan(tmp_path, ScanState(state.path))) == 2


def test_opencode_legacy_dedup(tmp_path):
    setup_home(tmp_path, "opencode")
    legacy = tmp_path / ".local/share/opencode/storage/message/ses_demo"
    legacy.mkdir(parents=True)
    row = json.loads((FIX / "opencode/message.json").read_text())
    row["tokens"]["input"] = 999
    (legacy / "msg_duplicate.json").write_text(json.dumps(row))
    row["id"] = "legacy-only"
    (legacy / "msg_other.json").write_text(json.dumps(row))
    events = OpenCodeCollector().scan(tmp_path, ScanState(tmp_path / "state.json"))
    assert len(events) == 2 and sum(e.input for e in events) == 1069


@pytest.mark.parametrize("root", ["tmp", "antigravity-cli/conversations", "antigravity/conversations", "antigravity-ide/conversations", "gemini-cli/conversations"])
def test_gemini_journal_paths_updates_and_rewind(tmp_path, root):
    path = tmp_path / ".gemini" / root / "project/chats/parent/session-child.jsonl"
    path.parent.mkdir(parents=True)
    message = json.loads((FIX / "gemini/session-example.json").read_text())["messages"][0]
    rows = [{"sessionId":"journal"}, message, {**message, "id":"g2"}]
    path.write_text("".join(json.dumps(r)+"\n" for r in rows))
    collector = GeminiCollector(); state = ScanState(tmp_path / "state.json")
    assert len(collector.scan(tmp_path, state)) == 2
    with path.open("a") as f:
        f.write(json.dumps({"$rewindTo":"g2"}) + "\n")
        f.write(json.dumps({**message, "tokens":{"input":150}}) + "\n")
    events = collector.scan(tmp_path, state)
    assert len(events) == 1 and events[0].input == 150
    with path.open("a") as f:
        f.write(json.dumps({"$set":{"messages":[{**message,"id":"checkpoint"}]}}) + "\n")
    assert "checkpoint" in collector.scan(tmp_path, state)[0].key


# Small independent protobuf fixture encoder; all values are synthetic.
def varint(value):
    encoded = []
    while value >= 128:
        encoded.append((value % 128) + 128); value //= 128
    return bytes(encoded + [value])


def field(number, value):
    if isinstance(value, int):
        return varint(number * 8) + varint(value)
    return varint(number * 8 + 2) + varint(len(value)) + value


@pytest.mark.parametrize("referenced", [False, True])
def test_gemini_antigravity_database(tmp_path, referenced):
    path = tmp_path / ".gemini/antigravity-cli/conversations/demo.db"
    path.parent.mkdir(parents=True)
    tokens = field(2, 42) + field(3, 18) + field(5, 80) + field(9, 6)
    generation = field(19, b"gemini-db") + field(4, tokens)
    if not referenced:
        generation += field(9, field(4, field(1, 1792497600)))
    blob = field(1, generation)
    if referenced:
        blob += field(2, varint(7))
    with sqlite3.connect(path) as db:
        db.execute("CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY, data BLOB, size INTEGER)")
        db.executemany("INSERT INTO gen_metadata VALUES (?, ?, ?)", [(0,blob,len(blob)),(1,b"\xff"*20,20)])
        db.execute("CREATE TABLE steps (idx INTEGER PRIMARY KEY, metadata BLOB)")
        db.execute("INSERT INTO steps VALUES (7, ?)", (field(1,field(1,1792497600)),))
    collector = GeminiCollector(); state = ScanState(tmp_path / "state.json")
    events = collector.scan(tmp_path, state)
    assert len(events) == 1
    e = events[0]
    assert (e.input,e.output,e.cache_read,e.model) == (42,18,80,"gemini-db")
    state.save()
    assert collector.scan(tmp_path, ScanState(state.path)) == events


def test_forbidden_filenames_never_opened(tmp_path, monkeypatch):
    for root in (".gemini/tmp/p/chats", ".qwen/usage", ".local/share/opencode/storage/message/ses_x"):
        directory = tmp_path / root; directory.mkdir(parents=True)
        for name in ("session-auth.json", "session-credential.jsonl", "msg_auth.json", "token-usage-oauth.jsonl"):
            (directory / name).write_text("do not read")
    original = Path.open
    def guarded(path, *args, **kwargs):
        assert not any(word in path.name.lower() for word in ("auth", "credential"))
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, "open", guarded)
    for collector in (GeminiCollector(), OpenCodeCollector(), QwenCollector()):
        assert collector.scan(tmp_path, ScanState(tmp_path / "state.json")) == []


@pytest.mark.parametrize("kind,cls", [("gemini", GeminiCollector), ("opencode", OpenCodeCollector), ("qwen", QwenCollector)])
def test_removed_sources_drop_cached_events(tmp_path, kind, cls):
    path = setup_home(tmp_path, kind)
    state = ScanState(tmp_path / "state.json")
    assert cls().scan(tmp_path, state)
    path.unlink()
    assert cls().scan(tmp_path, state) == []
    assert state.files(cls.tool) == []


def test_gemini_migration_prefers_journal(tmp_path):
    path = setup_home(tmp_path, "gemini")
    doc = json.loads(path.read_text())
    journal = path.with_suffix(".jsonl")
    message = {**doc["messages"][0], "id":"new", "tokens":{"input":33}}
    journal.write_text(json.dumps({"sessionId":doc["sessionId"]}) + "\n" + json.dumps(message) + "\n")
    events = GeminiCollector().scan(tmp_path, ScanState(tmp_path / "state.json"))
    assert len(events) == 1 and events[0].input == 33


@pytest.mark.parametrize("kind,cls", [("gemini", GeminiCollector), ("qwen", QwenCollector)])
def test_symlink_to_forbidden_file_not_opened(tmp_path, monkeypatch, kind, cls):
    path = setup_home(tmp_path, kind)
    secret = tmp_path / "private-auth.json"
    path.rename(secret)
    path.symlink_to(secret)
    original = Path.open
    def guarded(file, *args, **kwargs):
        assert file.resolve() != secret
        return original(file, *args, **kwargs)
    monkeypatch.setattr(Path, "open", guarded)
    assert cls().scan(tmp_path, ScanState(tmp_path / "state.json")) == []


def test_qwen_request_logs_and_summary_overlap(tmp_path):
    from agentfit.engine.collectors._usage import allowed

    summary = setup_home(tmp_path, "qwen")
    path = tmp_path / ".qwen/usage/token-usage-2026-10.jsonl"
    path.parent.mkdir()
    row = {"schemaVersion": 1, "id": "r1", "sessionId": "demo-q",
           "timestamp": "2026-10-20T12:00:00Z", "model": "qwen-example",
           "inputTokens": 100, "cachedTokens": 40, "outputTokens": 12,
           "thoughtsTokens": 5}
    # Match the existing summary: neither source should be double counted.
    row["sessionId"] = json.loads(summary.read_text())["sessionId"]
    path.write_text(json.dumps(row) + "\n" + json.dumps(row) + "\n[]\nbroken\n")
    assert allowed(path)
    collector = QwenCollector(); state = ScanState(tmp_path / "state.json")
    events = collector.scan(tmp_path, state)
    assert [(e.input, e.output, e.cache_read) for e in events] == [(60, 17, 40)]
    state.save()
    assert collector.scan(tmp_path, ScanState(state.path)) == events
    summary.unlink()
    assert collector.scan(tmp_path, state) == events
    with path.open("a") as f:
        f.write(json.dumps({**row, "id": "r2"}) + "\n")
    assert len(collector.scan(tmp_path, state)) == 2
    path.unlink()
    assert collector.scan(tmp_path, state) == []
    assert state.files(collector.tool) == []
