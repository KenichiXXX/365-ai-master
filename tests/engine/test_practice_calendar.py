import json
import os
import time
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone

from agentfit.engine.codex_book import update_book, practice_command
from agentfit.engine.content_pool import load_content
from agentfit.engine.events import CompactEvent
from agentfit.engine.profile import build_profile
from agentfit.engine.snapshot import build_snapshot

NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
CONTENT = load_content(None)
COVERAGE = {"claude_code": {"adapter_version": "1", "format": "claude-jsonl-v1",
    "status": "ok", "signals": {"tool_calls": "available"}}}


@contextmanager
def zone(name):
    old = os.environ.get("TZ")
    os.environ["TZ"] = name
    time.tzset()
    try:
        yield
    finally:
        if old is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = old
        time.tzset()


def event(key, at, capability=False):
    return CompactEvent("claude_code", key, at.isoformat(), "sonnet", input=10,
                        tool_calls={"WebSearch": 1} if capability else {})


def scan(path, now, events=(), coverage=COVERAGE):
    return update_book(CONTENT, build_profile(list(events), now), {}, path, now, events, coverage)


def days(book):
    return {row["date"]: row for row in book["practice_calendar"]["days"]}


def test_calendar_distinguishes_observation_self_report_usage_and_missing(tmp_path):
    path = tmp_path / "progress.json"
    with zone("UTC"):
        scan(path, NOW)
        practice_command("web_search", "start", path, NOW)
        observed = event("observed", NOW + timedelta(seconds=1), True)
        first = scan(path, NOW + timedelta(seconds=2), [observed, observed])
        assert days(first)["2026-10-21"]["state"] == "observed"
        assert len(days(first)) == 30
        second = scan(path, NOW + timedelta(days=1), [observed, event("usage", NOW + timedelta(days=1))])
        assert days(second)["2026-10-22"]["state"] == "usage_only"
        assert days(second)["2026-10-20"]["state"] == "unavailable"
        practice_command("init_cmd", "self", path, NOW + timedelta(days=2))
        third = scan(path, NOW + timedelta(days=2), [observed])
        assert days(third)["2026-10-23"]["state"] == "self_reported"
        assert days(third)["2026-10-21"]["state"] == "observed"
        assert "Rest does not remove earned achievements" in third["practice_calendar"]["labels"].values()


def test_scans_views_and_configuration_never_create_practice_days(tmp_path):
    path = tmp_path / "progress.json"
    with zone("UTC"):
        first = scan(path, NOW, coverage={})
        practice_command(first["today"]["id"], "seen", path, NOW)
        practice_command("web_search", "start", path, NOW)
        second = scan(path, NOW + timedelta(days=1), coverage={})
        assert {r["state"] for r in days(second).values()} == {"unavailable"}


def test_travel_preserves_occurrence_dates_and_new_events_use_new_zone(tmp_path):
    path = tmp_path / "progress.json"
    at = datetime(2026, 10, 21, 15, 1, tzinfo=timezone.utc)
    first_event = event("first", at, True)
    with zone("Asia/Tokyo"):
        scan(path, at - timedelta(minutes=1))
        practice_command("web_search", "start", path, at - timedelta(minutes=1))
        first = scan(path, at, [first_event])
        assert days(first)["2026-10-22"]["state"] == "observed"
    original = json.loads(path.read_text())["practice"]["events"]
    with zone("America/Los_Angeles"):
        # Wait until the originally earned local date is inside the displayed window.
        later = at + timedelta(days=1)
        second = scan(path, later, [first_event, event("later", later)])
        assert days(second)["2026-10-22"]["state"] == "observed"
        saved = json.loads(path.read_text())["practice"]
        assert all(saved["events"][key] == row for key, row in original.items())
        assert saved["attempts"][0]["reuse_dates"] == []


