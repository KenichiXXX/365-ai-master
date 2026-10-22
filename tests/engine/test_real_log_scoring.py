"""Scoring survives normal metadata and isolated unreadable sources."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil

import pytest

from agentfit.checkup import (DIMENSION_WEIGHTS, analyze_time_habits, compute_checkup,
                             diagnose_model_mix, overall_from_dimensions)
from agentfit.engine.action_rules import EvaluableDimension, overall
from agentfit.engine.collectors.claude_code import ClaudeCodeCollector
from agentfit.engine.collectors.codex import CodexCollector
from agentfit.engine.profile import build_profile
from agentfit.engine.scan_state import ScanState
from agentfit.engine.snapshot import build_snapshot

NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
FIXTURES = Path(__file__).parent / "fixtures"


def fixture_home(home):
    for source, target in (("claude", ".claude"), ("codex", ".codex")):
        shutil.copytree(FIXTURES / source, home / target)
    log = home / ".claude/projects/-tmp-demo/s1.jsonl"
    with log.open("a") as stream:
        stream.write(json.dumps({"type": "progress", "timestamp": NOW.isoformat(),
                                 "data": {"type": "hook_progress"}}) + "\n")
    return home


def test_realistic_mixed_logs_score_and_keep_partial_diagnostics(tmp_path):
    home = fixture_home(tmp_path / "home")
    state = tmp_path / "state"
    snapshot = build_snapshot(home, state, "en", NOW)
    assert snapshot["overall"]["score"] is not None
    assert all(d["score"] is not None for d in snapshot["dimensions"])
    dims = [EvaluableDimension(d["key"], d["label"], d["score"], d["availability"], d["evidence"])
            for d in snapshot["dimensions"]]
    assert snapshot["overall"]["score"] == overall_from_dimensions(dims)
    scan = ScanState(state / "scan.json")
    profile = build_profile(ClaudeCodeCollector().scan(home, scan) + CodexCollector().scan(home, scan), NOW)
    _, saving, mix = diagnose_model_mix(profile.scoring_usage_7d, profile.scoring_weight_7d)
    _, _, timing = analyze_time_habits(profile.hourly_histogram_7d)
    legacy, _ = compute_checkup(profile.rule_hits(), mix, timing, profile.cache_hit_rate_7d, saving)
    assert [d.score for d in dims] == [d.score for d in legacy]
    for tool in ("claude_code", "codex"):
        row = snapshot["coverage"][tool]
        assert row["status"] == "partial"
        assert row["valid_usage_count"] > 0
        assert row["signals"]["usage"] == "observed"
        assert row["signals"]["tool_calls"] == "observed"
    assert snapshot["coverage"]["claude_code"]["signals"]["skill_calls"] == "observed"
    assert snapshot["coverage"]["codex"]["signals"]["aborted"] == "observed"
    assert snapshot == build_snapshot(home, state, "en", NOW)


def test_supported_zero_signals_and_zero_turns_still_score(tmp_path):
    log = tmp_path / ".codex/sessions/usage.jsonl"
    log.parent.mkdir(parents=True)
    log.write_text(json.dumps({"timestamp": NOW.isoformat(), "type": "token_usage_record",
                              "payload": {"response_id": "r", "usage": {
                                  "input_tokens": 100, "output_tokens": 10}}}) + "\n")
    snapshot = build_snapshot(tmp_path, tmp_path / "state", "en", NOW)
    assert snapshot["coverage"]["codex"]["signals"]["usage"] == "observed"
    for signal in ("tool_calls", "turn_start", "aborted", "compacted", "sidechain"):
        assert snapshot["coverage"]["codex"]["signals"][signal] == "supported"
    assert all(d["score"] is not None for d in snapshot["dimensions"])
    expired = build_snapshot(tmp_path, tmp_path / "state", "en", NOW + timedelta(days=31))
    assert expired["overall"]["score"] is None
    assert expired["coverage"]["codex"]["signals"]["usage"] != "observed"


def test_unrelated_denied_source_does_not_erase_known_dimensions(tmp_path, monkeypatch):
    home = fixture_home(tmp_path / "home")
    def denied(*args):
        raise PermissionError("private source")
    monkeypatch.setattr(CodexCollector, "scan", denied)
    snapshot = build_snapshot(home, tmp_path / "state", "en", NOW)
    assert snapshot["coverage"]["codex"]["signals"]["usage"] == "unknown"
    assert snapshot["overall"]["score"] is not None
    assert {d["key"] for d in snapshot["dimensions"] if d["score"] is None} == {"context"}
    assert snapshot["overall"]["availability"] == "partial"


@pytest.mark.parametrize("missing,expected", [
    (set(), 75), ({"context"}, 73), ({"context", "routing"}, 93), (set(DIMENSION_WEIGHTS), None),
])
def test_overall_renormalises_only_available_dimensions(missing, expected):
    dims = [EvaluableDimension(key, key, None if key in missing else score, "unknown" if key in missing else "available", [])
            for key, score in zip(DIMENSION_WEIGHTS, [35, 90, 80, 95])]
    result = overall(dims)
    assert result["score"] == expected
    assert (result["tier"] is not None) == (expected is not None)


@pytest.mark.parametrize("signal_state", ["observed", "supported"])
def test_new_signal_states_remain_usable_for_quests_and_practice(signal_state):
    from agentfit.engine.action_rules import supported_quests
    from agentfit.engine.events import CompactEvent
    from agentfit.engine.practice import qualifying, validation_available
    coverage = {"codex": {"status": "ok", "format": "codex-response-usage-v1", "adapter_version": "1",
                          "signals": {"tool_calls": signal_state}}}
    card = {"validator": "edit", "compatibility": {
        "codex": {"format": "codex-response-usage-v1", "adapter_versions": ["1"]}}}
    event = CompactEvent(tool="codex", key="edit", ts=NOW.isoformat(), model="", tool_calls={"apply_patch": 1})
    assert "first_edit" in supported_quests(coverage, {})
    assert validation_available(card, coverage)
    assert qualifying(card, event, coverage)
