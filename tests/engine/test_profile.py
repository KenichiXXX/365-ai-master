from datetime import datetime, timezone, timedelta
from agentfit.engine.events import CompactEvent
from agentfit.engine.profile import build_profile, dimensions, event_cost

NOW = datetime(2026, 10, 21, 12, 0, tzinfo=timezone.utc)
def ev(**kw):
    base = dict(tool="claude_code", key="k", ts=(NOW - timedelta(hours=1)).isoformat(), model="claude-sonnet-5")
    base.update(kw); return CompactEvent(**base)

def test_dedupe_and_windows():
    events = [
        ev(key="a", input=100, output=10, tool_calls={"Edit": 1}),
        ev(key="a", input=100, output=40, tool_calls={"Read": 1}),          # same message, later line
        ev(key="b", model="claude-haiku-4-5", input=50, output=50, ts=(NOW - timedelta(days=3)).isoformat()),
        ev(key="old", input=999, output=999, ts=(NOW - timedelta(days=20)).isoformat()),
        ev(key="t1", model="", turn_start=1), ev(key="ab", model="", aborted=1),
        ev(key="cx", tool="codex", model="gpt-6.1-sol", input=200, cache_read=800, output=50),
    ]
    p = build_profile(events, NOW)
    assert p.usage_by_model_7d["claude-sonnet-5"] == {"tokens": 140, "cost": round(event_cost(ev(input=100, output=40)), 6), "requests": 1}
    assert p.tool_calls_14d == {"Edit": 1, "Read": 1}
    assert "old" not in str(p.usage_by_model_7d) and p.turns_14d == 1 and p.aborted_14d == 1
    assert p.light_token_share_14d == round(100 / (140 + 100 + 250), 4)
    assert abs(p.cache_hit_rate_7d - 800 / (100 + 50 + 200 + 800)) < 1e-6
    assert set(p.by_tool) == {"claude_code", "codex"}
    assert p.by_tool["codex"]["7d"]["tokens"] == 250

def test_dimensions_four_keys():
    dims = dimensions(build_profile([], NOW))
    assert [d.key for d in dims] == ["routing", "timing", "context", "leverage"]


def test_dedupe_merges_signals_without_mutating_events():
    events = [
        ev(input=10, output=30, cache_read=20, cache_write=40,
           tool_calls={"Edit": 1}, skill_calls={"tdd": 1}, turn_start=2,
           compacted=1, cwd="/project"),
        ev(input=999, output=1, cache_read=999, sidechain=True,
           tool_calls={"Edit": 2}, skill_calls={"tdd": 2}, turn_start=3,
           aborted=1, compacted=2, hook_success=1),
        ev(tool="codex", input=5, output=5),
    ]
    original = [e.to_dict() for e in events]
    p = build_profile(events, NOW)
    assert p.usage_by_model_7d["claude-sonnet-5"]["tokens"] == 50
    assert p.usage_by_model_7d["claude-sonnet-5"]["requests"] == 2
    assert p.tool_calls_14d == {"Edit": 3}
    assert p.skill_calls_14d == {"tdd": 3}
    assert (p.turns_14d, p.aborted_14d, p.compactions_14d, p.hook_success_14d) == (5, 1, 3, 1)
    assert p.sidechain_14d == 1
    assert p.project_dirs_14d == {"/project"}
    assert p.cache_hit_rate_7d == 20 / 35
    assert build_profile(events, NOW) == p
    assert [e.to_dict() for e in events] == original


