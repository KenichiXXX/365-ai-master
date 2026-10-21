"""Synthetic source coverage and privacy regressions for Task 26."""
import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from agentfit.engine.collectors.claude_code import ClaudeCodeCollector
from agentfit.engine.collectors.codex import CodexCollector
from agentfit.engine.inventory import claude_inventory
from agentfit.engine.profile import build_profile
from agentfit.engine.scan_state import ScanState
from agentfit.engine.snapshot import build_snapshot

NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
SECRET = "PRIVATE SENTINEL /private/project --secret"


def write_rows(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join((r if isinstance(r, str) else json.dumps(r)) + "\n" for r in rows))
    return path


def claude(ident="msg1", blocks=None):
    return {"type": "assistant", "uuid": "line1", "timestamp": NOW.isoformat(),
            "message": {"id": ident, "model": "claude-sonnet-5", "usage": {
                "input_tokens": 10, "output_tokens": 20}, "content": blocks or []}}


def coverage(home, state, tool="claude_code"):
    snap = build_snapshot(home, state, "en", NOW, enabled={tool})
    assert snap["schema"] == 3
    return snap["coverage"][tool]


def test_six_statuses_and_persisted_counts(tmp_path, monkeypatch):
    home, state = tmp_path / "home", tmp_path / "state"
    home.mkdir()
    assert coverage(home, state)["status"] == "not_detected"
    (home / ".claude").mkdir()
    assert coverage(home, state)["status"] == "no_logs"
    log = write_rows(home / ".claude/projects/demo/log.jsonl", [{"future_format": 99}])
    assert coverage(home, state)["status"] == "unsupported"
    write_rows(log, [claude(), "broken json", {"future_format": 99}])
    partial = coverage(home, state)
    assert partial["status"] == "partial"
    assert partial["valid_usage_count"] == 1
    assert partial["malformed_count"] == 1 and partial["skipped_count"] == 1
    assert partial["signals"]["tool_calls"] == "unknown"
    assert partial == coverage(home, state)
    write_rows(log, [claude()])
    good = coverage(home, state)
    assert good["status"] == "ok"
    assert good["signals"]["tool_calls"] == "available"
    assert good["signals"]["aborted"] == "unsupported"
    assert good["adapter_version"] and good["format"]
    assert good["start_utc"] == good["end_utc"] == NOW.isoformat()
    original = Path.open
    def denied(path, *args, **kwargs):
        if path == log:
            raise PermissionError("private path must not leak")
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, "open", denied)
    denied_row = coverage(home, state)
    assert denied_row["status"] == "permission_denied"
    assert denied_row["signals"]["usage"] == "unknown"
    assert "private path" not in json.dumps(denied_row)


def test_streaming_blocks_and_parent_child_overlap(tmp_path):
    blocks = [{"type": "tool_use", "id": "tool1", "name": "Read", "input": {"path": SECRET}},
              {"type": "tool_use", "id": "skill1", "name": "Skill", "input": {"skill": "tdd"}}]
    first = claude(blocks=blocks)
    second = claude(blocks=blocks + [{"type": "tool_use", "id": "tool2", "name": "Read"}])
    second["message"]["usage"]["output_tokens"] = 30
    log = write_rows(tmp_path / ".claude/projects/demo/log.jsonl", [first, second])
    write_rows(log.parent / "log/subagents/child.jsonl", [first, second])
    state = ScanState(tmp_path / "state.json")
    events = ClaudeCodeCollector().scan(tmp_path, state)
    profile = build_profile(events, NOW)
    assert profile.usage_by_model_7d["claude-sonnet-5"]["tokens"] == 40
    assert profile.tool_calls_14d == {"Read": 2, "Skill": 1}
    assert profile.skill_calls_14d == {"tdd": 1}
    assert profile == build_profile(events + events, NOW)
    assert SECRET not in json.dumps(state.state)


@pytest.mark.parametrize("tool,relative", [
    ("claude_code", ".claude/projects/demo/log.jsonl"),
    ("codex", ".codex/sessions/log.jsonl"),
    ("qwen_code", ".qwen/usage/token-usage-1.jsonl"),
    ("gemini_cli", ".gemini/tmp/demo/session-1.json"),
    ("opencode", ".local/share/opencode/storage/message/ses_1/msg_1.json"),
])
def test_symlink_escapes_are_never_opened(tmp_path, monkeypatch, tool, relative):
    home = tmp_path / "home"; home.mkdir()
    outside = tmp_path / "outside.jsonl"; outside.write_text(SECRET)
    link = home / relative; link.parent.mkdir(parents=True); link.symlink_to(outside)
    original = Path.open
    def guarded(path, *args, **kwargs):
        assert path.resolve() != outside, "source root escaped"
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, "open", guarded)
    row = coverage(home, tmp_path / "state", tool)
    assert row["status"] in {"unsupported", "no_logs"}
    assert row["valid_usage_count"] == 0


