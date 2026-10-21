import shutil
from pathlib import Path
from agentfit.engine.collectors.codex import CodexCollector, latest_rate_limits
from agentfit.engine.scan_state import ScanState

FIX = Path(__file__).parent / "fixtures" / "codex"

def _home(tmp_path):
    shutil.copytree(FIX, tmp_path / ".codex"); return tmp_path

def test_codex_usage_and_markers(tmp_path):
    home = _home(tmp_path)
    ev = CodexCollector().scan(home, ScanState(tmp_path / "s.json"))
    usage = [e for e in ev if e.model]
    assert len({e.key for e in usage}) == 1          # resp1 deduped (profile also dedupes)
    u = usage[0]
    assert (u.input, u.cache_read, u.output, u.model, u.effort) == (200, 800, 50, "gpt-6.1-sol", "low")
    calls = {}
    for e in ev:
        for k, v in e.tool_calls.items(): calls[k] = calls.get(k, 0) + v
    assert calls == {"shell": 1, "spawn_agent": 1}
    assert any(e.sidechain for e in ev)
    assert sum(e.turn_start for e in ev) == 1 and sum(e.aborted for e in ev) == 1
    assert sum(e.compacted for e in ev) == 1

def test_rate_limits(tmp_path):
    rl = latest_rate_limits(_home(tmp_path))
    assert rl["primary_pct"] == 42.5 and rl["primary_window_min"] == 300
    assert rl["secondary_pct"] == 10.0 and rl["plan_type"] == "pro"
    assert rl["primary_resets_at"].startswith("2026-")

def test_rate_limits_none_without_logs(tmp_path):
    assert latest_rate_limits(tmp_path) is None


def test_incremental_scan_preserves_context_and_line_numbers(tmp_path):
    import json

    home = _home(tmp_path)
    log = home / ".codex/sessions/2026/10/20/rollout-1.jsonl"
    rows = log.read_text().splitlines()
    log.write_text("\n".join(rows[:2]) + "\n")
    state_path = tmp_path / "s.json"
    state = ScanState(state_path)
    assert CodexCollector().scan(home, state) == []
    state.save()
    with log.open("a") as stream:
        stream.write("\n".join(rows[2:]) + "\n")
    state = ScanState(state_path)
    events = CodexCollector().scan(home, state)
    usage = [e for e in events if e.model]
    assert len(usage) == 1
    assert (usage[0].model, usage[0].effort, usage[0].cwd) == ("gpt-6.1-sol", "low", "/tmp/x")
    assert "turn:rollout-1:3" in {e.key for e in events}
    assert CodexCollector().scan(home, state) == events
    with log.open("a") as stream:
        stream.write(rows[2] + "\n" + rows[4] + "\n")
    events = CodexCollector().scan(home, state)
    assert sum(e.turn_start for e in events) == 2
    assert len([e for e in events if e.model]) == 1
    log.write_text(json.dumps({"timestamp": "2026-10-21T00:00:00Z", "type": "token_usage_record",
                               "payload": {"turn_id": "new", "usage": {"input_tokens": 2, "cached_input_tokens": 5}}}) + "\n")
    events = CodexCollector().scan(home, state)
    assert len(events) == 1
    assert (events[0].key, events[0].model, events[0].input, events[0].cwd) == ("new", "codex-unknown", 0, None)
    log.unlink()
    assert CodexCollector().scan(home, state) == []
    assert state.files("codex") == []


def test_archived_logs_and_malformed_lines(tmp_path):
    home = _home(tmp_path)
    (home / ".codex/sessions").rename(home / ".codex/archived_sessions")
    log = next((home / ".codex/archived_sessions").rglob("*.jsonl"))
    with log.open("a") as stream:
        stream.write('not json\nnull\n{"type":"token_usage_record","payload":null}\n')
    collector = CodexCollector()
    assert collector.detect(home)
    assert collector.inventory(home).to_public() == {
        "skills_installed": 0, "instructions_bytes": 0, "hooks": 0,
        "mcp_servers": 0, "subagents": 0, "plugins": 0,
    }
    assert len([e for e in collector.scan(home, ScanState(tmp_path / "s.json")) if e.model]) == 1
    assert latest_rate_limits(home)["primary_pct"] == 42.5


def test_rate_limits_newest_event_in_five_newest_files(tmp_path):
    import json
    import os
    from datetime import datetime, timezone

    root = tmp_path / ".codex/sessions"
    root.mkdir(parents=True)
    for i in range(6):
        row = {"timestamp": f"2026-10-{26-i:02d}T00:00:00Z", "type": "event_msg",
               "payload": {"type": "token_count", "rate_limits": {
                   "primary": {"used_percent": i, "window_minutes": 300, "resets_at": 1792540800}}}}
        log = root / f"rollout-{i}.jsonl"
        log.write_text(json.dumps(row) + "\n")
        os.utime(log, (1000+i, 1000+i))
    limits = latest_rate_limits(tmp_path)
    assert limits == {"primary_pct": 1.0, "primary_window_min": 300,
                      "primary_resets_at": datetime.fromtimestamp(1792540800, timezone.utc).isoformat(),
                      "secondary_pct": None, "secondary_window_min": None,
                      "secondary_resets_at": None, "plan_type": None}
