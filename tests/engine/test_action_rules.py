from datetime import datetime, timedelta, timezone
import json
import subprocess
import sys

import pytest

from agentfit.engine.events import CompactEvent
from agentfit.engine.profile import build_profile
from agentfit.engine.snapshot import build_snapshot
from agentfit.engine.village import evaluate

NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)


def profile(**kw):
    return build_profile([CompactEvent(tool="codex", key="a", ts=NOW.isoformat(),
        model="gpt-6.1-sol", input=100, output=20, cache_read=400,
        turn_start=20, **kw)], NOW)


def covered():
    return {"codex": {"status": "ok", "signals": dict.fromkeys(
        ["usage", "turn_start", "aborted", "compacted", "tool_calls", "sidechain"], "available")}}


def test_empty_scores_are_unknown_and_cannot_graduate(tmp_path):
    s = build_snapshot(tmp_path / "empty", tmp_path / "state", "en", now=NOW)
    assert all(d["score"] is None for d in s["dimensions"])
    assert s["overall"] == {"score": None, "tier": None, "availability": "unavailable", "score_version": "1"}
    assert len(s["growth"]["days"]) == 30
    assert all(d["score"] is None for d in s["growth"]["days"])
    assert not evaluate(build_profile([], NOW), {}, [])["graduate"][0]


def test_rules_explain_actual_denominators_and_preserve_legacy_arithmetic():
    from agentfit.engine.action_rules import evaluate_dimensions, overall
    from agentfit.checkup import compute_checkup, diagnose_model_mix, analyze_time_habits, overall_from_dimensions
    p = profile(compacted=3, aborted=2)
    dims = evaluate_dimensions(p, covered(), "en")
    _, saving, mix = diagnose_model_mix(p.scoring_usage_7d, p.scoring_weight_7d)
    _, _, time = analyze_time_habits(p.hourly_histogram_7d)
    legacy, _ = compute_checkup(p.rule_hits(), mix, time, p.cache_hit_rate_7d, saving)
    assert [d.score for d in dims] == [d.score for d in legacy]
    assert overall(dims)["score"] == overall_from_dimensions(legacy)
    rules = {r["rule_id"]: r for d in dims for r in d.evidence}
    for r in rules.values():
        assert r["version"] == "1" and r["required_signals"]
        assert r["missing_policy"] == "unknown" and r["explanation"] and r["limitation"]
        assert r["start_utc"] and r["end_utc"] and r["thresholds"]
    assert rules["context_bloat"]["numerator"] == 3
    assert rules["context_bloat"]["denominator"] == 20
    assert rules["context_bloat"]["window_days"] == 14
    assert rules["cache"]["numerator"] == 400
    assert rules["cache"]["denominator"] == 500
    assert rules["fast_gap"]["denominator"] == 120
    assert rules["late_night"]["denominator"] == 1


def test_partial_reweights_known_dimensions_without_inventing_unknown_inputs():
    from agentfit.engine.action_rules import evaluate_dimensions, overall
    cov = covered()
    cov["codex"]["signals"]["aborted"] = "unsupported"
    dims = evaluate_dimensions(profile(), cov, "zh")
    assert next(d for d in dims if d.key == "context").score is None
    assert overall(dims)["score"] == 85
    assert overall(dims)["tier"] is not None
    assert overall(dims)["availability"] == "partial"
    cov["codex"]["signals"] = dict.fromkeys(cov["codex"]["signals"], "unknown")
    assert all(d.score is None for d in evaluate_dimensions(profile(), cov, "en"))


def assign(path, day=NOW.date(), current="first_edit", supported=None, dims=None):
    from agentfit.engine.action_rules import assign_action
    return assign_action({"passed": {}, "current": current}, dims or [], "en", day,
        path, {"first_edit"} if supported is None else supported)


def test_assignment_stays_stable_across_days_and_coverage_changes(tmp_path):
    path = tmp_path / "progress.json"
    a = assign(path)
    assert a["source"] == {"kind": "quest", "ref": "first_edit"}
    assert a["action_id"] and a["rule_id"] and a["evidence_summary"] and a["limitation"]
    assert a["validation_kind"] == "structured_observation"
    assert assign(path, NOW.date() + timedelta(days=2), supported=set()) == a
    assert json.loads(path.read_text())["main_action"]["assignment"]["action_id"] == a["action_id"]