def test_inventory_does_not_open_mixed_account_config_or_instruction_bodies(tmp_path, monkeypatch):
    root = tmp_path / ".claude"; root.mkdir()
    (tmp_path / ".claude.json").write_text(json.dumps({"oauthAccount": SECRET, "mcpServers": {"a": {}}}))
    (root / "CLAUDE.md").write_text(SECRET)
    (root / "settings.json").write_text(json.dumps({"hooks": {"Stop": []}, "env": {"SECRET": SECRET}}))
    original = Path.open
    def guarded(path, *args, **kwargs):
        assert path.name != ".claude.json" and path.suffix != ".md"
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, "open", guarded)
    inv = claude_inventory(tmp_path, set())
    assert inv.mcp_servers is None
    assert inv.instructions_bytes == len(SECRET)
    assert SECRET not in json.dumps(inv.to_public())


def test_skill_arguments_not_persisted_and_bad_record_isolated(tmp_path):
    row = claude(blocks=[{"type": "tool_use", "id": "s", "name": "Skill", "input": {"skill": SECRET}}])
    write_rows(tmp_path / ".claude/projects/demo/log.jsonl", [row, {"type": "assistant", "timestamp": NOW.isoformat(), "message": "bad"}])
    snap = build_snapshot(tmp_path, tmp_path / "state", "en", NOW)
    assert snap["coverage"]["claude_code"]["status"] == "partial"
    assert snap["coverage"]["claude_code"]["valid_usage_count"] == 1
    assert SECRET not in json.dumps(snap)
    assert SECRET not in (tmp_path / "state/scan.json").read_text()


def test_failed_collector_preserves_other_tools(tmp_path, monkeypatch):
    write_rows(tmp_path / ".claude/projects/demo/log.jsonl", [claude()])
    (tmp_path / ".codex").mkdir()
    def fail(*args):
        raise PermissionError(SECRET)
    monkeypatch.setattr(CodexCollector, "scan", fail)
    snap = build_snapshot(tmp_path, tmp_path / "state", "en", NOW)
    assert snap["coverage"]["codex"]["status"] == "permission_denied"
    assert snap["coverage"]["claude_code"]["valid_usage_count"] == 1
    assert SECRET not in json.dumps(snap)


def test_codex_cumulative_is_unknown_without_verified_adapter(tmp_path):
    write_rows(tmp_path / ".codex/sessions/log.jsonl", [{"type": "event_msg", "timestamp": NOW.isoformat(),
        "payload": {"type": "token_count", "info": {"total_token_usage": {"input_tokens": 999}}}}])
    row = coverage(tmp_path, tmp_path / "state", "codex")
    assert row["status"] == "partial"
    assert row["valid_usage_count"] == 0 and row["signals"]["usage"] == "unknown"


@pytest.mark.parametrize("kind", ["gemini", "opencode", "qwen"])
def test_usage_adapter_mixed_records_report_partial_and_recover(tmp_path, kind):
    from tests.engine.test_usage_collectors import setup_home
    path = setup_home(tmp_path, kind)
    tool = {"gemini": "gemini_cli", "opencode": "opencode", "qwen": "qwen_code"}[kind]
    if kind == "gemini":
        doc = json.loads(path.read_text())
        doc["messages"].append({"id": "bad", "type": "gemini", "tokens": {"input": "oops"}})
        path.write_text(json.dumps(doc))
    elif kind == "qwen":
        with path.open("a") as stream:
            stream.write("broken\n")
    # The OpenCode fixture already has malformed rows beside its valid row.
    row = coverage(tmp_path, tmp_path / "state", tool)
    assert row["status"] == "partial"
    assert row["malformed_count"] >= 1
    assert row == coverage(tmp_path, tmp_path / "state", tool)


