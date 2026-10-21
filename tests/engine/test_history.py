import json
from datetime import datetime, timedelta, timezone

from agentfit.engine.snapshot import build_snapshot


NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)


def test_history_overwrites_today_retains_90_days_and_exposes_last_30(tmp_path):
    state = tmp_path / "state"
    state.mkdir()
    today = NOW.astimezone().date()
    history = {(today - timedelta(days=n)).isoformat(): {"score": n % 101, "dims": {}}
               for n in range(100)}
    (state / "progress.json").write_text(json.dumps({"passed": {}, "regress_notified": [], "history": history}))
    snapshot = build_snapshot(tmp_path / "empty", state, "en", now=NOW)
    saved = json.loads((state / "progress.json").read_text())
    assert len(saved["history"]) == 90
    assert min(saved["history"]) == (today - timedelta(days=89)).isoformat()
    assert saved["history"][today.isoformat()] == {
        "score": snapshot["overall"]["score"],
        "dims": {d["key"]: d["score"] for d in snapshot["dimensions"]},
    }
    assert len(snapshot["growth"]["days"]) == 30
    assert snapshot["growth"]["days"][-1] == {"date": today.isoformat(), "score": snapshot["overall"]["score"]}
    again = build_snapshot(tmp_path / "empty", state, "en", now=NOW)
    assert again["growth"] == snapshot["growth"]
    assert len(json.loads((state / "progress.json").read_text())["history"]) == 90


def test_week_delta_uses_previous_calendar_week_latest_and_weekly_progress(tmp_path):
    state = tmp_path / "state"
    state.mkdir()
    (state / "progress.json").write_text(json.dumps({
        "passed": {"first_edit": "2026-10-19T08:00:00+09:00", "rules_file": "2026-10-18T08:00:00+09:00"},
        "regress_notified": [],
        "lit": {"a": {"at": "2026-10-20T09:00:00+09:00", "how": "self"},
                "b": {"at": "2026-10-18T09:00:00+09:00", "how": "self"}},
        "history": {"2026-10-12": {"score": 30, "dims": {}},
                    "2026-10-18": {"score": 60, "dims": {}}},
    }))
    snapshot = build_snapshot(tmp_path / "empty", state, "en", now=NOW)
    delta = snapshot["overall"]["score"] - 60
    assert snapshot["growth"]["week_delta"] == delta
    assert snapshot["weekly"] == {"week_start": "2026-10-19", "score_delta": delta,
        "cards_lit_this_week": ["a"], "quests_passed_this_week": ["first_edit"], "days_active": 0}


def test_first_week_has_no_delta_and_days_active_comes_from_logs(tmp_path):
    from tests.engine.test_snapshot import _home, NOW as FIXTURE_NOW
    snapshot = build_snapshot(_home(tmp_path), tmp_path / "state", "zh", now=FIXTURE_NOW)
    assert snapshot["growth"]["week_delta"] is None
    assert snapshot["weekly"]["score_delta"] is None
    assert snapshot["weekly"]["days_active"] == 1
    assert snapshot["weekly"]["week_start"] == "2026-10-19"


def test_snapshot_supplies_top_20_while_daily_rankings_default_stays_five(tmp_path):
    from agentfit.engine.content_pool import load_content
    pool = load_content(None)
    for kind in ("skill", "agent"):
        item = pool["rankings"][kind][0]
        pool["rankings"][kind] = [{**item, "name": f"{kind}-{n}"} for n in range(25)]
    content = tmp_path / "content.json"
    content.write_text(json.dumps(pool))
    snapshot = build_snapshot(tmp_path / "empty", tmp_path / "state", "en", now=NOW, content=content)
    assert len(snapshot["rankings"]["skill"]) == 20
    assert len(snapshot["rankings"]["agent"]) == 20
