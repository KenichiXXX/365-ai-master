import json
from datetime import date, datetime, timedelta, timezone

import pytest

from agentfit.engine.codex_book import (
    badges, daily_rankings, daily_tip, detected, mark_tried, streak, today_skill, update_book,
)
from agentfit.engine.content_pool import load_content
from agentfit.engine.events import CompactEvent
from agentfit.engine.inventory import Inventory
from agentfit.engine.profile import Profile, build_profile

NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
TODAY = NOW.astimezone().date()


def inventory(size=201, skills=None):
    return Inventory(skills or [], size, 0, 0, 0, 0)


@pytest.mark.parametrize("rule,fields,inv", [
    ("tool:WebSearch", {"tool_calls_30d": {"WebSearch": 1}}, {}),
    ("mcp", {"tool_calls_30d": {"mcp": 1}}, {}),
    ("skill_any", {"skill_calls_30d": {"tdd": 1}}, {}),
    ("sidechain", {"sidechain_30d": 1}, {}),
    ("hook", {"hook_success_30d": 1}, {}),
    ("compaction", {"compactions_30d": 1}, {}),
    ("light_model", {"light_token_share_30d": 0.001}, {}),
    ("effort:high|xhigh|max", {"efforts_30d": {"xhigh"}}, {}),
    ("instructions:claude", {}, {"claude_code": inventory()}),
    ("instructions:codex", {}, {"codex": inventory()}),
])
def test_detect_and_permanent_lighting(tmp_path, rule, fields, inv):
    content = load_content(None)
    card = {**content["skills"][0], "detect": rule}
    content["skills"] = [card]
    blank = Profile(now=NOW)
    assert detected(card, blank, {}) is False
    assert detected(card, Profile(now=NOW, **fields), inv) is True
    path = tmp_path / "progress.json"
    path.write_text(json.dumps({"passed": {"first_edit": "before"}, "regress_notified": []}))
    book = update_book(content, Profile(now=NOW, **fields), inv, path, NOW)
    assert book["lit"] == book["total"] == 1
    how = "configuration" if rule.startswith("instructions:") else "log"
    assert book["cards"][0]["how"] == how
    assert update_book(content, blank, {}, path, NOW + timedelta(days=31))["lit"] == 1
    saved = json.loads(path.read_text())
    assert saved["lit"][card["id"]] == {"at": NOW.isoformat(), "how": how}
    assert saved["passed"] == {"first_edit": "before"}


def test_self_cards_and_mark_tried(tmp_path):
    content, path = load_content(None), tmp_path / "progress.json"
    assert detected({"detect": "self"}, Profile(now=NOW), {}) is None
    assert mark_tried("init_cmd", path, NOW) is True
    assert mark_tried("rules_file", path, NOW) is True
    assert mark_tried("unknown", path, NOW) is False
    book = update_book(content, Profile(now=NOW), {}, path, NOW)
    assert book["lit"] == 2
    card = next(c for c in book["cards"] if c["id"] == "init_cmd")
    assert card["lit"] and card["how"] == "self"
    assert mark_tried("init_cmd", path, NOW + timedelta(days=1))
    assert json.loads(path.read_text())["lit"]["init_cmd"]["at"] == NOW.isoformat()
    from agentfit.engine.village import advance
    from agentfit.engine.content import QUESTS
    advance({key: (False, "not_yet") for key in QUESTS}, path, NOW)
    assert update_book(content, Profile(now=NOW), {}, path, NOW)["lit"] == 2


def test_detect_instruction_boundary():
    assert not detected({"detect": "instructions:claude"}, Profile(now=NOW),
                        {"claude_code": inventory(200), "codex": inventory(999)})


def test_today_skill():
    cards = [{"id": str(i), "lit": i == 0} for i in range(4)]
    assert today_skill(cards, TODAY) == cards[1:][TODAY.toordinal() % 3]
    assert today_skill(cards, TODAY) == today_skill(cards, TODAY)
    all_lit = [{**c, "lit": True} for c in cards]
    assert today_skill(all_lit, TODAY) == all_lit[TODAY.toordinal() % 4]
    assert today_skill([], TODAY) == {}


def test_today_skill_follows_the_path_from_the_lowest_unfinished_level():
    cards = [{"id": "advanced", "lit": False, "level": 3}, {"id": "basic-a", "lit": False, "level": 1},
             {"id": "basic-done", "lit": True, "level": 1}, {"id": "basic-b", "lit": False, "level": 1}]
    for offset in range(4):
        assert today_skill(cards, TODAY + timedelta(days=offset))["id"] in {"basic-a", "basic-b"}
    finished = [{**card, "lit": card["level"] == 1} for card in cards]
    assert today_skill(finished, TODAY)["id"] == "advanced"


