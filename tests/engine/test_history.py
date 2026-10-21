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
    assert snapshot["overall"]["score"] is None
    assert saved["history"][today.isoformat()]["score"] is None
    assert saved["history"][(today - timedelta(days=1)).isoformat()]["score_version"] == "legacy_unknown_version"
    assert len(snapshot["growth"]["days"]) == 30
    assert snapshot["growth"]["days"][-1]["date"] == today.isoformat()
    assert snapshot["growth"]["days"][-1]["score"] is None
    again = build_snapshot(tmp_path / "empty", state, "en", now=NOW)
    assert again["growth"] == snapshot["growth"]
    assert len(json.loads((state / "progress.json").read_text())["history"]) == 90


def test_legacy_week_is_not_comparable_and_weekly_progress_is_preserved(tmp_path):
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
    delta = None
    assert snapshot["overall"]["score"] is None
    assert snapshot["growth"]["week_delta"] == delta
    assert {key: snapshot["weekly"][key] for key in ("week_start", "score_delta", "cards_lit_this_week",
        "quests_passed_this_week", "days_active")} == {"week_start": "2026-10-19", "score_delta": delta,
        "cards_lit_this_week": ["a"], "quests_passed_this_week": ["first_edit"], "days_active": 0}
    assert snapshot["weekly"]["observed_change"]["text"] == "No new practice change was observed this week"


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


def test_calendar_gaps_versions_nullable_observations_and_matched_weekdays(tmp_path):
    from agentfit.engine.history import record_history, SCORE_VERSION
    path = tmp_path / "progress.json"
    # Wednesday: compare only completed Monday and Tuesday, not today's carried profile.
    for day, score in [(12, 10), (13, 30), (19, 30), (20, 50)]:
        record_history(path, NOW.replace(day=day), score, {}, [], coverage={"codex": {"status": "ok"}})
    growth, weekly = record_history(path, NOW, 99, {}, [])
    assert len(growth["days"]) == 30
    assert growth["week_delta"] == 20
    assert growth["comparison"]["window"] == "matched_completed_weekdays"
    assert growth["days"][-4]["score"] is None
    saved = json.loads(path.read_text())["history"]
    assert saved["2026-10-20"]["score_version"] == SCORE_VERSION
    assert saved["2026-10-20"]["timezone"]
    assert saved["2026-10-20"]["coverage"]["codex"]["status"] == "ok"
    record_history(path, NOW.replace(day=20), None, {}, [])
    growth, _ = record_history(path, NOW, 99, {}, [])
    assert growth["week_delta"] is None and growth["comparison"]["reason"] == "incomplete_window"
    record_history(path, NOW.replace(day=20), 50, {}, [], score_version="other")
    growth, _ = record_history(path, NOW, 99, {}, [])
    assert growth["week_delta"] is None and growth["comparison"]["reason"] == "version_changed"


def test_weekly_evidence_is_sanitized_and_separates_self_report(tmp_path):
    from agentfit.engine.history import record_history
    path = tmp_path / "progress.json"
    path.write_text(json.dumps({"practice": {"events": {
        "abc": {"kind": "log_observed", "local_date": "2026-10-20", "occurred_at": "2026-10-20T00:00:00+00:00", "skill_id": "web_search", "secret": "/private/path"},
        "old": {"kind": "historical", "local_date": "2026-10-20"}},
        "self_reports": {"rules_file": {"local_date": "2026-10-20"}}}}))
    _, weekly = record_history(path, NOW, None, {}, [], locale="en", next_practice="web_search")
    assert weekly["observed_change"]["evidence_ids"] == ["abc"]
    assert weekly["observed_change"]["metric_id"] == "practice.new_observations"
    assert weekly["self_report_ids"] == ["rules_file"]
    assert weekly["next_practice"]["practice_id"] == "web_search"
    assert weekly["uncertainty"]["reason"] == "incomplete_window"
    assert "/private" not in json.dumps(weekly)
    assert "Collecting comparable data" in weekly["report_text"]


def test_configuration_self_report_reuse_and_future_evidence_stay_distinct(tmp_path):
    from agentfit.engine.history import record_history
    path = tmp_path / "progress.json"
    path.write_text(json.dumps({"practice": {"events": {
        "earlier": {"kind": "log_observed", "skill_id": "web_search", "local_date": "2026-10-18", "occurred_at": "2026-10-18T00:00:00+00:00"},
        "reuse": {"kind": "log_observed", "skill_id": "web_search", "local_date": "2026-10-20", "occurred_at": "2026-10-20T00:00:00+00:00"},
        "future": {"kind": "log_observed", "skill_id": "web_search", "local_date": "2026-10-21", "occurred_at": "2026-10-21T23:00:00+00:00"}},
        "configurations": {"rules_file": {"first_seen_at": "2026-10-20T00:00:00+00:00"}},
        "self_reports": {"plan_mode": {"local_date": "2026-10-20"}}}}))
    _, weekly = record_history(path, NOW, None, {}, [])
    assert weekly["configuration_ids"] == ["rules_file"]
    assert weekly["self_report_ids"] == ["plan_mode"]
    assert weekly["observed_change"]["evidence_ids"] == ["reuse"]
    assert weekly["reuse_evidence_ids"] == ["reuse"]


def test_monday_and_incomplete_or_legacy_weeks_never_invent_delta(tmp_path):
    from agentfit.engine.history import record_history
    path = tmp_path / "progress.json"
    for day in [12, 13, 19, 20]:
        record_history(path, NOW.replace(day=day), 60, {}, [])
    growth, _ = record_history(path, NOW.replace(day=19), 60, {}, [])
    assert growth["week_delta"] is None
    assert growth["comparison"]["current_dates"] == []
    # The previous week has complete legacy values but an unidentifiable score version.
    saved = json.loads(path.read_text())
    saved["history"]["2026-10-12"] = {"score": 50, "dims": {}}
    path.write_text(json.dumps(saved))
    record_history(path, NOW.replace(day=20), 60, {}, [])
    growth, weekly = record_history(path, NOW, 60, {}, [])
    assert growth["week_delta"] is None
    assert growth["comparison"]["reason"] == "version_changed"
    assert weekly["observed_change"]["text"] == "No new practice change was observed this week"


def test_invalid_daily_score_is_not_a_valid_comparison_point(tmp_path):
    from agentfit.engine.history import record_history
    path = tmp_path / "progress.json"
    for day in [12, 13, 19, 20]:
        record_history(path, NOW.replace(day=day), 60, {}, [])
    saved = json.loads(path.read_text())
    saved["history"]["2026-10-13"]["score"] = 101
    path.write_text(json.dumps(saved))
    growth, _ = record_history(path, NOW, 60, {}, [])
    assert growth["week_delta"] is None
    assert growth["comparison"]["reason"] == "incomplete_window"
