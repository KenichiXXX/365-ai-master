"""Deduplicated usage and behavior windows for local checkups."""
from collections import Counter
from dataclasses import dataclass, field, replace
from datetime import datetime, timedelta

from agentfit.checkup import analyze_time_habits, compute_checkup, diagnose_model_mix
from agentfit.engine.events import CompactEvent
from agentfit.models.checkup import DimensionScore
from agentfit.pricing import TIER_PRICES, classify_model


@dataclass
class Profile:
    now: datetime
    usage_by_model_7d: dict[str, dict] = field(default_factory=dict)
    hourly_histogram_7d: list[int] = field(default_factory=lambda: [0] * 24)
    cache_hit_rate_7d: float | None = None
    total_cost_7d: float = 0.0
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


def event_cost(e: CompactEvent) -> float:
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
            tool_calls=dict(Counter(previous.tool_calls) + Counter(event.tool_calls)),
            skill_calls=dict(Counter(previous.skill_calls) + Counter(event.skill_calls)),
            sidechain=previous.sidechain or event.sidechain,
            turn_start=previous.turn_start + event.turn_start,
            aborted=previous.aborted + event.aborted,
            compacted=previous.compacted + event.compacted,
            hook_success=previous.hook_success + event.hook_success,
            cwd=chosen.cwd or previous.cwd or event.cwd,
        )
    return list(merged.values())


def build_profile(events: list[CompactEvent], now: datetime) -> Profile:
    profile = Profile(now=now)
    cutoff_7d = now - timedelta(days=7)
    cutoff_14d = now - timedelta(days=14)
    today = now.astimezone().date()
    tool_calls: Counter[str] = Counter()
    skill_calls: Counter[str] = Counter()
    all_tokens = fast_tokens = input_tokens = cache_tokens = 0
    tool_models: dict[str, dict[str, dict]] = {}

    for event in _dedupe(events):
        timestamp = event.dt()
        if timestamp < cutoff_14d:
            continue
        tool_calls.update(event.tool_calls)
        skill_calls.update(event.skill_calls)
        profile.sidechain_14d += int(event.sidechain)
        profile.turns_14d += event.turn_start
        profile.aborted_14d += event.aborted
        profile.compactions_14d += event.compacted
        profile.hook_success_14d += event.hook_success
        if event.cwd:
            profile.project_dirs_14d.add(event.cwd)
        if not event.model:
            continue
        tokens = event.input + event.output
        all_tokens += tokens
        if classify_model(event.model) == "fast":
            fast_tokens += tokens
        if timestamp < cutoff_7d:
            continue

        cost = event_cost(event)
        usage = profile.usage_by_model_7d.setdefault(
            event.model, {"tokens": 0, "cost": 0.0, "requests": 0}
        )
        usage["tokens"] += tokens
        usage["cost"] += cost
        usage["requests"] += 1
        local_time = timestamp.astimezone()
        profile.hourly_histogram_7d[local_time.hour] += 1
        input_tokens += event.input
        cache_tokens += event.cache_read
        profile.total_cost_7d += cost

        tool_usage = profile.by_tool.setdefault(event.tool, {
            "today": {"tokens": 0, "cost_usd": 0.0},
            "7d": {"tokens": 0, "cost_usd": 0.0},
            "by_model": [],
        })
        tool_usage["7d"]["tokens"] += tokens
        tool_usage["7d"]["cost_usd"] += cost
        if local_time.date() == today:
            tool_usage["today"]["tokens"] += tokens
            tool_usage["today"]["cost_usd"] += cost
        model_usage = tool_models.setdefault(event.tool, {}).setdefault(
            event.model, {"model": event.model, "tokens": 0, "cost_usd": 0.0}
        )
        model_usage["tokens"] += tokens
        model_usage["cost_usd"] += cost

    profile.tool_calls_14d = dict(tool_calls)
    profile.skill_calls_14d = dict(skill_calls)
    profile.light_token_share_14d = round(fast_tokens / all_tokens, 4) if all_tokens else 0.0
    if input_tokens + cache_tokens:
        profile.cache_hit_rate_7d = cache_tokens / (input_tokens + cache_tokens)
    profile.total_cost_7d = round(profile.total_cost_7d, 6)
    for usage in profile.usage_by_model_7d.values():
        usage["cost"] = round(usage["cost"], 6)
    for tool, usage in profile.by_tool.items():
        usage["by_model"] = sorted(
            tool_models[tool].values(), key=lambda item: (-item["tokens"], item["model"])
        )
        for row in [usage["today"], usage["7d"], *usage["by_model"]]:
            row["cost_usd"] = round(row["cost_usd"], 6)
    return profile


def dimensions(p: Profile) -> list[DimensionScore]:
    _, saving, mix_flags = diagnose_model_mix(p.usage_by_model_7d, p.total_cost_7d)
    _, _, time_flags = analyze_time_habits(p.hourly_histogram_7d)
    scores, _ = compute_checkup(
        p.rule_hits(), mix_flags, time_flags, p.cache_hit_rate_7d, saving
    )
    return scores