def test_rankings_and_tip():
    content = load_content(None)
    entries = [{"name": str(i), "url": "https://example.org", "tagline": {"zh": "中文", "en": "English"},
                "match": ["tdd"] if i == 0 else []} for i in range(7)]
    content["rankings"] = {"skill": entries, "agent": []}
    result = daily_rankings(content, {"codex": inventory(skills=["tdd"])}, "en", TODAY, n=7)
    offset = TODAY.toordinal() % 7
    assert [r["name"] for r in result["skill"]] == [str(i) for i in list(range(7))[offset:] + list(range(7))[:offset]]
    assert {r["name"] for r in result["skill"] if r["installation_hint"]} == {"0"}
    assert all(r["tagline"] == "English" for r in result["skill"])
    assert result["agent"] == []
    assert len(daily_rankings(content, {}, "zh", TODAY)["skill"]) == 5
    assert daily_rankings(content, {}, "zh", TODAY) != daily_rankings(content, {}, "zh", TODAY + timedelta(days=1))
    expected = content["tips"][TODAY.toordinal() % len(content["tips"])]
    assert daily_tip(content, "en", TODAY) == {**expected, "title": expected["title"]["en"], "detail": expected["detail"]["en"], "limitations": expected["limitations"]["en"]}
    assert daily_tip({"tips": []}, "en", TODAY) == {}


@pytest.mark.parametrize("offsets,expected", [([], 0), ([0], 1), ([1, 2, 3], 3),
    ([0, 1, 2, 4], 3), ([2, 3], 0), ([0, 0, 1], 2)])
def test_streak(offsets, expected):
    assert streak([(TODAY - timedelta(days=d)).isoformat() for d in offsets], TODAY) == expected


@pytest.mark.parametrize("days,lit,total,passed,earned", [
    (0, 0, 24, 0, set()),
    (3, 5, 24, 8, {"streak_3", "book_5"}),
    (7, 10, 24, 9, {"streak_3", "streak_7", "book_5", "book_10", "village_done"}),
    (14, 20, 24, 0, {"streak_3", "streak_7", "streak_14", "book_5", "book_10", "book_20"}),
    (30, 24, 24, 9, {"streak_3", "streak_7", "streak_14", "streak_30", "book_5", "book_10", "book_20", "book_all", "village_done"}),
    (0, 0, 0, 0, set()),
])
def test_badges(days, lit, total, passed, earned):
    rows = badges(days, lit, total, passed, "en")
    assert len(rows) == 9
    assert {r["id"] for r in rows if r["earned"]} == earned
    assert rows[0]["title"] == "3-day streak"
    assert badges(days, lit, total, passed, "zh")[0]["title"] == "连续 3 天"


def test_profile_30_day_window_and_dedupe():
    def event(key, days, **kw):
        return CompactEvent(tool="codex", key=key, ts=(NOW - timedelta(days=days)).isoformat(),
                            model="claude-haiku-4-5", **kw)
    events = [event("old", 30, input=10, output=1, tool_calls={"WebSearch": 1},
                    skill_calls={"tdd": 1}, sidechain=True, hook_success=1, compacted=1, effort="high"),
              event("old", 30, input=10, output=5, tool_calls={"WebFetch": 1}),
              event("recent", 1, input=5),
              event("expired", 30 + 1 / 86400, input=1000, effort="max"),
              CompactEvent(tool="codex", key="marker", ts=NOW.isoformat(), model="", effort="xhigh")]
    p = build_profile(events, NOW)
    assert p.tool_calls_30d == {"WebSearch": 1, "WebFetch": 1}
    assert p.skill_calls_30d == {"tdd": 1}
    assert (p.sidechain_30d, p.hook_success_30d, p.compactions_30d) == (1, 1, 1)
    assert p.light_token_share_30d == 1.0
    assert p.efforts_30d == {"high", "xhigh"}
    assert p.active_dates_30d == sorted({(NOW - timedelta(days=d)).astimezone().date().isoformat() for d in (1, 30)})
    assert p.tool_calls_14d == {} and p.skill_calls_14d == {}
    assert p.by_tool["codex"]["7d"]["tokens"] == 5


def test_any_light_usage_remains_detectable():
    events = [CompactEvent(tool="codex", key="fast", ts=NOW.isoformat(),
                           model="claude-haiku-4-5", input=1),
              CompactEvent(tool="codex", key="premium", ts=NOW.isoformat(),
                           model="claude-opus-4", input=1_000_000)]
    profile = build_profile(events, NOW)
    assert detected({"detect": "light_model"}, profile, {}) is True


def test_active_dates_use_local_usage_days(monkeypatch):
    import time
    try:
        with monkeypatch.context() as patch:
            patch.setenv("TZ", "Asia/Tokyo")
            time.tzset()
            profile = build_profile([
                CompactEvent(tool="codex", key="usage", ts="2026-10-20T16:00:00+00:00",
                             model="gpt-6.1-sol", input=1),
                CompactEvent(tool="codex", key="marker", ts="2026-10-19T16:00:00+00:00",
                             model="", turn_start=1),
            ], NOW)
            assert profile.active_dates_30d == ["2026-10-21"]
    finally:
        time.tzset()


