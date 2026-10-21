"""Sequential newbie quests, permanent progress and offline daily tips."""
from datetime import date, datetime
import json
import os
from pathlib import Path
import tempfile

from agentfit.engine.content import (
    POOL, QUESTS, dimension_tip, pool_tip, quest_text, rank_title,
)
from agentfit.engine.inventory import Inventory
from agentfit.engine.profile import Profile
from agentfit.models.checkup import DimensionScore


_DIMENSION_ORDER = ("routing", "timing", "context", "leverage")


def evaluate(
    p: Profile, inv: dict[str, Inventory], dims: list[DimensionScore],
) -> dict[str, tuple[bool, str]]:
    installed = {name for item in inv.values() for name in item.skills_installed}
    used = {
        name for name in installed
        if any(key == name or key.split(":")[-1] == name for key in p.skill_calls_14d)
    }
    conditions = {
        "first_edit": sum(p.tool_calls_14d.get(k, 0) for k in ("Edit", "Write", "apply_patch")) >= 1,
        "rules_file": max((item.instructions_bytes for item in inv.values()), default=0) > 200,
        "light_model": p.light_token_share_14d > 0.05,
        "first_skill": any(count >= 3 for count in p.skill_calls_14d.values()),
        "parallel": p.sidechain_14d >= 1,
        "less_rework": (
            p.turns_14d >= 10 and p.aborted_14d / p.turns_14d < 0.10
            and not p.rule_hits()["RULE_ERROR_RETRY_LOOP"]
        ),
        "automation": sum(item.hooks for item in inv.values()) >= 1 and p.hook_success_14d >= 1,
        "declutter": not installed or len(used) / len(installed) >= 0.5,
        "graduate": all(d.score >= 85 for d in dims),
    }
    return {
        key: (met, "" if met else "need_data" if key == "less_rework" and p.turns_14d < 10 else "not_yet")
        for key, met in conditions.items()
    }


def advance(met: dict[str, tuple[bool, str]], progress_path: Path, now: datetime) -> dict:
    try:
        progress = json.loads(progress_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        progress = {"passed": {}, "regress_notified": []}
    passed = progress["passed"]
    notified = progress["regress_notified"]
    regressed = [key for key in QUESTS if key in passed and not met[key][0] and key not in notified]
    notified.extend(regressed)
    current = None
    for key in QUESTS:
        if key in passed:
            continue
        if not met[key][0]:
            current = key
            break
        passed[key] = now.isoformat()

    progress_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=progress_path.parent,
            prefix=progress_path.name + ".", suffix=".tmp", delete=False,
        ) as stream:
            temporary = Path(stream.name)
            json.dump(progress, stream, ensure_ascii=False)
        os.replace(temporary, progress_path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return {"passed": passed, "current": current, "regressed": regressed}


def today_tip(state: dict, dims: list[DimensionScore], locale: str, today: date) -> dict:
    """Select a tip; advance() guarantees that current is unmet or None."""
    if state["current"] is not None:
        kind, ref = "quest", state["current"]
        text = quest_text(ref, locale)
    else:
        lowest = min(
            dims, key=lambda d: (d.score, _DIMENSION_ORDER.index(d.key)), default=None,
        )
        if lowest is not None and lowest.score < 85:
            kind, ref = "dimension", lowest.key
            text = dimension_tip(ref, locale)
        else:
            kind, ref = "pool", POOL[today.toordinal() % len(POOL)]
            text = pool_tip(ref, locale)
    return {
        "title": text["title"], "why": text["why"], "steps": text["steps"],
        "prompt_for_claude": text["prompt"], "source": {"kind": kind, "ref": ref},
    }


def village_block(state: dict, met: dict, locale: str) -> dict:
    passed, current = state["passed"], state["current"]
    return {
        "current": current,
        "rank_title": rank_title(len(passed), locale),
        "quests": [
            {
                "key": key, "title": quest_text(key, locale)["title"],
                "status": "passed" if key in passed else "current" if key == current else "locked",
                "passed_at": passed.get(key), "progress_hint": met[key][1],
            }
            for key in QUESTS
        ],
    }