def test_codex_counter_reset_model_switch_and_explicit_precedence(tmp_path):
    rows = []
    for model, total in [("gpt-6.1-sol", 100), ("gpt-6.1-sol", 5), ("another", 80)]:
        rows.extend([
            {"type": "turn_context", "payload": {"model": model}},
            {"type": "event_msg", "timestamp": NOW.isoformat(), "payload": {
                "type": "token_count", "info": {"total_token_usage": {"input_tokens": total}}}},
        ])
    rows.append({"type": "token_usage_record", "timestamp": NOW.isoformat(), "payload": {
        "response_id": "r", "usage": {"input_tokens": 20, "output_tokens": 3}}})
    write_rows(tmp_path / ".codex/sessions/log.jsonl", rows)
    write_rows(tmp_path / ".codex/archived_sessions/copy.jsonl", rows)
    snap = build_snapshot(tmp_path, tmp_path / "state", "en", NOW, enabled={"codex"})
    assert snap["coverage"]["codex"]["status"] == "partial"
    assert snap["coverage"]["codex"]["valid_usage_count"] == 1
    assert snap["usage_summary"]["tokens_7d"] == 23
    assert snap == build_snapshot(tmp_path, tmp_path / "state", "en", NOW, enabled={"codex"})


def test_sqlite_reads_only_usage_tables_and_never_writes_sources(tmp_path, monkeypatch):
    import sqlite3

    from tests.engine.test_usage_collectors import setup_home
    path = setup_home(tmp_path, "opencode")
    with sqlite3.connect(path) as db:
        db.execute("CREATE TABLE credential (secret TEXT)")
        db.execute("CREATE TABLE account (secret TEXT)")
    before = path.read_bytes()
    original = sqlite3.connect
    statements = []
    def guarded(database, **kwargs):
        assert database.endswith("?mode=ro")
        db = original(database, **kwargs)
        db.set_trace_callback(statements.append)
        return db
    monkeypatch.setattr(sqlite3, "connect", guarded)
    coverage(tmp_path, tmp_path / "state", "opencode")
    assert statements and all("credential" not in s.lower() and "account" not in s.lower() for s in statements)
    assert all(s.startswith(("SELECT", "PRAGMA query_only")) for s in statements)
    assert path.read_bytes() == before


def test_symlinked_source_root_and_config_never_opened(tmp_path, monkeypatch):
    home = tmp_path / "home"; home.mkdir()
    outside = tmp_path / "elsewhere"; outside.mkdir()
    write_rows(outside / "projects/p/log.jsonl", [claude()])
    (outside / "settings.json").write_text(SECRET)
    (home / ".claude").symlink_to(outside, target_is_directory=True)
    original = Path.open
    def guarded(path, *args, **kwargs):
        assert not path.resolve().is_relative_to(outside)
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, "open", guarded)
    row = coverage(home, tmp_path / "state")
    assert row["valid_usage_count"] == 0


def test_legacy_cache_rebuilt_without_private_arguments(tmp_path):
    log = write_rows(tmp_path / ".claude/projects/demo/log.jsonl", [claude()])
    state = ScanState(tmp_path / "state/scan.json")
    ClaudeCodeCollector().scan(tmp_path, state)
    cursor = state.state["tools"]["claude_code"][str(log)]
    cursor.pop("adapter_version", None)
    cursor["events"][0]["skill_calls"] = {SECRET: 1}
    state.save()
    snap = build_snapshot(tmp_path, state.path.parent, "en", NOW)
    assert SECRET not in state.path.read_text()
    assert SECRET not in json.dumps(snap)


def test_unreadable_directory_is_denied_not_empty(tmp_path, monkeypatch):
    import os
    root = tmp_path / ".claude/projects"
    root.mkdir(parents=True)
    original = os.scandir
    def denied(path):
        if Path(path) == root:
            raise PermissionError(13, "denied", str(path))
        return original(path)
    monkeypatch.setattr(os, "scandir", denied)
    assert coverage(tmp_path, tmp_path / "state")["status"] == "permission_denied"


def test_shared_block_id_dedupes_independently_of_usage_id(tmp_path):
    block = {"type": "tool_use", "id": "shared", "name": "Read"}
    write_rows(tmp_path / ".claude/projects/p/log.jsonl", [
        claude("m1", [block]), claude("m2", [block]),
    ])
    events = ClaudeCodeCollector().scan(tmp_path, ScanState(tmp_path / "state.json"))
    profile = build_profile(events, NOW)
    assert profile.usage_by_model_7d["claude-sonnet-5"]["requests"] == 2
    assert profile.tool_calls_14d == {"Read": 1}


def test_removed_installation_does_not_reuse_stale_coverage(tmp_path):
    import shutil
    write_rows(tmp_path / ".claude/projects/p/log.jsonl", [claude(), "broken"])
    assert coverage(tmp_path, tmp_path / "state")["status"] == "partial"
    shutil.rmtree(tmp_path / ".claude")
    row = coverage(tmp_path, tmp_path / "state")
    assert row["status"] == "not_detected"
    assert row["valid_usage_count"] == row["malformed_count"] == 0