def test_inclusive_windows_and_usage_only_histogram():
    p = build_profile([
        ev(key="7", input=10, ts=(NOW - timedelta(days=7)).isoformat()),
        ev(key="over7", input=20, ts=(NOW - timedelta(days=7, microseconds=1)).isoformat()),
        ev(key="14", model="claude-haiku-4-5", input=30,
           ts=(NOW - timedelta(days=14)).isoformat(), cwd="/active", tool_calls={"Edit": 1}),
        ev(key="over14", input=1000, ts=(NOW - timedelta(days=14, microseconds=1)).isoformat(),
           cwd="/expired", tool_calls={"Read": 1}),
        ev(key="marker", model="", turn_start=1, sidechain=True),
    ], NOW)
    assert p.usage_by_model_7d["claude-sonnet-5"]["tokens"] == 10
    assert sum(p.hourly_histogram_7d) == 1
    assert p.hourly_histogram_7d[(NOW - timedelta(days=7)).astimezone().hour] == 1
    assert p.light_token_share_14d == 0.5
    assert p.tool_calls_14d == {"Edit": 1}
    assert p.project_dirs_14d == {"/active"}
    assert p.sidechain_14d == 1


def test_today_and_histogram_use_local_timezone(monkeypatch):
    import time

    try:
        with monkeypatch.context() as patch:
            patch.setenv("TZ", "Asia/Tokyo")
            time.tzset()
            now = datetime(2026, 10, 21, 1, tzinfo=timezone.utc)
            p = build_profile([
                ev(key="today", input=10, ts="2026-10-20T16:00:00+00:00"),
                ev(key="yesterday", input=20, ts="2026-10-20T14:00:00+00:00"),
                ev(key="marker", model="", ts="2026-10-20T16:00:00+00:00", turn_start=1),
            ], now)
            assert p.by_tool["claude_code"]["today"]["tokens"] == 10
            assert p.by_tool["claude_code"]["7d"]["tokens"] == 30
            assert p.hourly_histogram_7d[1] == 1
            assert p.hourly_histogram_7d[23] == 1
            assert sum(p.hourly_histogram_7d) == 2
    finally:
        time.tzset()


def test_costs_model_order_and_empty_profile():
    assert event_cost(ev(model="claude-opus-4", input=1_000_000, output=1_000_000,
                         cache_read=1_000_000, cache_write=999_999)) == 91.5
    events = [ev(key="small", input=1, cache_read=1),
              ev(key="large", model="claude-haiku-4-5", input=2, output=3)]
    p = build_profile(events, NOW)
    expected_cost = round(sum(event_cost(e) for e in events), 6)
    assert p.total_cost_7d == expected_cost
    assert p.by_tool["claude_code"]["7d"] == {"tokens": 6, "cost_usd": expected_cost}
    assert p.by_tool["claude_code"]["by_model"] == [
        {"model": "claude-haiku-4-5", "tokens": 5, "cost_usd": 0.000017},
        {"model": "claude-sonnet-5", "tokens": 1, "cost_usd": 0.000003},
    ]
    empty = build_profile([], NOW)
    assert empty.now == NOW
    assert empty.cache_hit_rate_7d is None
    assert empty.light_token_share_14d == 0.0
    assert empty.total_cost_7d == 0.0
    assert empty.by_tool == {} and empty.usage_by_model_7d == {}
    assert empty.hourly_histogram_7d == [0] * 24


def test_rule_thresholds_and_scoring_integration():
    from agentfit.checkup import analyze_time_habits, compute_checkup, diagnose_model_mix

    for turns, aborted, compacted, retry, bloat in [
        (9, 1, 2, False, False), (10, 1, 3, True, True), (11, 1, 0, False, False),
    ]:
        p = build_profile([ev(turn_start=turns, aborted=aborted, compacted=compacted,
                              input=100, output=20, model="claude-opus-4")], NOW)
        assert p.rule_hits() == {"RULE_CONTEXT_BLOAT": bloat, "RULE_ERROR_RETRY_LOOP": retry}
        _, saving, mix_flags = diagnose_model_mix(p.usage_by_model_7d, p.total_cost_7d)
        _, _, time_flags = analyze_time_habits(p.hourly_histogram_7d)
        expected, _ = compute_checkup(p.rule_hits(), mix_flags, time_flags, p.cache_hit_rate_7d, saving)
        assert dimensions(p) == expected