def test_dst_fallback_deduplicates_day_and_reuse_requires_capability(tmp_path):
    path = tmp_path / "progress.json"
    start = datetime(2026, 11, 1, 7, tzinfo=timezone.utc)
    events = [event("before", start + timedelta(hours=1, minutes=30), True),
              event("after", start + timedelta(hours=2, minutes=30), True)]
    with zone("America/Los_Angeles"):
        scan(path, start)
        practice_command("web_search", "start", path, start)
        result = scan(path, start + timedelta(hours=3), events)
        assert sum(row["state"] == "observed" for row in days(result).values()) == 1
        tomorrow = start + timedelta(days=1, hours=4)
        scan(path, tomorrow, events + [event("usage", tomorrow)])
        assert json.loads(path.read_text())["practice"]["attempts"][0]["reuse_dates"] == []
        scan(path, tomorrow + timedelta(seconds=1), [event("reuse", tomorrow + timedelta(seconds=1), True)])
        assert json.loads(path.read_text())["practice"]["attempts"][0]["reuse_dates"] == ["2026-11-02"]


def test_future_and_clock_rollback_do_not_create_activity(tmp_path):
    path = tmp_path / "progress.json"
    future = event("future", NOW + timedelta(days=1))
    with zone("UTC"):
        first = scan(path, NOW, [future])
        assert {r["state"] for r in days(first).values()} == {"unavailable"}
        second = scan(path, future.dt(), [future])
        assert days(second)["2026-10-22"]["state"] == "usage_only"
        rollback = scan(path, NOW, [future])
        assert {r["state"] for r in days(rollback).values()} == {"unavailable"}
        assert days(scan(path, future.dt(), [future]))["2026-10-22"]["state"] == "usage_only"


def test_repeated_self_reports_have_separate_days(tmp_path):
    path = tmp_path / "progress.json"
    with zone("UTC"):
        scan(path, NOW)
        for offset in (0, 0, 1):
            practice_command("init_cmd", "self", path, NOW + timedelta(days=offset))
        result = scan(path, NOW + timedelta(days=1))
        assert days(result)["2026-10-21"]["state"] == "self_reported"
        assert days(result)["2026-10-22"]["state"] == "self_reported"


def test_earned_badges_survive_gaps_rollback_and_legacy_migration(tmp_path):
    state = tmp_path / "state"
    state.mkdir()
    path = state / "progress.json"
    path.write_text(json.dumps({"badges": ["book_all"], "lit": {}, "passed": {}, "regress_notified": []}))
    home = tmp_path / "home"
    log = home / ".claude/projects/synthetic/log.jsonl"
    log.parent.mkdir(parents=True)
    log.write_text("\n".join(json.dumps({"type": "assistant", "timestamp": (NOW - timedelta(days=d)).isoformat(),
        "message": {"id": str(d), "model": "sonnet", "usage": {"input_tokens": 10, "output_tokens": 1}, "content": []}})
        for d in range(3)) + "\n")
    with zone("UTC"):
        first = build_snapshot(home, state, "en", NOW)
        assert first["streak"]["days"] == 3
        assert first["streak"]["label"] == "AI usage: 3 consecutive days"
        for at in (NOW + timedelta(days=5), NOW - timedelta(days=1)):
            result = build_snapshot(home, state, "en", at)
            earned = {b["id"] for b in result["badges"] if b["earned"]}
            assert {"streak_3", "book_all"} <= earned
            assert result["book"]["next_badge"]["id"] not in earned


def test_usage_dates_do_not_move_when_timezone_changes(tmp_path):
    path = tmp_path / "progress.json"
    at = datetime(2026, 10, 21, 16, tzinfo=timezone.utc)
    usage = event("one", at)
    with zone("Asia/Tokyo"):
        first = scan(path, at, [usage])
        assert days(first)["2026-10-22"]["state"] == "usage_only"
    with zone("America/Los_Angeles"):
        second = scan(path, at + timedelta(days=1), [usage])
        assert days(second)["2026-10-22"]["state"] == "usage_only"
        assert days(second)["2026-10-21"]["state"] == "unavailable"
