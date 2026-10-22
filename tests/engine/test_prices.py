"""Synthetic prices exercise arithmetic, never assert real market prices."""
from datetime import datetime, timezone
from copy import deepcopy
import pytest
from agentfit.engine.events import CompactEvent
from agentfit.engine.prices import estimate, validate_prices
from agentfit.engine.profile import build_profile

TABLE = {"version": "synthetic-v1", "reviewed_at": "2026-10-21", "currency": "USD",
         "unit": "per_million_tokens", "models": [
    {"model": "synthetic", "source_url": "https://example.com/pricing", "source_date": "2026-10-20",
     "conditions": {"tool": "codex"}, "input": 2, "output": 8, "cache_read": 1, "cache_write": None}]}
NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
def event(**kw):
    return CompactEvent(**({"tool": "codex", "key": "a", "ts": NOW.isoformat(),
                            "model": "synthetic", "input": 100, "output": 50,
                            "cache_read": 40, "cache_write": 10} | kw))

def test_partial_coverage_unknown_cache_write_and_unknown_model():
    result = estimate([event(), event(key="b", model="unknown", input=100, output=0, cache_read=0, cache_write=0)], TABLE)
    assert result["matched_subtotal_usd"] == pytest.approx(.00064)
    assert result["total_usd"] is None
    assert result["matched_tokens"] == 190 and result["unknown_tokens"] == 110
    assert result["coverage_pct"] == pytest.approx(190 / 300 * 100)
    assert result["unknown_models"] == ["synthetic", "unknown"]
    assert result["token_categories"] == {"input": 200, "output": 50, "cache_read": 40, "cache_write": 10}

def test_unknown_condition_no_price_and_zero_denominator():
    assert estimate([event(tool="claude_code")], TABLE)["matched_tokens"] == 0
    assert estimate([event()], None)["total_usd"] is None
    empty = estimate([], TABLE)
    assert empty["coverage_pct"] is None and empty["total_usd"] is None
    table = deepcopy(TABLE); table["models"][0]["cache_write"] = 4
    assert estimate([event()], table)["total_usd"] == pytest.approx(.00068)

def test_price_metadata_validation_and_unsupported_conditions():
    assert validate_prices(TABLE)
    for field, value in [("input", -1), ("output", float("nan")), ("source_url", "file:///private"),
                         ("source_date", "bad"), ("conditions", {"batch": True})]:
        table = deepcopy(TABLE); table["models"][0][field] = value
        assert not validate_prices(table)
    assert estimate([event()], {**TABLE, "currency": "JPY"})["matched_tokens"] == 0

def test_profile_separates_categories_and_unknown_models_remain_unpriced():
    p = build_profile([event(), event()], NOW, prices=TABLE)
    assert p.price_estimate["matched_tokens"] == 190  # deduplicated
    assert p.by_tool["codex"]["7d"]["tokens"] == 150
    assert p.by_tool["codex"]["7d"]["cost_usd"] is None
    assert build_profile([event(model="unreviewed")], NOW).price_estimate["matched_tokens"] == 0


def test_reviewed_prices_cannot_change_frozen_score_arithmetic():
    from agentfit.engine.profile import dimensions
    events = [event(model="claude-opus-4", tool="codex", input=1_000_000),
              event(key="b", model="claude-haiku-4-5", input=500_000)]
    table = deepcopy(TABLE)
    table["models"][0].update(model="claude-opus-4", input=10000, cache_write=0)
    unknown = build_profile(events, NOW)
    known = build_profile(events, NOW, prices=table)
    assert unknown.price_estimate != known.price_estimate
    assert [d.score for d in dimensions(unknown)] == [d.score for d in dimensions(known)]
    assert unknown.scoring_weight_7d == known.scoring_weight_7d


def test_content_rejects_invalid_price_override_and_accepts_absent_section(tmp_path):
    import json
    from agentfit.engine.content_pool import load_content, validate
    pool = load_content(None)
    pool.pop("prices")
    assert validate(pool)
    pool["prices"] = {**TABLE, "unit": "per_token"}
    assert not validate(pool)
    path = tmp_path / "content.json"
    path.write_text(json.dumps(pool))
    assert load_content(path)["prices"]["models"] == []


@pytest.mark.parametrize("tool,model,rates", [
    ("claude_code", "claude-opus-5", (15, 75, 1.5)),
    ("claude_code", "claude-sonnet-5", (3, 15, .3)),
    ("claude_code", "claude-haiku-4-5", (1, 5, .1)),
    ("codex", "gpt-6-astra", (15, 75, 1.5)),
    ("codex", "gpt-6.1-sol", (3, 15, .3)),
    ("codex", "gpt-6-terra", (3, 15, .3)),
    ("codex", "gpt-6-luna", (1, 5, .1)),
])
def test_known_family_tier_estimate_keeps_all_token_categories(tool, model, rates):
    result = estimate([event(tool=tool, model=model)])
    p_in, p_out, p_cache = rates
    assert result["total_usd"] == pytest.approx((110 * p_in + 50 * p_out + 40 * p_cache) / 1e6)
    assert result["coverage_pct"] == 100
    assert result["tier_estimated_tokens"] == 200
    assert result["price_version"].endswith("+tier-v1")


def test_reviewed_known_model_row_takes_precedence_without_filling_missing_categories():
    table = deepcopy(TABLE)
    table["models"][0]["model"] = "gpt-6.1-sol"
    result = estimate([event(model="gpt-6.1-sol")], table)
    assert result["matched_subtotal_usd"] == pytest.approx(.00064)
    assert result["unknown_tokens"] == 10
    assert result["total_usd"] is None
    assert result["tier_estimated_tokens"] == 0
    assert result["price_version"] == "synthetic-v1"


@pytest.mark.parametrize("model", ["", "unknown", "unreviewed", "gpt-6-mystery", "my-custom-balanced"])
def test_arbitrary_scoring_default_is_not_evidence_of_a_known_price(model):
    result = estimate([event(model=model)])
    assert result["total_usd"] is None
    assert result["matched_tokens"] == 0
    assert result["unknown_tokens"] == 200
