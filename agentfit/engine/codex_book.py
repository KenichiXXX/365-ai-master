"""Permanent skill discoveries and deterministic offline daily recommendations."""
from datetime import date, datetime, timedelta
import json
import os
from pathlib import Path
import tempfile

from agentfit.engine.content import badge_title
from agentfit.engine.content_pool import load_content
from agentfit.engine.inventory import Inventory
from agentfit.engine.profile import Profile


def detected(card: dict, p: Profile, inv: dict[str, Inventory]) -> bool | None:
    rule = card["detect"]
    if rule == "self":
        return None
    if rule.startswith("tool:"):
        return p.tool_calls_30d.get(rule.split(":", 1)[1], 0) >= 1
    if rule == "mcp":
        return p.tool_calls_30d.get("mcp", 0) >= 1
    if rule == "skill_any":
        return any(p.skill_calls_30d.values())
    if rule.startswith("effort:"):
        return bool(p.efforts_30d.intersection(rule.split(":", 1)[1].split("|")))
    if rule.startswith("instructions:"):
        tool = {"claude": "claude_code", "codex": "codex"}[rule.split(":", 1)[1]]
        return tool in inv and inv[tool].instructions_bytes > 200
    return {
        "sidechain": p.sidechain_30d >= 1,
        "hook": p.hook_success_30d >= 1,
        "compaction": p.compactions_30d >= 1,
        "light_model": p.light_token_share_30d > 0,
    }.get(rule, False)


def _read_progress(path: Path) -> dict:
    try:
        progress = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        progress = {}
    progress.setdefault("passed", {})
    progress.setdefault("regress_notified", [])
    progress.setdefault("lit", {})
    return progress


def _save_progress(path: Path, progress: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=path.name + ".", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(progress, stream, ensure_ascii=False)
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def update_book(content: dict, p: Profile, inv: dict[str, Inventory],
                progress_path: Path, now: datetime) -> dict:
    progress = _read_progress(progress_path)
    # Persist the active pool's self-report allowlist for the separate CLI command.
    progress["book_self_ids"] = [c["id"] for c in content["skills"] if c["detect"] == "self"]
    lit = progress["lit"]
    cards = []
    for card in content["skills"]:
        if detected(card, p, inv):
            lit.setdefault(card["id"], {"at": now.isoformat(), "how": "log"})
        record = lit.get(card["id"])
        cards.append({
            **{key: card[key] for key in ("id", "title", "why", "prompt", "level")},
            "lit": record is not None, "how": record["how"] if record else None,
        })
    _save_progress(progress_path, progress)
    return {"lit": sum(c["lit"] for c in cards), "total": len(cards), "cards": cards,
            "today": today_skill(cards, now.astimezone().date())}


def today_skill(cards: list[dict], today: date) -> dict:
    candidates = [card for card in cards if not card["lit"]] or cards
    return candidates[today.toordinal() % len(candidates)] if candidates else {}


def mark_tried(card_id: str, progress_path: Path, now: datetime) -> bool:
    progress = _read_progress(progress_path)
    allowed = progress.get("book_self_ids")
    if allowed is None:
        allowed = [c["id"] for c in load_content(None)["skills"] if c["detect"] == "self"]
    if card_id not in allowed:
        return False
    progress["lit"].setdefault(card_id, {"at": now.isoformat(), "how": "self"})
    _save_progress(progress_path, progress)
    return True


def daily_rankings(content: dict, inv: dict[str, Inventory], locale: str,
                   today: date, n: int = 5) -> dict:
    installed = {name.casefold() for item in inv.values()
                 for name in item.skills_installed + item.plugins_installed}
    rankings = content["rankings"]
    result = {key: rankings[key] for key in ("source", "updated_at") if key in rankings}
    for kind in ("skill", "agent"):
        items = rankings[kind]
        offset = today.toordinal() % len(items) if items and rankings.get("rotate", True) else 0
        result[kind] = [
            {"name": item["name"], "url": item["url"], "tagline": item["tagline"][locale],
             "installed": any(name.casefold() in installed for name in item["match"])}
            for item in (items[offset:] + items[:offset])[:n]
        ]
    return result


def daily_tip(content: dict, locale: str, today: date) -> dict:
    tips = content["tips"]
    if not tips:
        return {}
    tip = tips[today.toordinal() % len(tips)]
    return {**tip, "title": tip["title"][locale], "detail": tip["detail"][locale]}


def streak(active_dates: list[str], today: date) -> int:
    active = set(active_dates)
    current = today if today.isoformat() in active else today - timedelta(days=1)
    days = 0
    while current.isoformat() in active:
        days += 1
        current -= timedelta(days=1)
    return days


def badges(streak_days: int, lit: int, total: int, village_passed: int, locale: str) -> list[dict]:
    earned = {f"streak_{n}": streak_days >= n for n in (3, 7, 14, 30)}
    earned.update({f"book_{n}": lit >= n for n in (5, 10, 20)})
    earned.update(book_all=total > 0 and lit >= total, village_done=village_passed >= 9)
    return [{"id": key, "title": badge_title(key, locale), "earned": value}
            for key, value in earned.items()]