@pytest.mark.parametrize("feedback,days", [("later", 1), ("not_suitable", 7)])
def test_feedback_intervals_and_persistence(tmp_path, feedback, days):
    from agentfit.engine.action_rules import action_feedback
    path = tmp_path / "progress.json"
    a = assign(path)
    assert action_feedback(path, a["action_id"], feedback, "not_now", NOW.date())
    alternative = assign(path)
    assert alternative["source"]["kind"] == "pool"
    assert alternative["action_id"] != a["action_id"]
    assert not action_feedback(path, a["action_id"], "never", None, NOW.date())
    assert assign(path, NOW.date() + timedelta(days=days-1))["action_id"] == alternative["action_id"]
    assert action_feedback(path, alternative["action_id"], "completed", None, NOW.date() + timedelta(days=days))
    assert assign(path, NOW.date() + timedelta(days=days))["source"] == a["source"]
    assert json.loads(path.read_text())["main_action"]["feedback"][0]["reason"] == "not_now"


def test_never_reset_and_unknown_falls_back_to_safe_practice(tmp_path):
    from agentfit.engine.action_rules import action_feedback, reset_preferences
    path = tmp_path / "progress.json"
    a = assign(path)
    action_feedback(path, a["action_id"], "never", "unsupported_tool", NOW.date())
    b = assign(path, NOW.date() + timedelta(days=100))
    assert b["source"]["kind"] == "pool"
    reset_preferences(path)
    assert assign(path)["rule_id"] == a["rule_id"]
    assert assign(tmp_path / "other.json", supported=set())["source"]["kind"] == "pool"


def test_weakest_evaluable_dimension_before_safe_practice(tmp_path):
    from agentfit.engine.action_rules import evaluate_dimensions
    dims = evaluate_dimensions(profile(), covered(), "en")
    action = assign(tmp_path / "p.json", current=None, supported=set(), dims=dims)
    assert action["source"] == {"kind": "dimension", "ref": "routing"}


