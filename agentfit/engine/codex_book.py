"""Permanent skill discoveries and deterministic offline daily recommendations."""
from datetime import date, datetime, timedelta
import json
import os
from pathlib import Path
import tempfile

from agentfit.engine.content import badge_title, skill_level_title, practice_calendar_labels
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
                progress_path: Path, now: datetime, events=(), coverage=None) -> dict:
    from agentfit.engine.practice import PracticeLedger, compatible, validation_available
    progress = _read_progress(progress_path)
    ledger = PracticeLedger(progress, now)
    skills = [{**c, "content_revision": content["updated_at"]} for c in content["skills"]]
    reviews = [{**c, "content_revision": content["updated_at"]} for c in content.get("review_exercises", [])]
    progress["book_catalog"] = {c["id"]: c for c in skills + reviews}
    progress["book_self_ids"] = [c["id"] for c in skills + reviews
                                 if c["validator"] == "self" or not validation_available(c, coverage or {})]
    ledger.observe(events, skills + reviews, coverage or {}, now)
    lit = progress["lit"]
    cards = []
    for card in skills:
        configuration = card["detect"].startswith("instructions:") and detected(card, p, inv)
        kind = ledger.evidence(card["id"], lit.get(card["id"]))
        if configuration:
            ledger.state.setdefault("configurations", {}).setdefault(card["id"], {
                "kind": "configuration", "first_seen_at": now.isoformat(),
                "content_revision": content["updated_at"], "rule_version": "1"})
            kind = "configuration"
        if card["id"] in ledger.state.get("configurations", {}) and kind in {"ready", "historical"}:
            kind = "configuration"
        if kind in {"log_observed", "reuse", "self_reported"} or detected(card, p, inv):
            how = "configuration" if configuration else "self" if kind == "self_reported" else "log"
            lit.setdefault(card["id"], {"at": now.isoformat(), "how": how})
            if kind == "ready":
                kind = "historical"
        record = lit.get(card["id"])
        cards.append({**card, "lit": record is not None,
                      "how": record["how"] if record else None, "evidence_kind": kind,
                      "automatic_supported": validation_available(card, coverage or {}),
                      "mode": "new"})
    today = now.astimezone().date()
    day = today.isoformat()
    yesterday = (today - timedelta(days=1)).isoformat()
    assignments = progress.setdefault("book_daily", {})
    assignment = assignments.get(day)
    if assignment is None:
        candidates = [c for c in cards if not c["lit"] and c["id"] not in ledger.state["seen"]
                      and (not coverage or compatible(c, coverage))]
        previous = progress.get("book_seen", {}).get(yesterday)
        choice = today_skill(candidates, today, previous)
        mode = "new"
        if not choice:
            available = [c for c in reviews if compatible(c, coverage or {})]
            # No detected tool still permits the bundled manual review exercise.
            if not coverage:
                available = reviews
            choice = available[today.toordinal() % len(available)] if available else None
            mode = "review"
        assignment = {"card": choice, "mode": mode, "skipped": False,
                      "content_revision": content["updated_at"]}
        assignments[day] = assignment
    choice = assignment["card"]
    if choice:
        ledger.seen(choice["id"], now)
        current = next((c for c in cards if c["id"] == choice["id"]), {})
        choice = {**choice, "lit": choice["id"] in lit, "how": lit.get(choice["id"], {}).get("how"),
                  "evidence_kind": ledger.evidence(choice["id"], lit.get(choice["id"])),
                  "automatic_supported": current.get("automatic_supported", False),
                  "mode": assignment["mode"], "content_revision": assignment["content_revision"]}
        if current.get("evidence_kind") == "configuration":
            choice["evidence_kind"] = "configuration"
        progress.setdefault("book_seen", {})[day] = choice["id"]
    yesterday_attempts = [a for a in ledger.attempts
                          if a["started_local_date"] == yesterday
                          and a["stopped_at"] is None]
    tracked = []
    for attempt in yesterday_attempts:
        card = next((c for c in skills + reviews if c["id"] == attempt["skill_id"]), None)
        received = any(e["tool"] in (coverage or {}) and e["first_seen_at"] > attempt["started_at"]
                       and e["occurred_at"] > attempt["started_at"] for e in ledger.state["events"].values())
        status = ("observed" if attempt["first_observed_at"] else "not_yet"
                  if received and card and validation_available(card, coverage or {}) else "coverage_missing")
        tracked.append({"attempt_id": attempt["attempt_id"], "skill_id": attempt["skill_id"],
                        "status": status})
    calendar = practice_calendar(progress, events, now)
    _save_progress(progress_path, progress)
    return {"practice_calendar": calendar, "lit": sum(c["lit"] for c in cards), "total": len(cards), "cards": cards,
            "today": choice, "yesterday": tracked,
            "configuration_count": len(ledger.state.get("configurations", {})),
            "self_report_count": len(ledger.state.get("self_reports", {}))}


