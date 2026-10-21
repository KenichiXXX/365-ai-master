import shutil
from pathlib import Path
from agentfit.engine.collectors.claude_code import ClaudeCodeCollector
from agentfit.engine.scan_state import ScanState

FIX = Path(__file__).parent / "fixtures" / "claude"

def _home(tmp_path):
    shutil.copytree(FIX, tmp_path / ".claude"); return tmp_path

def test_parses_and_dedupes(tmp_path):
    home = _home(tmp_path); c = ClaudeCodeCollector()
    assert c.detect(home)
    ev = c.scan(home, ScanState(tmp_path / "s.json"))
    usage = {e.key: e for e in ev if e.model}
    assert set(usage) == {"msg_1", "msg_2"}
    m1 = usage["msg_1"]
    assert (m1.input, m1.output, m1.cache_read, m1.cache_write) == (10, 50, 100, 20)
    assert m1.tool_calls == {"Read": 1, "Edit": 1, "Skill": 1}
    assert m1.skill_calls == {"tdd": 1} and m1.effort == "high"
    assert usage["msg_2"].sidechain and usage["msg_2"].tool_calls == {"mcp": 1}
    assert sum(e.turn_start for e in ev) == 1
    assert sum(e.aborted for e in ev) == 1
    assert sum(e.compacted for e in ev) == 1
    assert sum(e.hook_success for e in ev) == 1

def test_second_scan_is_incremental(tmp_path):
    home = _home(tmp_path); st = ScanState(tmp_path / "s.json"); c = ClaudeCodeCollector()
    first = c.scan(home, st); second = c.scan(home, st)
    assert sorted(e.key for e in first) == sorted(e.key for e in second)

def test_not_detected_without_dir(tmp_path):
    assert ClaudeCodeCollector().detect(tmp_path) is False


def test_append_merges_usage_and_calls_after_reload(tmp_path):
    import json

    home = _home(tmp_path)
    log = home / ".claude/projects/-tmp-demo/s1.jsonl"
    state_path = tmp_path / "s.json"
    state = ScanState(state_path)
    collector = ClaudeCodeCollector()
    collector.scan(home, state)
    state.save()
    state = ScanState(state_path)
    row = json.loads(log.read_text().splitlines()[1])
    row["message"]["usage"].update(input_tokens=99, output_tokens=2)
    with log.open("a") as stream:
        stream.write(json.dumps(row) + "\n")
    events = collector.scan(home, state)
    event = next(e for e in events if e.key == "msg_1")
    assert (event.input, event.output) == (10, 50)
    assert event.tool_calls == {"Read": 2, "Edit": 1, "Skill": 1}
    row["message"]["usage"].update(input_tokens=20, output_tokens=80)
    with log.open("a") as stream:
        stream.write(json.dumps(row) + "\n")
    events = collector.scan(home, state)
    event = next(e for e in events if e.key == "msg_1")
    assert (event.input, event.output) == (20, 80)
    assert event.tool_calls == {"Read": 3, "Edit": 1, "Skill": 1}
    assert [e.to_dict() for e in collector.scan(home, state)] == [e.to_dict() for e in events]


def test_subagents_keep_same_id_separate_and_forget_removed_files(tmp_path):
    home = _home(tmp_path)
    log = home / ".claude/projects/-tmp-demo/s1.jsonl"
    subagent = log.parent / "s1/subagents/agent.jsonl"
    subagent.parent.mkdir(parents=True)
    subagent.write_text(log.read_text())
    state = ScanState(tmp_path / "s.json")
    collector = ClaudeCodeCollector()
    assert len(collector.scan(home, state)) == 12
    subagent.unlink()
    log.write_text(log.read_text().splitlines()[0] + "\n")
    events = collector.scan(home, state)
    assert [(e.key, e.turn_start) for e in events] == [("turn:u1", 1)]
    assert state.files(collector.tool) == [str(log)]


def test_fallback_keys_missing_model_and_zero_token_filter(tmp_path):
    import json

    home = _home(tmp_path)
    log = home / ".claude/projects/-tmp-demo/s1.jsonl"
    row = json.loads(log.read_text().splitlines()[1])
    del row["message"]["id"]
    del row["message"]["model"]
    row["effort"] = 1
    rows = [json.dumps(row)]
    del row["requestId"]
    rows.append(json.dumps(row))
    row["uuid"] = "zero"
    row["message"]["usage"].update(input_tokens=0, output_tokens=0)
    rows.append(json.dumps(row))
    row["uuid"] = "synthetic"
    row["message"].update(model="<synthetic>")
    row["message"]["usage"].update(input_tokens=10, output_tokens=5)
    rows.append(json.dumps(row))
    log.write_text("\n".join(rows) + "\n")
    events = ClaudeCodeCollector().scan(home, ScanState(tmp_path / "s.json"))
    assert {e.key for e in events} == {"r1", "a1"}
    assert all(e.model == "unknown" and e.effort is None for e in events)


def test_registered_and_inventory(tmp_path):
    from agentfit.engine.collectors.base import REGISTRY

    assert any(isinstance(c, ClaudeCodeCollector) for c in REGISTRY)
    collector = ClaudeCodeCollector()
    assert (collector.tool, collector.tier) == ("claude_code", "deep")
    assert collector.inventory(tmp_path).to_public() == {
        "skills_installed": 0, "instructions_bytes": 0, "hooks": 0,
        "mcp_servers": 0, "subagents": 0, "plugins": 0,
    }