def test_cli_feedback_rejects_free_text_and_preserves_other_progress(tmp_path):
    path = tmp_path / "progress.json"
    path.write_text(json.dumps({"passed": {"first_edit": "old"}, "history": {"old": 1}}))
    a = assign(path)
    cmd = [sys.executable, "-m", "agentfit.engine", "action-feedback", a["action_id"],
           "later", "--reason", "not_now", "--state-dir", str(tmp_path)]
    out = subprocess.run(cmd, capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert json.loads(out.stdout) == {"ok": True}
    saved = path.read_text()
    assert json.loads(saved)["history"] == {"old": 1}
    out = subprocess.run(cmd[:5] + ["private free text"] + cmd[6:], capture_output=True, text=True)
    assert out.returncode != 0
    assert path.read_text() == saved


@pytest.mark.parametrize("kind", ["empty", "partial", "evaluable"])
def test_snapshot_score_states_history_and_privacy(tmp_path, kind):
    home = tmp_path / "home"
    if kind != "empty":
        tool = ".claude/projects/demo" if kind == "partial" else ".codex/sessions"
        log = home / tool / "a.jsonl"
        log.parent.mkdir(parents=True)
        if kind == "partial":
            rows = [{"type": "user", "uuid": "u1", "timestamp": NOW.isoformat(),
                     "message": {"content": "private sentinel"}},
                    {"type": "assistant", "timestamp": NOW.isoformat(), "cwd": "/private/sentinel",
                     "message": {"id": "a1", "model": "claude-sonnet-5", "content": [],
                                 "usage": {"input_tokens": 100, "output_tokens": 20, "cache_read_input_tokens": 400}}}]
        else:
            rows = [{"type": "turn_context", "timestamp": NOW.isoformat(), "payload": {"model": "gpt-6.1-sol"}},
                    {"type": "event_msg", "timestamp": NOW.isoformat(), "payload": {"type": "task_started"}},
                    {"type": "token_usage_record", "timestamp": NOW.isoformat(), "payload": {
                        "response_id": "r1", "turn_id": "t1", "usage": {
                            "input_tokens": 500, "cached_input_tokens": 400, "output_tokens": 20}}}]
        log.write_text("".join(json.dumps(row) + "\n" for row in rows))
    state = tmp_path / "state"
    snapshot = build_snapshot(home, state, "en", now=NOW)
    assert snapshot["overall"]["availability"] == {"empty": "unavailable", "partial": "partial", "evaluable": "available"}[kind]
    assert len(snapshot["growth"]["days"]) == 30
    assert sum(d["score"] is not None for d in snapshot["growth"]["days"]) == (0 if kind == "empty" else 1)
    raw = json.dumps(snapshot)
    for sentinel in ("private sentinel", "/private/sentinel", str(tmp_path)):
        assert sentinel not in raw
    repeated = build_snapshot(home, state, "en", now=NOW + timedelta(hours=1))
    assert repeated["today_tip"]["action_id"] == snapshot["today_tip"]["action_id"]
    later = build_snapshot(home, state, "en", now=NOW + timedelta(days=31))
    assert later["overall"]["score"] is None
    history = json.loads((state / "progress.json").read_text())["history"]
    assert len(history) == 2
    assert history[NOW.astimezone().date().isoformat()]["score"] == snapshot["overall"]["score"]
    assert history[(NOW + timedelta(days=31)).astimezone().date().isoformat()]["score"] is None



def test_quest_completion_reassigns_but_feedback_never_unlocks(tmp_path):
    from agentfit.engine.action_rules import assign_action, action_feedback
    path = tmp_path / "progress.json"
    a = assign(path)
    next_action = assign_action({"passed": {"first_edit": NOW.isoformat()}, "current": "rules_file"},
                               [], "en", NOW.date(), path, {"rules_file"})
    assert next_action["rule_id"] == "quest:rules_file"
    assert next_action["action_id"] != a["action_id"]
    assert action_feedback(path, next_action["action_id"], "completed", None, NOW.date())
    assert json.loads(path.read_text())["passed"] == {}


def test_bad_feedback_never_persists_private_input_and_reset_cli(tmp_path):
    from agentfit.engine.action_rules import action_feedback
    path = tmp_path / "progress.json"
    a = assign(path)
    saved = path.read_text()
    assert not action_feedback(path, a["action_id"], "not_suitable", "/private/text", NOW.date())
    assert path.read_text() == saved
    command = [sys.executable, "-m", "agentfit.engine", "reset-action-preferences", "--state-dir", str(tmp_path)]
    assert json.loads(subprocess.run(command, capture_output=True, text=True, check=True).stdout) == {"ok": True}
    assert json.loads(path.read_text())["main_action"]["assignment"] is None


def test_known_weakest_dimension_is_offered_even_above_85(tmp_path):
    from agentfit.engine.action_rules import evaluate_dimensions
    dims = evaluate_dimensions(profile(), covered(), "en")
    for d in dims:
        d.score = 91 if d.key == "routing" else 90
    action = assign(tmp_path / "p.json", current=None, supported=set(), dims=dims)
    assert action["source"] == {"kind": "dimension", "ref": "timing"}


def test_one_unsupported_source_does_not_veto_observed_source_inputs():
    from agentfit.engine.action_rules import evaluate_dimensions
    marker = CompactEvent(tool="claude_code", key="turn", ts=NOW.isoformat(), model="", turn_start=1)
    usage = CompactEvent(tool="codex", key="usage", ts=NOW.isoformat(), model="gpt-6.1-sol",
                         input=100, output=20, cache_read=400, turn_start=20)
    p = build_profile([usage, marker], NOW)
    coverage = covered()
    coverage["claude_code"] = {"status": "ok", "signals": {
        "usage": "available", "turn_start": "available", "compacted": "available", "aborted": "unsupported"}}
    dims = evaluate_dimensions(p, coverage, "en")
    assert next(d for d in dims if d.key == "context").score == 95
    assert next(d for d in dims if d.key == "routing").score is not None


def test_unsuitable_action_offers_safe_practice_even_when_scores_are_known(tmp_path):
    from agentfit.engine.action_rules import action_feedback, evaluate_dimensions
    path = tmp_path / "progress.json"
    dims = evaluate_dimensions(profile(), covered(), "en")
    a = assign(path, dims=dims)
    assert action_feedback(path, a["action_id"], "not_suitable", "no_project", NOW.date())
    b = assign(path, dims=dims)
    assert b["source"]["kind"] == "pool"
    assert b["validation_kind"] == "self_report"
