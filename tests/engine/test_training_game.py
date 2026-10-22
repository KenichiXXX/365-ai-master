"""Task 45: deterministic local rewards, never self-report evidence."""
from datetime import datetime, timedelta, timezone
import json
import subprocess
import sys

import pytest

from agentfit.engine.training_game import checkin, mark_card_read, sync_game, level_progress
from agentfit.engine.codex_book import _read_progress

NOW = datetime(2026, 10, 22, 12, tzinfo=timezone.utc)


def test_checkin_and_card_read_idempotent_and_validated(tmp_path):
    path = tmp_path / 'progress.json'
    assert checkin(path, NOW)
    assert checkin(path, NOW)
    assert not mark_card_read(path, 'invented', NOW)
    assert mark_card_read(path, 'web_search', NOW)
    assert mark_card_read(path, 'web_search', NOW)
    p = _read_progress(path)
    game = sync_game(p, NOW, 'en')
    assert game['xp'] == 10
    assert game['today']['completed'] == 2
    assert len(p['training_game']['ledger']) == 2
    assert 'passed' in p and 'lit' in p


def test_chest_requires_verified_practice_and_is_once_per_day(tmp_path):
    path = tmp_path / 'progress.json'
    checkin(path, NOW)
    mark_card_read(path, 'web_search', NOW)
    p = _read_progress(path)
    p['practice'] = {'events': {'self': {'kind': 'self_reported', 'local_date': NOW.astimezone().date().isoformat()}}}
    assert sync_game(p, NOW, 'zh')['today']['completed'] == 2
    day = NOW.astimezone().date().isoformat()
    p['practice']['events']['verified'] = {'kind': 'log_observed', 'local_date': day,
        'attempt_id': '1', 'skill_id': 'web_search'}
    game = sync_game(p, NOW, 'zh')
    assert game['xp'] == 50  # 5 + 5 + 20 + chest 20
    assert game['today']['chest_tip']
    assert sync_game(p, NOW, 'zh') == game
    assert sync_game(p, NOW, 'en')['today']['chest_tip'] != game['today']['chest_tip']
    # A second raw event in the same practice is not a second reward.
    p['practice']['events']['duplicate'] = dict(p['practice']['events']['verified'])
    assert sync_game(p, NOW, 'zh')['xp'] == 50


def test_quest_and_badge_rewards_are_once_and_quest_completes_daily_practice():
    p = {'passed': {'first_edit': NOW.isoformat()}, 'badges': ['first_skill']}
    game = sync_game(p, NOW, 'en')
    assert game['xp'] == 80
    assert game['today']['practice'] is True
    assert sync_game(p, NOW + timedelta(days=1), 'en')['xp'] == 80
    assert sync_game(p, NOW + timedelta(days=1), 'en')['today']['practice'] is False


def test_level_math():
    assert level_progress(0) == (1, 0, 50)
    assert level_progress(49) == (1, 49, 50)
    assert level_progress(50) == (2, 0, 100)
    assert level_progress(1050 + 120) == (7, 120, 350)


def test_shield_earned_used_once_and_calendar_preserves_missed_day(tmp_path):
    path = tmp_path / 'progress.json'
    for offset in range(7):
        checkin(path, NOW + timedelta(days=offset))
    game = sync_game(_read_progress(path), NOW + timedelta(days=6), 'en')
    assert game['shields'] == 1
    assert game['streak'] == game['best_streak'] == 7
    checkin(path, NOW + timedelta(days=8))
    p = _read_progress(path)
    game = sync_game(p, NOW + timedelta(days=8), 'en')
    assert game['shields'] == 0
    assert game['streak'] == 9
    missed = (NOW + timedelta(days=7)).astimezone().date().isoformat()
    assert next(d for d in game['calendar'] if d['date'] == missed)['state'] == 'shield'
    assert sync_game(p, NOW + timedelta(days=8), 'en')['shields'] == 0
    checkin(path, NOW + timedelta(days=11))
    game = sync_game(_read_progress(path), NOW + timedelta(days=11), 'en')
    assert game['streak'] == 1 and game['best_streak'] == 9


def test_shields_capped_and_local_day_boundary(tmp_path):
    path = tmp_path / 'progress.json'
    for offset in range(28):
        checkin(path, NOW + timedelta(days=offset))
    assert sync_game(_read_progress(path), NOW + timedelta(days=27), 'en')['shields'] == 2
    # Two UTC instants on the same machine-local date give only one stamp.
    p = _read_progress(path)
    assert len(p['training_game']['checkins']) == 28


