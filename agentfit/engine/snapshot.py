"""Assemble the public, content-free snapshot from local usage logs."""
from datetime import datetime, timedelta, timezone
from pathlib import Path

from agentfit.engine.action_rules import overall, supported_quests
from agentfit.engine.codex_book import (
    badges,
    book_groups,
    daily_rankings,
    daily_tip,
    relevant_updates,
    next_badge,
    streak,
    update_book,
    usage_dates,
    retain_badges,
    _read_progress,
    _save_progress,
)
from agentfit.engine.collectors.base import REGISTRY
from agentfit.engine.collectors.codex import latest_rate_limits
from agentfit.engine.content import first_practice, label, practice_evidence_label, review_labels, practice_calendar_labels
from agentfit.engine.content_pool import load_content
from agentfit.engine.coverage import source_coverage
from agentfit.engine.history import record_history
from agentfit.engine.profile import build_profile, dimensions
from agentfit.engine.scan_state import ScanState
from agentfit.engine.village import advance, evaluate, today_tip, village_block


def build_snapshot(
    home: Path, state_dir: Path, locale: str, now: datetime | None = None,
    enabled: set[str] | None = None, content: Path | None = None,
) -> dict:
    now = now or datetime.now(timezone.utc)
    from agentfit.engine.local_metrics import LocalMetrics
    metrics = LocalMetrics(state_dir, now)
    state = ScanState(state_dir / "scan.json")
    events, tools, collectors = [], [], []
    coverage = {}
    for collector in REGISTRY:
        if enabled is not None and collector.tool not in enabled:
            continue
        row = {"tool": collector.tool, "tier": collector.tier,
               "detected": False, "error": None}
        tools.append(row)
        collected = []
        coverage_error = None
        try:
            row["detected"] = collector.detect(home)
            if row["detected"]:
                collected = collector.scan(home, state)
                events.extend(collected)
        except Exception as exc:
            row["error"] = "unavailable"
            coverage_error = "permission_denied" if isinstance(exc, PermissionError) else "partial"
        coverage[collector.tool] = source_coverage(collector.tool, row["detected"], collected, state, coverage_error)
        collectors.append((collector, row))
    cutoff = now - timedelta(days=30)
    state.prune_before(cutoff)
    state.save()
    pool = load_content(content)
    profile = build_profile([event for event in events if event.dt() >= cutoff], now, prices=pool.get("prices"))
    inventories = {}
    quota = None
    for collector, row in collectors:
        usage = profile.by_tool.get(collector.tool, {})
        row.update(
            usage_today=usage.get("today", {"tokens": 0, "cost_usd": None}),
            usage_7d=usage.get("7d", {"tokens": 0, "cost_usd": None}),
            by_model=usage.get("by_model", []),
        )
        if not row["detected"]:
            continue
        try:
            if collector.tool == "claude_code":
                inventory = collector.inventory(home, profile.project_dirs_14d)
            else:
                inventory = collector.inventory(home)
            if inventory is not None:
                inventories[collector.tool] = inventory
            if collector.tool == "codex" and row["error"] is None:
                quota = latest_rate_limits(home)
                if quota:
                    recorded = quota.get("recorded_at")
                    age = (now - datetime.fromisoformat(recorded)).total_seconds() if recorded else None
                    quota["freshness"] = ("unknown" if age is None else "future" if age < 0 else
                                          "stale" if age > 3600 else "fresh")
        except Exception:
            row["error"] = "unavailable"
    dims = dimensions(profile, coverage, locale)
    assessment = overall(dims)
    score = assessment["score"]
    met = evaluate(profile, inventories, dims)
    progress = advance(met, state_dir / "progress.json", now)
    book = update_book(pool, profile, inventories, state_dir / "progress.json", now, events, coverage)
    for card in book["cards"] + ([book["today"]] if book["today"] else []):
        card["evidence_label"] = practice_evidence_label(card["evidence_kind"], locale)
        for key in ("title", "why", "prompt", "steps", "expected_signal", "limitations"):
            card[key] = card[key][locale]
    today = now.astimezone().date()
    persisted = _read_progress(state_dir / "progress.json")
    profile.active_dates_30d = [day for day in usage_dates(persisted, now)
                               if (today - timedelta(days=29)).isoformat() <= day <= today.isoformat()]
    streak_days = streak(profile.active_dates_30d, today)
    earned_badges = retain_badges(persisted, badges(streak_days, book["lit"], book["total"],
                                                  len(progress["passed"]), locale))
    _save_progress(state_dir / "progress.json", persisted)
    book["practice_calendar"]["labels"] = practice_calendar_labels(locale)
    book["groups"] = book_groups(book["cards"], locale)
    book["next_badge"] = next_badge(streak_days, book["lit"], book["total"],
                                    len(progress["passed"]), locale, persisted["badges"])
    growth, weekly = record_history(
        state_dir / "progress.json", now, score, {d.key: d.score for d in dims},
        profile.active_dates_30d, coverage=coverage, locale=locale,
        price_version=profile.price_estimate["price_version"],
        next_practice=book["today"]["id"] if book["today"] else "review_capability_v1",
    )
    tip = today_tip(progress, dims, locale, today, state_dir / "progress.json",
                    supported_quests(coverage, inventories))
    persisted = _read_progress(state_dir / "progress.json")
    action_id = tip.get("action_id")
    if action_id:
        quest_cards = {"rules_file": "rules_file", "light_model": "light_model",
                       "first_skill": "first_skill", "parallel": "subagent", "automation": "hook"}
        skill_id = quest_cards.get(tip["source"]["ref"], "review_capability_v1")
        card = next((c for c in pool["skills"] + pool.get("review_exercises", []) if c["id"] == skill_id),
                    load_content(None)["review_exercises"][0])
        if tip["source"]["kind"] == "quest" and tip["source"]["ref"] == "first_edit":
            card = {**card, "id": "quest:first_edit", "validator": "edit"}
        from agentfit.engine.practice import validation_available
        automatic = validation_available(card, coverage)
        tip["validation_kind"] = "structured_observation" if automatic else "self_report"
        persisted["practice_actions"] = {action_id: {**card, "content_revision": pool["updated_at"],
                                                   "automatic_supported": automatic}}
        _save_progress(state_dir / "progress.json", persisted)
    notices = [] if any(row["tier"] == "deep" and row["detected"] for row in tools) else ["no_tools"]
    notices.extend(f"regressed:{key}" for key in progress["regressed"])
    from agentfit.engine.content import local_validation_labels
    validation = metrics.summary(persisted, coverage, now)
    validation["labels"] = local_validation_labels(locale)
    return {
        "local_validation": validation,
        "schema": 3, "coverage": coverage, "generated_at": now.isoformat(), "locale": locale,
        "tools": tools, "quota": {"codex": quota},
        "dimensions": [{"key": d.key, "label": d.label, "score": d.score,
                        "availability": d.availability, "evidence": d.evidence} for d in dims],
        "overall": assessment,
        "village": village_block(progress, met, locale, supported_quests(coverage, inventories), persisted.get("practice")),
        "first_practice": first_practice(locale),
        "today_tip": tip,
        "inventory": {tool: inv.to_public() for tool, inv in inventories.items()},
        "book": book,
        "rankings": daily_rankings(pool, inventories, locale, today, n=20),
        "tool_updates": relevant_updates(pool, coverage, locale),
        "growth": growth, "weekly": weekly,
        "daily_tip": daily_tip(pool, locale, today),
        "streak": {"days": streak_days, "label": practice_calendar_labels(locale)["streak"].format(n=streak_days)},
        "badges": earned_badges,
        "usage_summary": {
            "tokens_7d": sum(usage["tokens"] for usage in profile.usage_by_model_7d.values()),
            "cost_usd_7d": profile.total_cost_7d,
            "price_estimate": profile.price_estimate,
            "codex_quota": quota,
            "labels": review_labels(locale),
        },
        "notices": notices,
        "labels": {key: label(key, locale) for key in ("no_tools", "tool_unavailable")},
    }
