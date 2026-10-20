"""总分 = 四维分项加权 (唯一出口) + 模型分档单一口径。

回归: 总分此前直接沿用客户端规则引擎的分数, 与云端四维分项是两套
互不相干的算法 —— 出现过总分 100 / 四维 75·70·95·75 同屏的矛盾。
"""
import pytest
from fastapi.testclient import TestClient

import agentfit.pricing
import cloud.coach
from cloud.analytics import AnalyticsEngine
from cloud.coach import CoachEngine, classify_model, overall_from_dimensions
from cloud.database import DatabaseEngine
from cloud.models import DimensionScore


# ---------------------------------------------------------------------------
# 模型分档: CLI 与云端同一张表
# ---------------------------------------------------------------------------

def test_cloud_uses_the_same_classifier_as_cli():
    assert cloud.coach.classify_model is agentfit.pricing.classify_model


@pytest.mark.parametrize(
    "model, tier",
    [
        # 档位依据 Codex 官方模型描述 (~/.codex/models_cache.json)
        ("gpt-6-astra", "premium"),     # Frontier intelligence
        ("gpt-6.1-sol", "balanced"),    # workhorse
        ("gpt-6-sol", "balanced"),
        ("gpt-5.6-sol", "balanced"),
        ("gpt-5.6-terra", "balanced"),  # balanced model
        ("gpt-6-luna", "fast"),         # Fast and affordable
        ("gpt-5.6-luna", "fast"),
        ("gpt-reserve", "fast"),
        # 原先只在云端表里的关键词, 合并后 CLI 侧也生效
        ("o3-pro", "premium"),
        ("gemini-2.5-flash", "fast"),
    ],
)
def test_gpt6_family_and_merged_keywords(model, tier):
    assert classify_model(model) == tier


# ---------------------------------------------------------------------------
# 总分 = 四维加权
# ---------------------------------------------------------------------------

def _dims(*scores):
    keys = ["routing", "timing", "context", "leverage"]
    return [DimensionScore(key=k, label=k, score=s) for k, s in zip(keys, scores)]


def test_overall_is_weighted_mean_of_dimensions():
    assert overall_from_dimensions(_dims(75, 70, 95, 75)) == 79  # 78.75 → 79
    assert overall_from_dimensions(_dims(100, 100, 100, 100)) == 100


@pytest.fixture
def engine():
    db = DatabaseEngine("sqlite:///:memory:")
    db.init_db()
    return CoachEngine(db), db


def test_report_score_matches_dimensions_not_client_score(engine):
    """Kenichi 2026-10-20 实例: 只用均衡档 + 全天碎片化 → 总分不能是 100。"""
    coach, _ = engine
    report = coach.generate_report(
        total_tokens_7d=1_000_000,
        total_cost_7d=50.0,
        usage_by_model={"gpt-6.1-sol": {"tokens": 1_000_000, "cost": 50.0, "requests": 500}},
        hourly_histogram=[3] * 24,
        cache_hit_rate=0.51,
    )
    assert report.score == overall_from_dimensions(report.dimension_scores)
    assert report.score < 100
    assert report.tier == cloud.coach.tier_for_score(report.score)


# ---------------------------------------------------------------------------
# API: 入库的是云端算出的分数, 排名同口径
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    test_db = DatabaseEngine("sqlite:///:memory:")
    test_db.init_db()
    import cloud.api
    cloud.api.db = test_db
    cloud.api.analytics = AnalyticsEngine(test_db)
    cloud.api.coach = CoachEngine(test_db)
    from cloud.main import app
    return TestClient(app), test_db


def test_analyze_ignores_client_score_and_stores_derived(client):
    c, db = client
    r = c.post("/api/v1/coach/analyze", json={
        "score": 100, "tier": "S",
        "total_tokens_7d": 1_000_000, "total_cost_7d": 50.0,
        "usage_by_model": {"gpt-6.1-sol": {"tokens": 1_000_000, "cost": 50.0, "requests": 500}},
        "hourly_histogram": [3] * 24,
        "device_token": "tok",
    })
    assert r.status_code == 200
    body = r.json()
    assert body["score"] == overall_from_dimensions(
        [DimensionScore(**d) for d in body["dimension_scores"]]
    )
    assert body["score"] < 100
    stored = db.get_latest_submission(device_token="tok")
    assert stored["score"] == body["score"]
    assert stored["tier"] == body["tier"]
