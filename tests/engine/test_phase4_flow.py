"""Synthetic Phase 4 acceptance: clocks and homes never use personal logs."""
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path

import pytest

from agentfit.engine.codex_book import practice_command
from agentfit.engine.local_metrics import LocalMetrics
from agentfit.engine.snapshot import build_snapshot

ROOT = Path(__file__).resolve().parents[2]
NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
SENTINELS = ("private-prompt-p4", "/private/project-p4", "private-argument-p4", "private-token-p4")


def append_event(home, key, at, tool="WebSearch"):
    path = home / ".claude/projects/synthetic/session.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    row = {"type": "assistant", "timestamp": at.isoformat(), "cwd": SENTINELS[1],
           "message": {"id": key, "model": "claude-sonnet-5",
                       "usage": {"input_tokens": 10, "output_tokens": 2},
                       "content": [{"type": "text", "text": SENTINELS[0]},
                                   {"type": "tool_use", "id": key, "name": tool,
                                    "input": {"query": SENTINELS[2], "token": SENTINELS[3]}}]}}
    with path.open("a") as stream:
        stream.write(json.dumps(row) + "\n")


def card(snapshot):
    return next(c for c in snapshot["book"]["cards"] if c["id"] == "web_search")


@pytest.mark.parametrize("locale", ["zh", "en"])
def test_local_loop_replay_and_expired_entitlement_metrics(tmp_path, locale):
    home, state = tmp_path / "home", tmp_path / "state"
    append_event(home, "old", NOW - timedelta(seconds=1))
    source_before = (home / ".claude/projects/synthetic/session.jsonl").read_bytes()
    first = build_snapshot(home, state, locale, NOW, enabled=set())
    assert first["coverage"] == {} and first["tools"] == []
    assert first["first_practice"]["prompt"]
    assert first["local_validation"]["funnel"]["observed"] == 0
    progress = state / "progress.json"
    assert practice_command("web_search", "copy", progress, NOW)
    # Enabling the explicitly chosen source and late-importing old usage cannot validate practice.
    chosen = build_snapshot(home, state, locale, NOW, enabled={"claude_code"})
    assert card(chosen)["evidence_kind"] == "started"
    assert chosen["local_validation"]["funnel"]["observed"] == 0
    assert (home / ".claude/projects/synthetic/session.jsonl").read_bytes() == source_before
    append_event(home, "new", NOW + timedelta(seconds=1))
    observed = build_snapshot(home, state, locale, NOW + timedelta(seconds=2), enabled={"claude_code"})
    assert card(observed)["evidence_kind"] == "log_observed"
    assert observed["local_validation"]["observation_rate"] == {"numerator": 1, "denominator": 1}
    tomorrow = NOW + timedelta(days=1)
    # A later scan or a usage-only event is not different-date capability reuse.
    append_event(home, "usage-only", tomorrow, tool="Read")
    assert card(build_snapshot(home, state, locale, tomorrow))["evidence_kind"] == "log_observed"
    append_event(home, "reuse", tomorrow + timedelta(seconds=1))
    metrics = LocalMetrics(state, tomorrow)
    for _ in range(2):
        metrics.record("foreground_open", tomorrow)
        metrics.record("trial_start", tomorrow)
        metrics.record("checkout_return", tomorrow)
        metrics.record("activation", tomorrow, "imported_verified")
        metrics.record("renewal", tomorrow, "unavailable")
    end = tomorrow + timedelta(seconds=2)
    result = build_snapshot(home, state, locale, end)
    assert card(result)["evidence_kind"] == "reuse"
    assert result["local_validation"]["d1"] == {"status": "observed", "denominator": 1, "foreground": 1, "practice": 1}
    assert result["local_validation"]["trial_starts"] == 1
    assert result["local_validation"]["paid_purchases"] is None
    assert len(result["weekly"]["reuse_evidence_ids"]) == 1
    before = json.loads(progress.read_text())
    for _ in range(2):
        repeated = build_snapshot(home, state, locale, end)
        assert repeated == result
        assert json.loads(progress.read_text()) == before
    assert len(before["practice"]["attempts"]) == 1
    assert len(before["practice"]["attempts"][0]["reuse_dates"]) == 1
    # An expired entitlement is only an enum event to the offline engine; no proof or paid claim.
    metrics = LocalMetrics(state, end + timedelta(days=15))
    metrics.record("renewal", end + timedelta(days=15), "expired")
    expired = build_snapshot(home, state, locale, end + timedelta(days=15))
    assert card(expired)["evidence_kind"] == "reuse"
    assert expired["local_validation"]["trial_starts"] == 1
    assert expired["local_validation"]["renewal_status"] == "expired"
    assert expired["local_validation"]["paid_purchases"] is None
    for export in (result, repeated, expired, before["practice"]):
        raw = json.dumps(export)
        assert str(home) not in raw
        for sentinel in SENTINELS:
            assert sentinel not in raw


def test_weekly_review_replay_respects_gaps_and_versions(tmp_path):
    from agentfit.engine.history import record_history
    path = tmp_path / "progress.json"
    for day, score in [(12, 10), (13, 30), (19, 30), (20, 50)]:
        record_history(path, NOW.replace(day=day), score, {}, [])
    for _ in range(2):
        growth, weekly = record_history(path, NOW, None, {}, [])
        assert growth["week_delta"] == weekly["score_delta"] == 20
    saved = json.loads(path.read_text())
    saved["history"].pop("2026-10-13")
    path.write_text(json.dumps(saved))
    assert record_history(path, NOW, None, {}, [])[1]["uncertainty"]["reason"] == "incomplete_window"
    record_history(path, NOW.replace(day=13), 30, {}, [], score_version="synthetic-previous")
    # Historical-date writes prune future rows; recreate completed current weekdays explicitly.
    for day in (19, 20):
        record_history(path, NOW.replace(day=day), 50, {}, [])
    for _ in range(2):
        growth, weekly = record_history(path, NOW, None, {}, [])
        assert growth["week_delta"] is None
        assert weekly["uncertainty"]["reason"] == "version_changed"


def test_release_report_keeps_real_world_gates_explicit():
    report = (ROOT / "docs/testing/phase4-acceptance.md").read_text()
    for status in ("已验证 / Verified", "未运行 / Not run", "未验证 / Unverified", "受阻 / Blocked"):
        assert status in report
    for gate in ("Waffo", "notarization", "VoiceOver", "UI-open", "receipt recovery", "public-source"):
        assert gate in report
    assert "Payment integration is not verified. Checkout is unavailable" in report
