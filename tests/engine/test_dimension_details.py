"""Task 42: explanatory details preserve the score and numeric evidence."""
import pytest

from agentfit.engine.snapshot import build_snapshot
from tests.engine.test_real_log_scoring import fixture_home, NOW


@pytest.mark.parametrize("locale", ["zh", "en"])
def test_real_shaped_snapshot_explains_all_dimensions(tmp_path, locale):
    home = fixture_home(tmp_path / "home")
    snapshot = build_snapshot(home, tmp_path / "state", locale, NOW)
    for dimension in snapshot["dimensions"]:
        assert dimension["verdict"]
        assert 2 <= len(dimension["evidence"]) <= 4
        assert all(row["label"] and row["value"] for row in dimension["evidence"])
        assert sum(d["points"] for d in dimension["deductions"]) == dimension["base"] - dimension["score"]
        assert dimension["steps"]
        assert dimension["prompt"]
    assert len(snapshot["growth"]["days"]) == 30
    assert snapshot["growth"]["days"][-1]["dims"] == {
        d["key"]: d["score"] for d in snapshot["dimensions"]}


def test_empty_snapshot_never_invents_deductions_or_numeric_evidence(tmp_path):
    snapshot = build_snapshot(tmp_path / "home", tmp_path / "state", "en", NOW)
    for dimension in snapshot["dimensions"]:
        assert dimension["score"] is None
        assert dimension["deductions"] == []
        assert dimension["prompt"] == ""
        assert all(row["value"] == "—" for row in dimension["evidence"])


@pytest.mark.parametrize("locale", ["zh", "en"])
def test_all_penalties_and_concentration_bonus_reconcile(locale):
    from agentfit.engine.profile import Profile, dimensions
    from agentfit.engine.dimension_details import dimension_details
    from agentfit.checkup import compute_checkup

    profile = Profile(now=NOW, usage_tools_7d={"codex"}, usage_tools_14d={"codex"},
        behavior_tools_14d={"codex"}, scoring_usage_7d={"claude-opus-4": {"tokens": 1000, "cost": 1}},
        scoring_weight_7d=1, cache_hit_rate_7d=0, input_tokens_7d=1000,
        turns_14d=100, compactions_14d=20, aborted_14d=20,
        hourly_histogram_7d=[1] * 24)
    details = dimension_details(profile, dimensions(profile, None, locale), locale)
    expected, _ = compute_checkup(profile.rule_hits(), {"model_overuse": True, "fast_gap": True},
        {"fragmented": True}, 0, 0)
    assert [d["score"] for d in details] == [d.score for d in expected]
    assert [sum(item["points"] for item in d["deductions"]) for d in details] == [60, 20, 70, 10]
    for d in details:
        assert sum(item["points"] for item in d["deductions"]) == d["base"] - d["score"]
        assert d["steps"]
    context = next(d for d in details if d["key"] == "context")
    assert context["evidence"][0]["value"] == "20 / 100"
    assert next(d for d in details if d["key"] == "routing")["evidence"][1]["value"] == "0%"
    # A concentrated daytime pattern adds five points rather than a fake deduction.
    profile.hourly_histogram_7d = [0] * 24
    profile.hourly_histogram_7d[12] = 100
    timing = next(d for d in dimension_details(profile, dimensions(profile, None, locale), locale)
                  if d["key"] == "timing")
    assert timing["score"] == timing["base"] == 95
    assert timing["deductions"] == []
    profile.hourly_histogram_7d = [100] + [0] * 23
    timing = next(d for d in dimension_details(profile, dimensions(profile, None, locale), locale)
                  if d["key"] == "timing")
    assert timing["base"] == 95
    assert timing["deductions"][0]["points"] == 25
    assert timing["score"] == 70


def test_unsupported_skill_counts_stay_unknown_and_zero_cost_uses_token_label():
    from agentfit.engine.profile import Profile, dimensions
    from agentfit.engine.dimension_details import dimension_details
    profile = Profile(now=NOW, usage_tools_7d={"gemini_cli"}, usage_tools_14d={"gemini_cli"},
        scoring_usage_7d={"claude-opus-4": {"tokens": 100, "cost": 0}},
        hourly_histogram_7d=[0] * 12 + [1] + [0] * 11)
    coverage = {"gemini_cli": {"signals": {"usage": "observed", "skill_calls": "unsupported"}}}
    details = dimension_details(profile, dimensions(profile, coverage, "en"), "en", coverage)
    routing = next(d for d in details if d["key"] == "routing")
    assert "token" in routing["evidence"][0]["label"].lower()
    leverage = next(d for d in details if d["key"] == "leverage")
    assert leverage["evidence"][-1]["value"] == "—"


@pytest.mark.parametrize("locale", ["zh", "en"])
def test_token_fallback_evidence_does_not_claim_cost_share(locale):
    from agentfit.engine.profile import Profile, dimensions
    from agentfit.engine.dimension_details import dimension_details
    profile = Profile(now=NOW, usage_tools_7d={"codex"}, usage_tools_14d={"codex"},
        scoring_usage_7d={"claude-opus-4": {"tokens": 100, "cost": 0}},
        hourly_histogram_7d=[0] * 12 + [1] + [0] * 11)
    routing = dimension_details(profile, dimensions(profile, None, locale), locale)[0]
    assert "token" in routing["evidence"][0]["label"].lower()
    assert routing["evidence"][0]["value"] == "100%"


def test_observed_skill_calls_are_reported_even_without_a_context_score():
    from agentfit.engine.profile import Profile, dimensions
    from agentfit.engine.dimension_details import dimension_details
    profile = Profile(now=NOW, usage_tools_14d={"claude_code"}, skill_calls_14d={"review": 3})
    coverage = {"claude_code": {"signals": {"skill_calls": "observed"}}}
    details = dimension_details(profile, dimensions(profile, coverage, "en"), "en", coverage)
    leverage = next(d for d in details if d["key"] == "leverage")
    assert leverage["score"] is None
    assert leverage["evidence"][-1]["value"] == "3"