def practice_command(card_id: str, operation: str, progress_path: Path, now: datetime) -> bool:
    from agentfit.engine.practice import PracticeLedger
    progress = _read_progress(progress_path)
    ledger = PracticeLedger(progress, now)
    content = load_content(None)
    cards = list(progress.get("book_catalog", {}).values()) or content["skills"] + content.get("review_exercises", [])
    assignments = progress.get("book_daily", {})
    day = now.astimezone().date().isoformat()
    pinned = assignments.get(day, {}).get("card")
    action_card = progress.get("practice_actions", {}).get(card_id)
    card = action_card or (pinned if pinned and pinned["id"] == card_id else next((c for c in cards if c["id"] == card_id), None))
    if operation == "stop":
        ok = ledger.stop(card_id, now)
    elif card is None:
        return False
    elif operation in {"start", "copy"}:
        ledger.start(card, card_id, now)
        ok = True
    elif operation == "self":
        if card["validator"] != "self" and not (card_id in progress.get("book_self_ids", [])
                                                  or card.get("automatic_supported") is False):
            return False
        ok = ledger.self_report(card, now, unsupported=True)
    elif operation == "seen":
        ledger.seen(card_id, now)
        ok = True
    elif operation == "skip":
        assignment = assignments.get(day)
        if not assignment or assignment["skipped"] or not pinned or pinned["id"] != card_id:
            return False
        alternative = next((c for c in cards if c["id"] != card_id
                            and c["id"] not in ledger.state["seen"]), None)
        if alternative is None:
            return False
        assignment.update(card=alternative, skipped=True, content_revision=alternative.get("content_revision", content["updated_at"]))
        ledger.seen(alternative["id"], now)
        ok = True
    else:
        return False
    if ok:
        _save_progress(progress_path, progress)
    return ok


def today_skill(cards: list[dict], today: date, yesterday_id: str | None = None) -> dict:
    unlit = [card for card in cards if not card["lit"]]
    if unlit:
        # Follow the path: finish the lowest unfinished level before moving up.
        lowest = min(card.get("level", 1) for card in unlit)
        unlit = [card for card in unlit if card.get("level", 1) == lowest]
    candidates = unlit or cards
    if not candidates:
        return {}
    index = today.toordinal() % len(candidates)
    if len(unlit) > 1 and candidates[index]["id"] == yesterday_id:
        index = (index + 1) % len(candidates)
    return candidates[index]


def mark_tried(card_id: str, progress_path: Path, now: datetime) -> bool:
    from agentfit.engine.practice import PracticeLedger
    progress = _read_progress(progress_path)
    content = load_content(None)
    cards = list(progress.get("book_catalog", {}).values()) or content["skills"] + content.get("review_exercises", [])
    card = next((c for c in cards if c["id"] == card_id), None)
    if not card or card_id not in progress.get("book_self_ids", [c["id"] for c in content["skills"] if c["validator"] == "self"]):
        return False
    if not PracticeLedger(progress, now).self_report(card, now, unsupported=card_id in progress.get("book_self_ids", [])):
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
    result["origin"] = "cached" if rankings.get("origin") == "public" else "bundled"
    for kind in ("skill", "agent", "product"):
        items = rankings.get(kind, [])
        offset = today.toordinal() % len(items) if items and kind != "product" and rankings.get("rotate", True) else 0
        result[kind] = [
            {**{key: item[key] for key in ("stars", "stars7d", "category", "beginner") if key in item},
             "name": item["name"], "url": item["url"], "tagline": item["tagline"][locale],
             "installation_hint": any(name.casefold() in installed for name in item["match"]),
             "source_url": item.get("source_url", item["url"]), "source_date": item.get("source_date"),
             "source_type": item.get("source_type", "curated"), "task_category": item.get("task_category"),
             "compatibility": item.get("compatibility"),
             "caution": item["caution"][locale] if "caution" in item else None}
            for item in (items[offset:] + items[:offset])[:min(n, 20)]
        ]
    return result


