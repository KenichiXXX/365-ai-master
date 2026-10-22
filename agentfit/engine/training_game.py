"""Local daily game derived from explicit actions and verified evidence.

The CLI caller holds engine.lock, as for all other progress mutations. Snapshots
reconcile rewards from stable source identities; rereading logs cannot mint XP.
"""
from datetime import date, datetime, timedelta
import calendar
import json
import secrets

from agentfit.engine.codex_book import _read_progress, _save_progress
from agentfit.engine.content import GAME_LEVELS, GAME_TIPS, GAME_WEEKLY
from agentfit.engine.content_pool import load_content


def level_progress(xp):
    level = 1
    while xp >= 50 * level:
        xp -= 50 * level
        level += 1
    return level, xp, 50 * level


def _state(progress):
    return progress.setdefault('training_game', {
        'version': 1, 'checkins': {}, 'reads': {}, 'ledger': {},
        'shields': 0, 'protected': [], 'weeks': {}, 'shield_awards': [],
    })


def _reward(state, kind, identity, day, xp):
    # JSON tuple encoding avoids delimiter collisions in source IDs.
    key = json.dumps([kind, identity, day], separators=(',', ':'))
    state['ledger'].setdefault(key, {'kind': kind, 'id': identity, 'date': day, 'xp': xp})


def _runs(state, today):
    days = sorted(date.fromisoformat(d) for d in set(state['checkins']) | set(state['protected'])
                  if d <= today.isoformat())
    best = current = 0
    previous = None
    start = None
    for day in days:
        if previous is None or day != previous + timedelta(days=1):
            current, start = 0, day
        current += 1
        best = max(best, current)
        previous = day
    if previous is None or previous < today - timedelta(days=1):
        current = 0
    return current, best, start


def checkin(path, now):
    progress = _read_progress(path)
    sync_game(progress, now, 'en')
    state = _state(progress)
    today = now.astimezone().date()
    day = today.isoformat()
    if day not in state['checkins']:
        state['checkins'][day] = True
        count, _, start = _runs(state, today)
        # Milestone identities include run start, so broken streaks start fresh.
        milestone = f'{start}:{count // 7}'
        if count >= 7 and count % 7 == 0 and milestone not in state['shield_awards']:
            state['shield_awards'].append(milestone)
            state['shields'] = min(2, state['shields'] + 1)
    sync_game(progress, now, 'en')
    _save_progress(path, progress)
    return True


def mark_card_read(path, card_id, now):
    progress = _read_progress(path)
    # Review cards stay readable after the 24-card book is complete.
    pool = load_content(None)
    valid = {c['id'] for c in pool['skills'] + pool.get('review_exercises', [])}
    if card_id not in valid:
        return False
    state = _state(progress)
    day = now.astimezone().date().isoformat()
    state['reads'].setdefault(day, [])
    if card_id not in state['reads'][day]:
        state['reads'][day].append(card_id)
    sync_game(progress, now, 'en')
    _save_progress(path, progress)
    return True


