"""One-installation diagnostics never promote clicks into practice or payment."""
from datetime import datetime, timedelta, timezone
import json

import pytest

from agentfit.engine.local_metrics import LocalMetrics
from agentfit.engine.practice import PracticeLedger
from agentfit.engine.content_pool import load_content
from agentfit.engine.events import CompactEvent

NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
CARD = next(c for c in load_content(None)["skills"] if c["id"] == "web_search")
COVERAGE = {"claude_code": {"format": "claude-jsonl-v1", "adapter_version": "1", "status": "ok",
                            "signals": {"tool_calls": "available"}}}


def test_new_install_and_foreground_are_explicit_and_idempotent(tmp_path):
    metrics = LocalMetrics(tmp_path, NOW)
    metrics.record("foreground_open", NOW)
    metrics.record("foreground_open", NOW)
    metrics.record("share_copy", NOW)
    metrics.record("checkout_return", NOW)
    result = metrics.summary({}, {}, NOW)
    assert result["cohort"] == "new_installation"
    assert result["installation_date"] == NOW.astimezone().date().isoformat()
    assert result["counts"]["foreground_open"] == 1
    assert result["funnel"] == {"attempts": 0, "observed": 0, "self_reported": 0, "reused": 0}
    assert result["paid_purchases"] is None
    assert result["d1"]["status"] == "not_yet"
    assert result["d7"]["denominator"] == 0
    metrics = LocalMetrics(tmp_path, NOW)
    assert metrics.summary({}, {}, NOW)["counts"]["first_launch"] == 1


def test_existing_installation_has_measurement_cohort_not_invented_install(tmp_path):
    (tmp_path / "progress.json").write_text("{}")
    metrics = LocalMetrics(tmp_path, NOW)
    result = metrics.summary({}, {}, NOW + timedelta(days=7))
    assert result["cohort"] == "post_upgrade"
    assert result["installation_date"] is None
    assert result["d1"]["status"] == "unknown_installation"
    assert result["d7"]["denominator"] == 0
    assert result["measurement_start"] == NOW.isoformat()


def test_practice_denominators_new_observation_reuse_and_return(tmp_path):
    metrics = LocalMetrics(tmp_path, NOW)
    progress = {}
    ledger = PracticeLedger(progress, NOW)
    ledger.start(CARD, "one", NOW)
    ledger.start({**CARD, "id": "unsupported"}, "two", NOW)
    def event(key, at):
        return CompactEvent(tool="claude_code", key=key, ts=at.isoformat(), model="m", tool_calls={"WebSearch": 1})
    ledger.observe([event("new", NOW + timedelta(seconds=1))], [CARD], COVERAGE, NOW + timedelta(seconds=2))
    # The second attempt owns the observation; evidence still has one denominator per attempt.
    day1 = NOW + timedelta(days=1)
    metrics.record("foreground_open", day1)
    ledger.observe([event("reuse", day1)], [CARD], COVERAGE, day1)
    day7 = NOW + timedelta(days=7)
    metrics.record("foreground_open", day7)
    result = metrics.summary(progress, {"codex": {"status": "unsupported"}}, day7)
    assert result["funnel"] == {"attempts": 2, "observed": 1, "self_reported": 0, "reused": 1}
    assert result["observation_rate"] == {"numerator": 1, "denominator": 2}
    assert result["d1"] == {"status": "observed", "denominator": 1, "foreground": 1, "practice": 1}
    assert result["d7"] == {"status": "observed", "denominator": 1, "foreground": 1, "practice": 0}
    assert result["first_practice_funnel"] == {"denominator": 1, "started": 1, "observed": 1, "self_reported": 0, "reused": 1}
    assert result["reuse_rate"] == {"numerator": 1, "denominator": 1}
    assert result["unsupported_sources"] == 1


def test_self_report_copy_and_late_import_do_not_become_new_observation(tmp_path):
    metrics = LocalMetrics(tmp_path, NOW)
    progress = {}
    ledger = PracticeLedger(progress, NOW)
    ledger.start(CARD, "one", NOW)
    ledger.self_report(CARD, NOW, unsupported=True)
    old = CompactEvent(tool="claude_code", key="late", ts=(NOW - timedelta(days=1)).isoformat(),
                       model="m", tool_calls={"WebSearch": 1})
    ledger.observe([old], [CARD], COVERAGE, NOW + timedelta(days=1))
    metrics.record("share_preview", NOW)
    metrics.record("share_copy", NOW)
    metrics.record("activation", NOW, "imported_verified")
    result = metrics.summary(progress, {}, NOW + timedelta(days=1))
    assert result["observation_rate"] == {"numerator": 0, "denominator": 1}
    assert result["funnel"]["self_reported"] == 1
    assert result["d1"]["practice"] == 0
    assert result["activation_status"] == "imported_verified"
    assert result["paid_purchases"] is None


