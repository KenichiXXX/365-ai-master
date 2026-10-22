"""Task 40 regressions use synthetic homes, never the user's logs."""
from datetime import timedelta
import json

import pytest

from agentfit.engine.snapshot import build_snapshot
from tests.engine.test_real_log_scoring import fixture_home, NOW


def ready_home(tmp_path):
    home = fixture_home(tmp_path / "home")
    rules = home / ".claude/CLAUDE.md"
    rules.write_text("# Project rules\n" + "Use focused tests.\n" * 20)
    return home


@pytest.mark.parametrize("locale", ["zh", "en"])
def test_supported_data_replaces_initial_safe_action_with_current_quest(tmp_path, locale):
    home = tmp_path / "home"
    state = tmp_path / "state"
    initial = build_snapshot(home, state, locale, NOW)
    assert initial["today_tip"]["source"] == {"kind": "pool", "ref": "privacy_check"}
    ready_home(tmp_path)
    result = build_snapshot(home, state, locale, NOW)
    assert {"first_edit", "rules_file"} <= {
        q["key"] for q in result["village"]["quests"] if q["status"] == "passed"}
    assert result["village"]["current"] == "light_model"
    assert result["overall"]["score"] is not None
    assert result["today_tip"]["source"] == {"kind": "quest", "ref": "light_model"}
    assert result["today_tip"]["action_id"] != initial["today_tip"]["action_id"]
    assert build_snapshot(home, state, locale, NOW)["today_tip"] == result["today_tip"]


def test_known_tier_usage_has_api_equivalent_cost_and_unknown_stays_partial(tmp_path):
    home = ready_home(tmp_path)
    state = tmp_path / "state"
    result = build_snapshot(home, state, "zh", NOW)
    usage = result["usage_summary"]
    assert usage["cost_usd_7d"] > 0
    assert usage["price_estimate"]["coverage_pct"] == 100
    assert usage["price_estimate"]["unknown_models"] == []
    known_cost = usage["cost_usd_7d"]
    log = home / ".claude/projects/-tmp-demo/s1.jsonl"
    with log.open("a") as stream:
        stream.write(json.dumps({"type": "assistant", "timestamp": NOW.isoformat(),
            "message": {"id": "unknown", "model": "unrecognized-model", "content": [],
                        "usage": {"input_tokens": 100, "output_tokens": 10}}}) + "\n")
    partial = build_snapshot(home, state, "zh", NOW)["usage_summary"]["price_estimate"]
    assert partial["total_usd"] is None
    assert partial["matched_subtotal_usd"] == known_cost
    assert partial["unknown_models"] == ["unrecognized-model"]
    assert 0 < partial["coverage_pct"] < 100


@pytest.mark.parametrize("age,reset_offset,expected", [
    (timedelta(hours=2), timedelta(days=5), "fresh"),
    (timedelta(days=8), timedelta(days=1), "stale"),
    (timedelta(minutes=-1), timedelta(days=5), "future"),
    (timedelta(hours=2), timedelta(seconds=-1), "stale"),
])
def test_weekly_quota_freshness_uses_record_time_and_its_window(tmp_path, age, reset_offset, expected):
    home = ready_home(tmp_path)
    for fixture in (home / ".codex/sessions").rglob("*.jsonl"):
        rows = [json.loads(line) for line in fixture.read_text().splitlines()]
        fixture.write_text("".join(json.dumps(row) + "\n" for row in rows
                                    if "rate_limits" not in row.get("payload", {})))
    log = home / ".codex/sessions/quota.jsonl"
    log.write_text(json.dumps({"timestamp": (NOW - age).isoformat(), "type": "event_msg",
        "payload": {"type": "token_count", "rate_limits": {
            "primary": {"used_percent": 42, "window_minutes": 300,
                        "resets_at": (NOW - timedelta(hours=1)).timestamp()},
            "secondary": {"used_percent": 29, "window_minutes": 10080,
                          "resets_at": (NOW + reset_offset).timestamp()}}}}) + "\n")
    quota = build_snapshot(home, tmp_path / "state", "zh", NOW)["usage_summary"]["codex_quota"]
    assert quota["freshness"] == expected
