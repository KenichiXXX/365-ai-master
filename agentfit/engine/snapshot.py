"""Assemble the public, content-free snapshot from local usage logs."""
from datetime import datetime, timedelta, timezone
from pathlib import Path

from agentfit.engine.action_rules import overall, supported_quests
from agentfit.engine.codex_book import (
    badges,
    book_groups,
    daily_rankings,
    daily_tip,
    next_badge,
    streak,
    update_book,
)
from agentfit.engine.collectors.base import REGISTRY
from agentfit.engine.collectors.codex import latest_rate_limits
from agentfit.engine.content import first_practice, label
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
    profile = build_profile([event for event in events if event.dt() >= cutoff], now)
    inventories = {}
    quota = None
    for collector, row in collectors:
        usage = profile.by_tool.get(collector.tool, {})
        row.update(
            usage_today=usage.get("today", {"tokens": 0, "cost_usd": 0.0}),
            usage_7d=usage.get("7d", {"tokens": 0, "cost_usd": 0.0}),
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
        except Exception:
            row["error"] = "unavailable"
    dims = dimensions(profile, coverage, locale)
    assessment = overall(dims)
    score = assessment["score"]
    met = evaluate(profile, inventories, dims)
    progress = advance(met, state_dir / "progress.json", now)
    pool = load_content(content)
    book = update_book(pool, profile, inventories, state_dir / "progress.json", now)
    for card in book["cards"]:
        for key in ("title", "why", "prompt"):
            card[key] = card[key][locale]
    today = now.astimezone().date()
    streak_days = streak(profile.active_dates_30d, today)
    book["groups"] = book_groups(book["cards"], locale)
    book["next_badge"] = next_badge(streak_days, book["lit"], book["total"],
                                    len(progress["passed"]), locale)
    growth, weekly = record_history(
        state_dir / "progress.json", now, score, {d.key: d.score for d in dims},
        profile.active_dates_30d,
    )
    notices = [] if any(row["tier"] == "deep" and row["detected"] for row in tools) else ["no_tools"]
    notices.extend(f"regressed:{key}" for key in progress["regressed"])
    return {
        "schema": 3, "coverage": coverage, "generated_at": now.isoformat(), "locale": locale,
        "tools": tools, "quota": {"codex": quota},
        "dimensions": [{"key": d.key, "label": d.label, "score": d.score,
                        "availability": d.availability, "evidence": d.evidence} for d in dims],
        "overall": assessment,
        "village": village_block(progress, met, locale, supported_quests(coverage, inventories)),
        "first_practice": first_practice(locale),
        "today_tip": today_tip(progress, dims, locale, today, state_dir / "progress.json",
                               supported_quests(coverage, inventories)),
        "inventory": {tool: inv.to_public() for tool, inv in inventories.items()},
        "book": book,
        "rankings": daily_rankings(pool, inventories, locale, today, n=20),
        "growth": growth, "weekly": weekly,
        "daily_tip": daily_tip(pool, locale, today),
        "streak": {"days": streak_days},
        "badges": badges(streak_days, book["lit"], book["total"], len(progress["passed"]), locale),
        "usage_summary": {
            "tokens_7d": sum(usage["tokens"] for usage in profile.usage_by_model_7d.values()),
            "cost_usd_7d": profile.total_cost_7d,
            "codex_quota_pct": quota.get("primary_pct") if quota else None,
        },
        "notices": notices,
        "labels": {key: label(key, locale) for key in ("no_tools", "tool_unavailable")},
    }