@pytest.mark.parametrize("offset", range(4))
def test_weekly_rotation_reward_and_iso_year(offset):
    monday = datetime(2026, 10, 19, 12, tzinfo=timezone.utc) + timedelta(weeks=offset)
    ids = [sync_game({}, monday + timedelta(weeks=w), 'en')['weekly']['kind'] for w in range(4)]
    assert len(set(ids)) == 4
    p = {}
    game = sync_game(p, monday, 'en')
    week = game['weekly']['week']
    kind = game['weekly']['kind']
    state = p['training_game']
    if kind == 'checkins':
        state['checkins'] = {(monday + timedelta(days=d)).astimezone().date().isoformat(): True for d in range(5)}
    elif kind == 'cards':
        p['lit'] = {'a': {'how': 'log'}, 'b': {'how': 'log'}}
    elif kind == 'practices':
        p['practice'] = {'events': {str(i): {'kind': 'log_observed', 'local_date': monday.astimezone().date().isoformat(),
            'attempt_id': str(i), 'skill_id': str(i)} for i in range(3)}}
    else:
        p['history'] = {monday.astimezone().date().isoformat(): {'dims': {'routing': 55}}}
        state['weeks'][week]['baseline_dims'] = {'routing': 50}
    game = sync_game(p, monday + timedelta(days=5), 'en')
    assert game['weekly']['earned']
    ledger = list(state['ledger'].values())
    assert sum(e['xp'] for e in ledger if e['kind'] == 'weekly') == 50
    assert any(b.startswith('weekly:') for b in game['weekly_badges'])
    assert sync_game(p, monday + timedelta(days=5), 'en')['xp'] == game['xp']
    assert sync_game(p, datetime(2027, 1, 1, tzinfo=timezone.utc), 'en')['weekly']['week'] == '2026-W53'


def test_snapshot_and_cli_expose_game(tmp_path):
    state = tmp_path / 'state'
    for args in [['checkin'], ['mark-card-read', 'web_search']]:
        result = subprocess.run([sys.executable, '-m', 'agentfit.engine', *args, '--state-dir', str(state)],
                                capture_output=True, text=True)
        assert result.returncode == 0, result.stdout
        assert json.loads(result.stdout)['ok']
    from agentfit.engine.snapshot import build_snapshot
    snapshot = build_snapshot(tmp_path / 'home', state, 'en', enabled=set())
    assert snapshot['training_game']['today']['completed'] == 2
    assert snapshot['training_game']['xp'] == 10


def test_each_distinct_card_read_rewards_once_per_day(tmp_path):
    path = tmp_path / 'progress.json'
    mark_card_read(path, 'web_search', NOW)
    mark_card_read(path, 'init_cmd', NOW)
    mark_card_read(path, 'web_search', NOW)
    p = _read_progress(path)
    assert sync_game(p, NOW, 'en')['xp'] == 10


def test_shield_is_automatic_on_snapshot_not_only_on_next_checkin(tmp_path):
    path = tmp_path / 'progress.json'
    for d in range(7):
        checkin(path, NOW + timedelta(days=d))
    p = _read_progress(path)
    game = sync_game(p, NOW + timedelta(days=8), 'en')
    assert game['shields'] == 0
    assert game['streak'] == 8
    assert sync_game(p, NOW + timedelta(days=8), 'en') == game


def test_machine_local_day_boundary(tmp_path, monkeypatch):
    import time
    monkeypatch.setenv('TZ', 'Asia/Tokyo')
    time.tzset()
    try:
        path = tmp_path / 'progress.json'
        before = datetime(2026, 10, 22, 14, 59, tzinfo=timezone.utc)
        checkin(path, before)
        checkin(path, before + timedelta(seconds=30))
        assert len(_read_progress(path)['training_game']['checkins']) == 1
        checkin(path, before + timedelta(minutes=1))
        p = _read_progress(path)
        assert sorted(p['training_game']['checkins']) == ['2026-10-22', '2026-10-23']
        assert sync_game(p, before + timedelta(minutes=1), 'en')['streak'] == 2
    finally:
        monkeypatch.undo()
        time.tzset()


def test_real_collector_practice_unlocks_chest_without_source_content(tmp_path):
    from agentfit.engine.snapshot import build_snapshot
    from agentfit.engine.codex_book import practice_command
    home, state = tmp_path / 'home', tmp_path / 'state'
    log = home / '.claude/projects/demo/session.jsonl'
    log.parent.mkdir(parents=True)

    def append(identity, at):
        row = {'type': 'assistant', 'timestamp': at.isoformat(),
               'message': {'id': identity, 'model': 'claude-sonnet-5',
                           'usage': {'input_tokens': 10, 'output_tokens': 2},
                           'content': [{'type': 'text', 'text': 'private-game-sentinel'},
                                       {'type': 'tool_use', 'id': identity, 'name': 'WebSearch',
                                        'input': {'query': 'private-game-sentinel'}}]}}
        with log.open('a') as stream:
            stream.write(json.dumps(row) + '\n')

    append('old', NOW - timedelta(seconds=1))
    build_snapshot(home, state, 'en', NOW)
    path = state / 'progress.json'
    checkin(path, NOW)
    mark_card_read(path, 'web_search', NOW)
    assert practice_command('web_search', 'start', path, NOW)
    before = build_snapshot(home, state, 'en', NOW)
    assert before['training_game']['today']['completed'] == 2
    append('new', NOW + timedelta(seconds=1))
    after = build_snapshot(home, state, 'en', NOW + timedelta(seconds=2))
    assert after['training_game']['today']['completed'] == 3
    assert after['training_game']['today']['chest_tip']
    assert after == build_snapshot(home, state, 'en', NOW + timedelta(seconds=2))
    assert 'private-game-sentinel' not in json.dumps(after)
    assert 'private-game-sentinel' not in path.read_text()