def test_live_rankings_match_plugins_case_insensitively_and_keep_order():
    content = load_content(None)
    rows = [{"name": str(i), "url": "https://example.org", "tagline": {"en": "English", "zh": "中文"},
             "match": ["SUPERPOWERS"] if i == 0 else ["TDD"]} for i in range(7)]
    content["rankings"] = {"skill": rows, "agent": rows, "rotate": False,
                           "source": "The Skill Leaderboard · GitHub", "updated_at": "2026-10-21"}
    inv = inventory(skills=["tdd"])
    inv.plugins_installed = ["superpowers"]
    result = daily_rankings(content, {"claude_code": inv}, "zh", TODAY)
    assert [row["name"] for row in result["skill"]] == [str(i) for i in range(5)]
    assert all(row["installation_hint"] for row in result["skill"])
    assert result["source"] == content["rankings"]["source"]
    assert result["updated_at"] == "2026-10-21"
    assert daily_rankings(content, {"claude_code": inv}, "zh", TODAY + timedelta(days=1)) == result


def test_today_skill_skips_yesterdays_card_when_pool_shrinks(tmp_path):
    content = load_content(None)
    # Four cards yesterday, three today; today's modulo points to yesterday's card.
    content["skills"] = [{**content["skills"][0], "id": str(i), "detect": "self", "validator": "self"}
                         for i in range(4)]
    path = tmp_path / "progress.json"
    yesterday = NOW - timedelta(days=1)
    previous = update_book(content, Profile(now=yesterday), {}, path, yesterday)["today"]
    assert previous["id"] == "1"
    assert mark_tried("3", path, NOW)
    book = update_book(content, Profile(now=NOW), {}, path, NOW)
    assert book["today"]["id"] == "0"
    assert book["today"]["id"] != previous["id"]
    assert update_book(content, Profile(now=NOW), {}, path, NOW)["today"] == book["today"]
    assert all(c["detect"] == "self" for c in book["cards"])
    content["skills"] = [next(c for c in content["skills"] if c["id"] == book["today"]["id"])]
    tomorrow = NOW + timedelta(days=1)
    assert update_book(content, Profile(now=tomorrow), {}, path, tomorrow)["today"]["mode"] == "review"


def test_rankings_emit_growth_metrics():
    content = load_content(None)
    content["rankings"] = {"skill": [
        {"name": "a/b", "url": "https://example.org", "tagline": {"zh": "中文", "en": "English"},
         "match": [], "stars": 302_000, "stars7d": 3946},
        {"name": "a/c", "url": "https://example.org", "tagline": {"zh": "中文", "en": "English"},
         "match": [], "stars": 2000, "stars7d": None}], "agent": [], "rotate": False}
    rows = daily_rankings(content, {}, "en", TODAY)["skill"]
    assert (rows[0]["stars"], rows[0]["stars7d"]) == (302_000, 3946)
    assert rows[1]["stars7d"] is None


@pytest.mark.parametrize("locale,titles", [("zh", ["入门", "进阶", "高手"]),
                                           ("en", ["Basics", "Intermediate", "Advanced"])])
def test_snapshot_training_groups(tmp_path, locale, titles):
    from agentfit.engine.snapshot import build_snapshot
    state = tmp_path / "state"
    state.mkdir()
    state.joinpath("progress.json").write_text(json.dumps({
        "passed": {}, "regress_notified": [],
        "lit": {"rules_file": {"at": NOW.isoformat(), "how": "log"}}}))
    snapshot = build_snapshot(tmp_path / "home", state, locale, NOW, enabled=set())
    groups = snapshot["book"]["groups"]
    assert [g["level"] for g in groups] == [1, 2, 3]
    assert [g["title"] for g in groups] == titles
    assert [g["total"] for g in groups] == [8, 10, 6]
    assert [g["lit"] for g in groups] == [1, 0, 0]
    assert groups[0]["missing"] == ["web_search", "web_fetch", "ask_first", "init_cmd",
                                      "clear_session", "at_mention", "paste_image"]
    assert snapshot["book"]["next_badge"] == {
        "id": "streak_3", "title": "连续 3 天" if locale == "zh" else "3-day streak",
        "have": 0, "need": 3}


@pytest.mark.parametrize("days,lit,total,passed,expected", [
    (0, 0, 24, 0, ("streak_3", 0, 3)),
    (2, 4, 24, 8, ("streak_3", 2, 3)),
    (3, 4, 24, 8, ("book_5", 4, 5)),
    (7, 10, 24, 8, ("village_done", 8, 9)),
    (30, 23, 24, 9, ("book_all", 23, 24)),
    (30, 24, 24, 9, None),
    (30, 0, 0, 9, ("book_5", 0, 5)),
])
def test_next_badge(days, lit, total, passed, expected):
    from agentfit.engine.codex_book import next_badge
    result = next_badge(days, lit, total, passed, "en")
    if expected is None:
        assert result is None
    else:
        key, have, need = expected
        assert result == {"id": key, "title": next(b["title"] for b in
            badges(days, lit, total, passed, "en") if b["id"] == key), "have": have, "need": need}
