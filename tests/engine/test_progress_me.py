import json
from datetime import datetime, timedelta, timezone

from agentfit.engine.history import record_history
from agentfit.engine.snapshot import build_snapshot


NOW = datetime(2026, 10, 22, 12, tzinfo=timezone.utc)


def test_snapshot_exposes_nullable_progress_me(tmp_path):
    snapshot = build_snapshot(tmp_path / 'empty', tmp_path / 'state', 'en', now=NOW)
    assert snapshot['progress_me'] == {
        'vs_yesterday': None, 'personal_best': None, 'week_delta': None,
    }


def test_latest_local_daily_scores_best_and_monday_baseline(tmp_path):
    from agentfit.engine.history import progress_me
    path = tmp_path / 'progress.json'
    record_history(path, NOW.replace(day=19), 64, {}, [])
    record_history(path, NOW.replace(day=20), 74, {}, [])
    record_history(path, NOW.replace(day=21, hour=1), 60, {}, [])
    record_history(path, NOW.replace(day=21), 67, {}, [])
    record_history(path, NOW, 69, {}, [])
    history = json.loads(path.read_text())['history']
    assert progress_me(history, NOW) == {
        'vs_yesterday': 2, 'personal_best': 74, 'week_delta': 5,
    }
    record_history(path, NOW.replace(hour=13), 66, {}, [])
    assert progress_me(json.loads(path.read_text())['history'], NOW) == {
        'vs_yesterday': -1, 'personal_best': 74, 'week_delta': 2,
    }


def test_missing_invalid_future_and_other_versions_are_not_comparable():
    from agentfit.engine.history import progress_me
    today = NOW.astimezone().date()
    def row(score, version='1', rule='1'):
        return {'score': score, 'score_version': version, 'rule_version': rule}
    history = {today.isoformat(): row(69),
               (today - timedelta(days=1)).isoformat(): row(69),
               (today - timedelta(days=2)).isoformat(): row(100, 'old'),
               (today + timedelta(days=1)).isoformat(): row(100)}
    assert progress_me(history, NOW) == {'vs_yesterday': 0, 'personal_best': 69, 'week_delta': None}
    for invalid in [None, True, 101, -1, '70']:
        history[(today - timedelta(days=1)).isoformat()] = row(invalid)
        assert progress_me(history, NOW)['vs_yesterday'] is None
    history[(today - timedelta(days=1)).isoformat()] = row(70, rule='old')
    assert progress_me(history, NOW)['vs_yesterday'] is None
    history[today.isoformat()] = row(None)
    assert progress_me(history, NOW) == {'vs_yesterday': None, 'personal_best': None, 'week_delta': None}


def test_progress_uses_local_day_across_utc_midnight(monkeypatch):
    import time
    from agentfit.engine.history import progress_me
    monkeypatch.setenv('TZ', 'Asia/Tokyo')
    time.tzset()
    try:
        now = datetime(2026, 10, 21, 16, tzinfo=timezone.utc)  # Oct 22 locally
        row = lambda n: {'score': n, 'score_version': '1', 'rule_version': '1'}
        assert progress_me({'2026-10-21': row(67), '2026-10-22': row(69)}, now)['vs_yesterday'] == 2
    finally:
        monkeypatch.undo()
        time.tzset()


def test_snapshot_wires_comparable_progress_without_changing_weekly_review(tmp_path):
    from tests.engine.test_snapshot import _home, NOW as fixture_now
    state = tmp_path / 'state'
    state.mkdir()
    today = fixture_now.astimezone().date()
    yesterday = (today - timedelta(days=1)).isoformat()
    (state / 'progress.json').write_text(json.dumps({'passed': {}, 'regress_notified': [], 'history': {
        yesterday: {'score': 50, 'score_version': '1', 'rule_version': '1'},
    }}))
    snapshot = build_snapshot(_home(tmp_path), state, 'zh', now=fixture_now)
    score = snapshot['overall']['score']
    assert score is not None
    assert snapshot['progress_me'] == {
        'vs_yesterday': score - 50, 'personal_best': max(50, score), 'week_delta': score - 50,
    }
    # The existing matched-weekday weekly review has its own, stricter window.
    assert snapshot['growth']['week_delta'] is None
    assert snapshot['weekly']['score_delta'] is None