def test_rolling_expiry_and_bounded_rows_keep_small_counters(tmp_path):
    metrics = LocalMetrics(tmp_path, NOW)
    metrics.record("trial_start", NOW)
    for day in range(95):
        metrics.record("foreground_open", NOW + timedelta(days=day))
    result = metrics.summary({}, {}, NOW + timedelta(days=94))
    assert result["counts"]["foreground_open"] == 90
    assert result["expired_counts"]["foreground_open"] == 5
    assert result["truncated"] is True
    assert result["window_days"] == 90
    assert result["window_start"] == (NOW.astimezone() + timedelta(days=5)).replace(
        hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc).isoformat()
    metrics.record("trial_start", NOW + timedelta(days=94))
    assert metrics.summary({}, {}, NOW + timedelta(days=94))["trial_starts"] == 1
    state = json.loads((tmp_path / "local_metrics.json").read_text())
    assert len(state["events"]) <= 2048
    assert all(set(row) == {"name", "object_id", "utc", "local_date", "result"} for row in state["events"])


def test_rejects_unreviewed_event_names_results_and_future_practice(tmp_path):
    metrics = LocalMetrics(tmp_path, NOW)
    with pytest.raises(ValueError):
        metrics.record("published", NOW)
    with pytest.raises(ValueError):
        metrics.record("activation", NOW, "license-secret")
    result = metrics.summary({"practice": {"attempts": [{"started_at": (NOW + timedelta(days=1)).isoformat()}]}}, {}, NOW)
    assert result["funnel"]["attempts"] == 0
    assert "license-secret" not in (tmp_path / "local_metrics.json").read_text()


def test_snapshot_and_cli_share_serialized_ledger(tmp_path, capsys):
    from agentfit.engine.snapshot import build_snapshot
    from agentfit.engine.__main__ import main
    state = tmp_path / "state"
    result = build_snapshot(tmp_path / "home", state, "en", NOW, enabled=set())
    assert result["local_validation"]["funnel"]["attempts"] == 0
    assert result["local_validation"]["labels"]["title"] == "Local validation"
    for _ in range(2):
        assert main(["local-event", "share_copy", "--state-dir", str(state)]) == 0
    assert json.loads(capsys.readouterr().out.splitlines()[-1]) == {"ok": True}
    assert (state / "engine.lock").exists()


def test_concurrent_cli_events_and_snapshot_never_lose_updates(tmp_path):
    from concurrent.futures import ThreadPoolExecutor
    import subprocess
    import sys
    from agentfit.engine.snapshot import build_snapshot
    state = tmp_path / "state"
    build_snapshot(tmp_path / "home", state, "en", NOW, enabled=set())
    commands = [["local-event", name] for name in ("share_preview", "share_copy", "trial_start", "foreground_open")]
    commands += [["snapshot", "--home", str(tmp_path / "home"), "--tools", "", "--json"]]
    def run(arguments):
        return subprocess.run([sys.executable, "-m", "agentfit.engine", *arguments,
                               "--state-dir", str(state)], capture_output=True, text=True)
    with ThreadPoolExecutor(max_workers=5) as pool:
        results = list(pool.map(run, commands * 2))
    assert all(result.returncode == 0 for result in results)
    result = LocalMetrics(state, datetime.now(timezone.utc)).summary({}, {}, datetime.now(timezone.utc))
    for name in ("share_preview", "share_copy", "trial_start", "foreground_open"):
        assert result["counts"][name] == 1
    assert result["paid_purchases"] is None


def test_window_boundary_keeps_the_whole_first_local_date(tmp_path):
    metrics = LocalMetrics(tmp_path, NOW)
    early = (NOW.astimezone() + timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
    metrics.record("foreground_open", early)
    result = metrics.summary({}, {}, NOW + timedelta(days=90))
    assert result["d1"] == {"status": "observed", "denominator": 1, "foreground": 1, "practice": 0}


def test_corrupt_metrics_restart_measurement_without_inventing_install(tmp_path):
    (tmp_path / "local_metrics.json").write_text("{broken")
    result = LocalMetrics(tmp_path, NOW).summary({}, {}, NOW)
    assert result["cohort"] == "post_upgrade"
    assert result["installation_date"] is None
    assert result["measurement_reset"] is True
