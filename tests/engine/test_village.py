from datetime import datetime, timezone, date, timedelta
import json

import pytest

from agentfit.engine import content as C
from agentfit.engine.events import CompactEvent
from agentfit.engine.profile import Profile, build_profile
from agentfit.engine.inventory import Inventory
from agentfit.models.checkup import DimensionScore
from agentfit.engine import village as V

NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
def dims(*s): return [DimensionScore(key=k, label=k, score=v) for k, v in zip(["routing","timing","context","leverage"], s)]
def inv(**kw):
    base = dict(skills_installed=[], instructions_bytes=0, hooks=0, mcp_servers=0, subagents=0, plugins=0); base.update(kw)
    return {"claude_code": Inventory(**base)}
def prof(**tool_calls):
    return build_profile([CompactEvent(tool="claude_code", key="a", ts=(NOW - timedelta(hours=1)).isoformat(), model="claude-sonnet-5", input=10, output=10, tool_calls=tool_calls)], NOW)

def test_sequential_unlock_and_persistence(tmp_path):
    pp = tmp_path / "progress.json"
    met = V.evaluate(prof(Edit=1), inv(instructions_bytes=500), dims(90,90,90,90))
    assert met["first_edit"][0] and met["rules_file"][0] and not met["light_model"][0]
    st = V.advance(met, pp, NOW)
    assert set(st["passed"]) == {"first_edit", "rules_file"} and st["current"] == "light_model"
    met2 = V.evaluate(prof(), inv(), dims(90,90,90,90))       # regressed: no edits, no CLAUDE.md
    st2 = V.advance(met2, pp, NOW)
    assert set(st2["passed"]) == {"first_edit", "rules_file"}  # never taken away
    assert set(st2["regressed"]) == {"first_edit", "rules_file"}
    assert V.advance(met2, pp, NOW)["regressed"] == []         # notified only once

def test_later_quest_not_passed_before_earlier(tmp_path):
    met = V.evaluate(prof(), inv(instructions_bytes=500), dims(90,90,90,90))   # rules_file met, first_edit not
    st = V.advance(met, tmp_path / "p.json", NOW)
    assert st["passed"] == {} and st["current"] == "first_edit"

def test_declutter_and_empty_install():
    assert V.evaluate(prof(), inv(), dims(90,90,90,90))["declutter"][0] is True
    p = build_profile([CompactEvent(tool="claude_code", key="s", ts=NOW.isoformat(), model="m", skill_calls={"plug:tdd": 3})], NOW)
    assert V.evaluate(p, inv(skills_installed=["tdd", "x", "y"]), dims(90,90,90,90))["declutter"][0] is False
    assert V.evaluate(p, inv(skills_installed=["tdd", "x"]), dims(90,90,90,90))["declutter"][0] is True
    assert V.evaluate(p, inv(), dims(90,90,90,90))["first_skill"][0] is True

def test_today_tip_order_and_determinism(tmp_path):
    st = {"passed": {}, "current": "first_edit", "regressed": []}
    t = V.today_tip(st, dims(90,90,90,90), "zh", date(2026,10,21))
    assert t["source"] == {"kind": "quest", "ref": "first_edit"} and t["prompt_for_claude"]
    done = {"passed": {k: "x" for k in V.QUESTS}, "current": None, "regressed": []}
    assert V.today_tip(done, dims(90,60,70,90), "en", date(2026,10,21))["source"] == {"kind": "dimension", "ref": "timing"}
    a = V.today_tip(done, dims(90,90,90,90), "en", date(2026,10,21)); b = V.today_tip(done, dims(90,90,90,90), "en", date(2026,10,21))
    assert a == b and a["source"]["kind"] == "pool"


@pytest.mark.parametrize("calls", [{"Edit": 1}, {"Write": 1}, {"apply_patch": 1}, {}])
def test_edit_tools(calls):
    result = V.evaluate(prof(**calls), {}, dims(85, 85, 85, 85))
    assert result["first_edit"] == (bool(calls), "" if calls else "not_yet")


@pytest.mark.parametrize("size,share,expected", [(200, 0.05, False), (201, 0.051, True)])
def test_strict_thresholds(size, share, expected):
    p = Profile(now=NOW, light_token_share_14d=share)
    result = V.evaluate(p, inv(instructions_bytes=size), dims(85, 85, 85, 85))
    assert result["rules_file"][0] is expected
    assert result["light_model"][0] is expected
    assert result["graduate"] == (True, "")
    assert not V.evaluate(p, {}, dims(85, 85, 84, 85))["graduate"][0]


