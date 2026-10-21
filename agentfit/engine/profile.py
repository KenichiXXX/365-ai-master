"""Deduplicated usage and behavior windows for local checkups."""
from collections import Counter
from dataclasses import dataclass, field, replace
from datetime import datetime, timedelta

from agentfit.engine.events import CompactEvent
from agentfit.pricing import TIER_PRICES, classify_model
from agentfit.engine.prices import estimate


@dataclass
class Profile:
    now: datetime
    usage_by_model_7d: dict[str, dict] = field(default_factory=dict)
    hourly_histogram_7d: list[int] = field(default_factory=lambda: [0] * 24)
    cache_hit_rate_7d: float | None = None
    total_cost_7d: float | None = None
    price_estimate: dict = field(default_factory=dict)
    # Frozen v1 score weights, never a public USD estimate.
    scoring_usage_7d: dict[str, dict] = field(default_factory=dict)
    scoring_weight_7d: float = 0.0
    by_tool: dict[str, dict] = field(default_factory=dict)
    tool_calls_14d: dict[str, int] = field(default_factory=dict)
    skill_calls_14d: dict[str, int] = field(default_factory=dict)
    sidechain_14d: int = 0
    turns_14d: int = 0
    aborted_14d: int = 0
    compactions_14d: int = 0
    hook_success_14d: int = 0
    light_token_share_14d: float = 0.0
    project_dirs_14d: set[str] = field(default_factory=set)

    tool_calls_30d: dict[str, int] = field(default_factory=dict)
    skill_calls_30d: dict[str, int] = field(default_factory=dict)
    sidechain_30d: int = 0
    hook_success_30d: int = 0
    compactions_30d: int = 0
    light_token_share_30d: float = 0.0
    efforts_30d: set[str] = field(default_factory=set)
    active_dates_30d: list[str] = field(default_factory=list)

    usage_tools_7d: set[str] = field(default_factory=set)
    usage_tools_14d: set[str] = field(default_factory=set)
    behavior_tools_14d: set[str] = field(default_factory=set)
    input_tokens_7d: int = 0
    cache_tokens_7d: int = 0

    def rule_hits(self) -> dict[str, bool]:
        return {
            "RULE_CONTEXT_BLOAT": (
                self.compactions_14d >= 3
                and self.compactions_14d / max(self.turns_14d, 1) >= 0.10
            ),
            "RULE_ERROR_RETRY_LOOP": (
                self.turns_14d >= 10 and self.aborted_14d / self.turns_14d >= 0.10
            ),
        }


def event_cost(e: CompactEvent, prices=None) -> float | None:
    return estimate([e], prices)["total_usd"]


def _scoring_weight(e: CompactEvent) -> float:
    """Retain v1 arithmetic independently of reviewed public price changes."""
    p_in, p_out, p_cache = TIER_PRICES[classify_model(e.model)]
    return (e.input * p_in + e.output * p_out + e.cache_read * p_cache) / 1e6


def _dedupe(events: list[CompactEvent]) -> list[CompactEvent]:
    merged: dict[tuple[str, str], CompactEvent] = {}
    for event in events:
        key = (event.tool, event.key)
        previous = merged.get(key)
        if previous is None:
            merged[key] = replace(
                event, tool_calls=dict(event.tool_calls), skill_calls=dict(event.skill_calls)
            )
            continue
        chosen = event if event.output > previous.output else previous
        merged[key] = replace(
            chosen,
            tool_calls=dict(Counter(previous.tool_calls) | Counter(event.tool_calls)),
            skill_calls=dict(Counter(previous.skill_calls) | Counter(event.skill_calls)),
            markers=previous.markers | event.markers,
            sidechain=previous.sidechain or event.sidechain,
            effort=chosen.effort or previous.effort or event.effort,
            turn_start=max(previous.turn_start, event.turn_start),
            aborted=max(previous.aborted, event.aborted),
            compacted=max(previous.compacted, event.compacted),
            hook_success=max(previous.hook_success, event.hook_success),
            cwd=chosen.cwd or previous.cwd or event.cwd,
        )
    return list(merged.values())