def sync_game(progress, now, locale):
    state = _state(progress)
    today = now.astimezone().date()
    day = today.isoformat()
    # On the first visit after a missed day, automatically protect completed
    # past days. Never stamp an unchecked day, including today.
    if state['checkins']:
        gap = date.fromisoformat(max(state['checkins'])) + timedelta(days=1)
        while gap < today and state['shields'] > 0:
            key = gap.isoformat()
            if key not in state['protected']:
                state['protected'].append(key)
                state['shields'] -= 1
            gap += timedelta(days=1)
    practices = set()
    for row in progress.get('practice', {}).get('events', {}).values():
        if row.get('kind') == 'log_observed' and row.get('attempt_id') and row.get('local_date', '') <= day:
            practices.add((row['local_date'], str(row['attempt_id'])))
    verified_days = {d for d, _ in practices}
    for d, identity in practices:
        _reward(state, 'practice', identity, d, 20)
    for identity, at in progress.get('passed', {}).items():
        d = datetime.fromisoformat(at).astimezone().date().isoformat()
        if d <= day:
            _reward(state, 'quest', identity, d, 50)
            verified_days.add(d)
    for d in state['checkins']:
        if d <= day:
            _reward(state, 'checkin', 'daily', d, 5)
    for d, ids in state['reads'].items():
        if d <= day:
            for identity in ids:
                _reward(state, 'card_read', identity, d, 5)
    for identity in progress.get('badges', []):
        # Badge source has no timestamp. Retain the first local observation date.
        earned = state.setdefault('badge_dates', {}).setdefault(identity, day)
        _reward(state, 'badge', identity, earned, 30)
    complete = set(state['checkins']) & set(state['reads']) & verified_days
    for d in sorted(complete):
        if d > day:
            continue
        _reward(state, 'chest', 'daily', d, 20)
        chests = state.setdefault('chests', {})
        if d not in chests:
            chests[d] = secrets.randbelow(len(GAME_TIPS))

    monday = today - timedelta(days=today.weekday())
    iso = today.isocalendar()
    week = f'{iso.year}-W{iso.week:02d}'
    kind = list(GAME_WEEKLY)[(monday.toordinal() // 7) % len(GAME_WEEKLY)]
    target, titles = GAME_WEEKLY[kind]
    history = progress.get('history', {})
    latest = max((d for d in history if d <= day), default=None)
    dims = history.get(latest, {}).get('dims', {})
    challenge = state['weeks'].setdefault(week, {
        'kind': kind, 'baseline_cards': sorted(progress.get('lit', {})),
        'baseline_dims': dims.copy(), 'earned': False,
    })
    week_start, week_end = monday.isoformat(), (monday + timedelta(days=6)).isoformat()
    if kind == 'checkins':
        have = sum(week_start <= d <= min(day, week_end) for d in state['checkins'])
    elif kind == 'cards':
        have = len(set(progress.get('lit', {})) - set(challenge['baseline_cards']))
    elif kind == 'practices':
        have = sum(week_start <= d <= min(day, week_end) for d, _ in practices)
    else:
        baseline = challenge['baseline_dims']
        # A missing dimension starts at its first available observation, not zero.
        for key, value in dims.items():
            if value is not None and baseline.get(key) is None:
                baseline[key] = value
        have = max([0] + [value - baseline[key] for key, value in dims.items()
                          if value is not None and baseline.get(key) is not None])
    challenge['progress'] = max(challenge.get('progress', 0), min(target, have))
    if challenge['progress'] >= target:
        challenge['earned'] = True
        earned = challenge.setdefault('earned_date', day)
        _reward(state, 'weekly', week, earned, 50)
        _reward(state, 'badge', 'weekly:' + week, earned, 30)
    xp = sum(row['xp'] for row in state['ledger'].values())
    level, within, required = level_progress(xp)
    current, best, _ = _runs(state, today)
    completed = [day in state['checkins'], bool(state['reads'].get(day)), day in verified_days]
    chest = state.get('chests', {}).get(day)
    return {
        'xp': xp, 'level': level, 'level_xp': within, 'next_level_xp': required,
        'level_title': GAME_LEVELS[locale][min((level - 1) // 5, 5)],
        'today': {'checkin': completed[0], 'card_read': completed[1], 'practice': completed[2],
                  'completed': sum(completed), 'chest_tip': GAME_TIPS[chest][0 if locale == 'zh' else 1] if chest is not None else None},
        'shields': state['shields'], 'streak': current, 'best_streak': best,
        'month': today.strftime('%Y-%m'), 'first_weekday': today.replace(day=1).weekday(),
        'calendar': [{'date': today.replace(day=n).isoformat(),
                      'state': 'stamp' if today.replace(day=n).isoformat() in state['checkins'] else
                               'shield' if today.replace(day=n).isoformat() in state['protected'] else 'empty'}
                     for n in range(1, calendar.monthrange(today.year, today.month)[1] + 1)],
        'weekly': {'week': week, 'kind': kind, 'title': titles[locale], 'have': challenge['progress'],
                   'need': target, 'earned': challenge['earned']},
        'weekly_badges': ['weekly:' + w for w, c in sorted(state['weeks'].items()) if c['earned']],
    }