@pytest.mark.parametrize("turns,aborted,expected", [
    (0, 0, (False, "need_data")), (9, 0, (False, "need_data")),
    (10, 1, (False, "not_yet")), (10, 0, (True, "")),
    (11, 1, (True, "")),
])
def test_rework_threshold(turns, aborted, expected):
    p = Profile(now=NOW, turns_14d=turns, aborted_14d=aborted)
    assert V.evaluate(p, {}, dims(90, 90, 90, 90))["less_rework"] == expected


def test_retry_rule_blocks_rework(monkeypatch):
    p = Profile(now=NOW, turns_14d=10)
    monkeypatch.setattr(p, "rule_hits", lambda: {"RULE_ERROR_RETRY_LOOP": True})
    assert V.evaluate(p, {}, dims(90, 90, 90, 90))["less_rework"] == (False, "not_yet")


def test_cross_tool_inventory_and_behavior():
    inventories = inv(skills_installed=["tdd", "x"])
    inventories["codex"] = inv(instructions_bytes=201, hooks=1, skills_installed=["tdd", "y"])["claude_code"]
    p = Profile(now=NOW, skill_calls_14d={"plug:tdd": 3}, sidechain_14d=1, hook_success_14d=1)
    result = V.evaluate(p, inventories, dims(90, 90, 90, 90))
    for key in ("rules_file", "first_skill", "parallel", "automation"):
        assert result[key] == (True, "")
    assert result["declutter"] == (False, "not_yet")
    p.skill_calls_14d["x"] = 1
    assert V.evaluate(p, inventories, [])["declutter"] == (True, "")
    p.hook_success_14d = 0
    assert not V.evaluate(p, inventories, [])["automation"][0]
    p.hook_success_14d = 1
    assert not V.evaluate(p, inv(), [])["automation"][0]


def test_persisted_timestamps_and_regression_after_recovery(tmp_path):
    path = tmp_path / "nested" / "progress.json"
    met = {key: (True, "") for key in V.QUESTS}
    state = V.advance(met, path, NOW)
    assert state["current"] is None
    assert state["passed"] == dict.fromkeys(V.QUESTS, NOW.isoformat())
    met["first_edit"] = (False, "not_yet")
    assert V.advance(met, path, NOW + timedelta(days=1))["regressed"] == ["first_edit"]
    met["first_edit"] = (True, "")
    V.advance(met, path, NOW + timedelta(days=2))
    met["first_edit"] = (False, "not_yet")
    assert V.advance(met, path, NOW + timedelta(days=3))["regressed"] == []
    assert json.loads(path.read_text()) == {
        "passed": state["passed"], "regress_notified": ["first_edit"],
    }


@pytest.mark.parametrize("locale", ["zh", "en"])
def test_village_snapshot_and_localized_tip(tmp_path, locale):
    met = V.evaluate(prof(Edit=1), inv(), dims(90, 90, 90, 90))
    state = V.advance(met, tmp_path / "progress.json", NOW)
    block = V.village_block(state, met, locale)
    assert block["current"] == "rules_file"
    assert block["rank_title"] == C.rank_title(1, locale)
    assert [q["key"] for q in block["quests"]] == V.QUESTS
    assert [q["status"] for q in block["quests"]] == ["passed", "current"] + ["locked"] * 7
    for q in block["quests"]:
        assert q == {
            "key": q["key"], "title": C.quest_text(q["key"], locale)["title"],
            "status": q["status"], "passed_at": state["passed"].get(q["key"]),
            "progress_hint": met[q["key"]][1],
        }
    tip = V.today_tip(state, dims(0, 0, 0, 0), locale, NOW.date())
    copy = C.quest_text("rules_file", locale)
    assert tip == {"title": copy["title"], "why": copy["why"], "steps": copy["steps"],
                   "prompt_for_claude": copy["prompt"], "source": {"kind": "quest", "ref": "rules_file"}}


def test_dimension_tie_order_and_pool_rotation():
    state = {"passed": dict.fromkeys(V.QUESTS, NOW.isoformat()), "current": None, "regressed": []}
    scores = list(reversed(dims(60, 60, 60, 60)))
    assert V.today_tip(state, scores, "en", NOW.date())["source"] == {"kind": "dimension", "ref": "routing"}
    for offset in range(len(C.POOL)):
        day = NOW.date() + timedelta(days=offset)
        assert V.today_tip(state, dims(85, 85, 85, 85), "en", day)["source"] == {
            "kind": "pool", "ref": C.POOL[day.toordinal() % len(C.POOL)],
        }
    block = V.village_block(state, dict.fromkeys(V.QUESTS, (True, "")), "en")
    assert block["current"] is None and block["rank_title"] == "Grandmaster"
    assert all(q["status"] == "passed" for q in block["quests"])