def build_profile(events: list[CompactEvent], now: datetime, prices=None) -> Profile:
    profile = Profile(now=now)
    cutoff_7d = now - timedelta(days=7)
    cutoff_14d = now - timedelta(days=14)
    cutoff_30d = now - timedelta(days=30)
    today = now.astimezone().date()
    tool_calls: Counter[str] = Counter()
    skill_calls: Counter[str] = Counter()
    all_tokens = fast_tokens = input_tokens = cache_tokens = 0
    tool_models: dict[str, dict[str, dict]] = {}
    calls_30d: Counter[str] = Counter()
    skills_30d: Counter[str] = Counter()
    tokens_30d = fast_30d = 0
    active_dates: set[str] = set()

    priced_events = []
    tool_events = {}
    seen_markers: set[tuple[str, str]] = set()
    for event in _dedupe(events):
        if event.markers:
            fresh = {k: v for k, v in event.markers.items() if (event.tool, k) not in seen_markers}
            seen_markers.update((event.tool, k) for k in event.markers)
            event = replace(event, tool_calls=dict(Counter(v for v in fresh.values() if not v.startswith("skill:"))),
                            skill_calls=dict(Counter(v[6:] for v in fresh.values() if v.startswith("skill:"))))
        timestamp = event.dt()
        if timestamp < cutoff_30d or timestamp > now:
            continue
        calls_30d.update(event.tool_calls)
        skills_30d.update(event.skill_calls)
        profile.sidechain_30d += int(event.sidechain)
        profile.hook_success_30d += event.hook_success
        profile.compactions_30d += event.compacted
        if event.effort:
            profile.efforts_30d.add(event.effort)
        if event.model:
            active_dates.add(timestamp.astimezone().date().isoformat())
            tokens = event.input + event.output
            tokens_30d += tokens
            if classify_model(event.model) == "fast":
                fast_30d += tokens
        if timestamp < cutoff_14d:
            continue
        tool_calls.update(event.tool_calls)
        skill_calls.update(event.skill_calls)
        profile.sidechain_14d += int(event.sidechain)
        if event.turn_start or event.aborted or event.compacted:
            profile.behavior_tools_14d.add(event.tool)
        profile.turns_14d += event.turn_start
        profile.aborted_14d += event.aborted
        profile.compactions_14d += event.compacted
        profile.hook_success_14d += event.hook_success
        if event.cwd:
            profile.project_dirs_14d.add(event.cwd)
        if not event.model or event.input + event.output + event.cache_read + event.cache_write <= 0:
            continue
        profile.usage_tools_14d.add(event.tool)
        tokens = event.input + event.output
        all_tokens += tokens
        if classify_model(event.model) == "fast":
            fast_tokens += tokens
        if timestamp < cutoff_7d:
            continue

        profile.usage_tools_7d.add(event.tool)
        priced_events.append(event)
        tool_events.setdefault(event.tool, []).append(event)
        cost = _scoring_weight(event)
        usage = profile.scoring_usage_7d.setdefault(
            event.model, {"tokens": 0, "cost": 0.0, "requests": 0}
        )
        usage["tokens"] += tokens
        usage["cost"] += cost
        usage["requests"] += 1
        local_time = timestamp.astimezone()
        profile.hourly_histogram_7d[local_time.hour] += 1
        input_tokens += event.input
        cache_tokens += event.cache_read
        profile.scoring_weight_7d += cost

        tool_usage = profile.by_tool.setdefault(event.tool, {
            "today": {"tokens": 0},
            "7d": {"tokens": 0},
            "by_model": [],
        })
        tool_usage["7d"]["tokens"] += tokens
        if local_time.date() == today:
            tool_usage["today"]["tokens"] += tokens
        model_usage = tool_models.setdefault(event.tool, {}).setdefault(
            event.model, {"model": event.model, "tokens": 0}
        )
        model_usage["tokens"] += tokens

    profile.input_tokens_7d = input_tokens
    profile.cache_tokens_7d = cache_tokens
    profile.tool_calls_30d = dict(calls_30d)
    profile.skill_calls_30d = dict(skills_30d)
    profile.active_dates_30d = sorted(active_dates)
    profile.light_token_share_30d = fast_30d / tokens_30d if tokens_30d else 0.0
    profile.tool_calls_14d = dict(tool_calls)
    profile.skill_calls_14d = dict(skill_calls)
    profile.light_token_share_14d = round(fast_tokens / all_tokens, 4) if all_tokens else 0.0
    if input_tokens + cache_tokens:
        profile.cache_hit_rate_7d = cache_tokens / (input_tokens + cache_tokens)
    profile.scoring_weight_7d = round(profile.scoring_weight_7d, 6)
    for usage in profile.scoring_usage_7d.values():
        usage["cost"] = round(usage["cost"], 6)
    profile.price_estimate = estimate(priced_events, prices)
    profile.total_cost_7d = profile.price_estimate["total_usd"]
    for model, usage in profile.scoring_usage_7d.items():
        profile.usage_by_model_7d[model] = {**usage, "cost": estimate(
            [e for e in priced_events if e.model == model], prices)["total_usd"]}
    for tool, usage in profile.by_tool.items():
        usage["by_model"] = sorted(
            tool_models[tool].values(), key=lambda item: (-item["tokens"], item["model"])
        )
        for key in ("today", "7d"):
            subset = [e for e in tool_events[tool] if key == "7d" or e.dt().astimezone().date() == today]
            usage[key]["price_estimate"] = estimate(subset, prices)
            usage[key]["cost_usd"] = usage[key]["price_estimate"]["total_usd"]
        for row in usage["by_model"]:
            row["price_estimate"] = estimate([e for e in tool_events[tool] if e.model == row["model"]], prices)
            row["cost_usd"] = row["price_estimate"]["total_usd"]
    return profile


def dimensions(p: Profile, coverage: dict | None = None, locale: str = "en"):
    from agentfit.engine.action_rules import evaluate_dimensions
    return evaluate_dimensions(p, coverage, locale)