def relevant_updates(content: dict, coverage: dict, locale: str) -> list[dict]:
    result = []
    for item in content.get("tool_updates", []):
        source = coverage.get(item["tool"], {})
        spec = item["compatibility"]
        if (source.get("status") not in {"not_detected", None}
                and source.get("format") == spec["format"]
                and source.get("adapter_version") in spec["adapter_versions"]):
            result.append({**item, "summary": item["summary"][locale]})
    return result


def daily_tip(content: dict, locale: str, today: date) -> dict:
    tips = content["tips"]
    if not tips:
        return {}
    tip = tips[today.toordinal() % len(tips)]
    result = {**tip, "title": tip["title"][locale], "detail": tip["detail"][locale]}
    limitations = tip.get("limitations")
    if isinstance(limitations, dict) and isinstance(limitations.get(locale), str):
        result["limitations"] = limitations[locale]
    else:
        result.pop("limitations", None)
    return result


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


def book_groups(cards: list[dict], locale: str) -> list[dict]:
    groups = []
    for level in (1, 2, 3):
        members = [card for card in cards if card["level"] == level]
        groups.append({"level": level, "title": skill_level_title(level, locale),
                       "lit": sum(card["lit"] for card in members), "total": len(members),
                       "missing": [card["id"] for card in members if not card["lit"]]})
    return groups


def next_badge(streak_days: int, lit: int, total: int, village_passed: int,
               locale: str, earned=()) -> dict | None:
    targets = [(f"streak_{n}", streak_days, n) for n in (3, 7, 14, 30)]
    targets += [(f"book_{n}", lit, n) for n in (5, 10, 20)]
    targets += [("book_all", lit, total), ("village_done", village_passed, 9)]
    unearned = [(key, have, need) for key, have, need in targets if have < need and key not in earned]
    if not unearned:
        return None
    key, have, need = min(unearned, key=lambda row: (row[2] - row[1], row[2]))
    return {"id": key, "title": badge_title(key, locale), "have": have, "need": need}


def practice_calendar(progress, events, now):
    state = progress["practice"]
    # Migrate usage flags without re-attributing the stored occurrence date or timezone.
    for event in events:
        record = state["events"].get(event.identity())
        if record is not None:
            record.setdefault("usage", bool(event.model))
    activity = {}
    for record in state["events"].values():
        if datetime.fromisoformat(record["occurred_at"]) > now:
            continue
        day = activity.setdefault(record["local_date"], set())
        if record["kind"] == "log_observed":
            day.add("observed")
        if record.get("usage"):
            day.add("usage_only")
    reports = list(state.get("self_reports", {}).values()) + list(state.get("self_report_days", {}).values())
    for record in reports:
        if datetime.fromisoformat(record["self_reported_at"]) <= now:
            activity.setdefault(record["local_date"], set()).add("self_reported")
    today = now.astimezone().date()
    days = []
    for offset in range(29, -1, -1):
        day = (today - timedelta(days=offset)).isoformat()
        state = next((kind for kind in ("observed", "self_reported", "usage_only")
                      if kind in activity.get(day, set())), "unavailable")
        days.append({"date": day, "state": state})
    return {"days": days, "labels": practice_calendar_labels("en")}


def usage_dates(progress, now):
    return sorted({row["local_date"] for row in progress.get("practice", {}).get("events", {}).values()
                   if row.get("usage") and datetime.fromisoformat(row["occurred_at"]) <= now})


def retain_badges(progress, current):
    earned = set(progress.get("badges", []))
    earned.update(row["id"] for row in current if row["earned"])
    progress["badges"] = sorted(earned)
    return [{**row, "earned": row["id"] in earned} for row in current]
