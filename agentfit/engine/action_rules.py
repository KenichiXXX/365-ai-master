"""Versioned score evidence and persistent, content-free recommendation choices."""
from dataclasses import dataclass
from datetime import date, timedelta, timezone
from pathlib import Path

from agentfit.checkup import (DIMENSION_WEIGHTS, analyze_time_habits, compute_checkup,
                             diagnose_model_mix, tier_for_score)
from agentfit.engine.codex_book import _read_progress, _save_progress
from agentfit.engine.content import action_copy, dimension_tip, label, pool_tip, quest_text
from agentfit.engine.coverage import ASSESSABLE_SIGNALS, SUPPORTED
from agentfit.pricing import classify_model


@dataclass(frozen=True)
class Rule:
    id: str
    dimensions: tuple[str, ...]
    signals: tuple[str, ...]
    days: int
    thresholds: dict


RULES = (
    Rule("model_overuse", ("routing",), ("usage",), 7, {"premium_share_gt": .6}),
    Rule("fast_gap", ("routing",), ("usage",), 7, {"fast_share_lt": .05}),
    Rule("late_night", ("timing",), ("usage",), 7, {"share_gt": .25}),
    Rule("fragmented", ("timing", "leverage"), ("usage",), 7, {"active_hours_gte": 14, "top3_share_lt": .45}),
    Rule("concentrated", ("timing",), ("usage",), 7, {"top3_share_gte": .6}),
    Rule("context_bloat", ("context",), ("compacted", "turn_start"), 14, {"count_gte": 3, "share_gte": .1}),
    Rule("retry", ("context",), ("aborted", "turn_start"), 14, {"turns_gte": 10, "share_gte": .1}),
    Rule("cache", ("context",), ("usage",), 7, {"share_lt": .5}),
)


@dataclass
class EvaluableDimension:
    key: str
    label: str
    score: int | None
    availability: str
    evidence: list[dict]


def evaluate_dimensions(p, coverage: dict | None, locale: str) -> list[EvaluableDimension]:
    if coverage is None:
        coverage = {tool: {"signals": dict.fromkeys(SUPPORTED.get(tool, {"usage"}), "supported")}
                    for tool in p.usage_tools_14d | p.behavior_tools_14d}
    _, saving, mix = diagnose_model_mix(p.scoring_usage_7d, p.scoring_weight_7d)
    _, _, time = analyze_time_habits(p.hourly_histogram_7d)
    legacy, _ = compute_checkup(p.rule_hits(), mix, time, p.cache_hit_rate_7d, saving)
    usage = p.scoring_usage_7d
    tokens = sum(u["tokens"] for u in usage.values())
    costs = sum(u["cost"] for u in usage.values())
    hist = p.hourly_histogram_7d
    records = sum(hist)
    values = {
        "model_overuse": (sum(u["cost"] if costs else u["tokens"] for m, u in usage.items()
                              if classify_model(m) == "premium"), costs or tokens),
        "fast_gap": (sum(u["tokens"] for m, u in usage.items() if classify_model(m) == "fast"), tokens),
        "late_night": (sum(hist[:6]), records),
        "fragmented": (sum(sorted(hist, reverse=True)[:3]), records),
        "concentrated": (sum(sorted(hist, reverse=True)[:3]), records),
        "context_bloat": (p.compactions_14d, p.turns_14d),
        "retry": (p.aborted_14d, p.turns_14d),
        "cache": (p.cache_tokens_7d, p.input_tokens_7d + p.cache_tokens_7d),
    }
    evidence = []
    for rule in RULES:
        sources = p.usage_tools_7d if rule.days == 7 else p.usage_tools_14d | p.behavior_tools_14d
        numerator, denominator = values[rule.id]
        available = bool(sources) and all(any(
            coverage.get(tool, {}).get("signals", {}).get(signal) in ASSESSABLE_SIGNALS
            for tool in sources) for signal in rule.signals)
        evidence.append({
            "rule_id": rule.id, "version": "1", "required_signals": list(rule.signals),
            "window_days": rule.days,
            "start_utc": (p.now - timedelta(days=rule.days)).astimezone(timezone.utc).isoformat(),
            "end_utc": p.now.astimezone(timezone.utc).isoformat(),
            "numerator": numerator if available else None, "denominator": denominator if available else None,
            "availability": "available" if available else "unknown", "missing_policy": "unknown",
            "thresholds": rule.thresholds, "active_hours": sum(v > 0 for v in hist) if rule.id == "fragmented" else None,
            "explanation": action_copy(rule.id, locale), "limitation": action_copy("heuristic", locale),
        })
    result = []
    for dimension in legacy:
        rules = [e for e, r in zip(evidence, RULES) if dimension.key in r.dimensions]
        available = all(e["availability"] == "available" for e in rules)
        result.append(EvaluableDimension(dimension.key, label(dimension.key, locale),
                      dimension.score if available else None,
                      "available" if available else "unknown", rules))
    return result


def overall(dims) -> dict:
    available = [d for d in dims if d.score is not None]
    weight = sum(DIMENSION_WEIGHTS[d.key] for d in available)
    score = int(sum(DIMENSION_WEIGHTS[d.key] * d.score for d in available) / weight + 0.5) if weight else None
    return {"score": score, "tier": tier_for_score(score) if score is not None else None,
            "availability": "available" if len(available) == 4 else "partial" if available else "unavailable",
            "score_version": "1"}


FEEDBACK = ("later", "not_suitable", "never", "completed")
REASONS = ("unclear", "unsupported_tool", "no_project", "not_now")
QUEST_SIGNALS = {"first_edit": "tool_calls", "light_model": "usage", "first_skill": "skill_calls",
                 "parallel": "sidechain", "less_rework": "aborted", "automation": "hook_success",
                 "declutter": "skill_calls"}


def supported_quests(coverage: dict, inventories: dict) -> set[str]:
    result = {quest for quest, signal in QUEST_SIGNALS.items() if any(
        row.get("signals", {}).get(signal) in ASSESSABLE_SIGNALS for row in coverage.values())}
    if inventories:
        result.add("rules_file")
    return result


def assign_action(state: dict, dims, locale: str, today: date, path: Path | None,
                  supported: set[str]) -> dict:
    progress = _read_progress(path) if path is not None else {}
    main = progress.setdefault("main_action", {"assignment": None, "feedback": [], "snoozed": {}, "never": [], "sequence": 0})
    previous = main["assignment"]
    if previous and previous["source"]["kind"] == "quest" and previous["source"]["ref"] in state["passed"]:
        main["assignment"] = previous = None
    # Retire an automatic no-data fallback when assessable logs arrive. Keep
    # deliberate alternatives selected after feedback, including legacy ones.
    if (previous and previous["source"]["kind"] == "pool"
            and previous.get("missing_data_fallback", not main["feedback"])
            and any(d.score is not None for d in dims)):
        main["assignment"] = previous = None
    if previous:
        kind, ref = previous["source"]["kind"], previous["source"]["ref"]
    else:
        candidates = []
        safe_alternative = main.pop("safe_alternative", False)
        if not safe_alternative:
            if state["current"] in supported:
                candidates.append(("quest", state["current"]))
            candidates.extend(("dimension", d.key) for d in sorted(
                [d for d in dims if d.score is not None],
                key=lambda d: (d.score, list(DIMENSION_WEIGHTS).index(d.key))))
        candidates.extend(("pool", ref) for ref in ("privacy_check", "fresh_session", "background_agent"))
        kind, ref = next(((kind, ref) for kind, ref in candidates
                          if f"{kind}:{ref}" not in main["never"]
                          and main["snoozed"].get(f"{kind}:{ref}", "") <= today.isoformat()), ("pool", None))
        if ref is None:
            return {"title": action_copy("none", locale), "why": "", "steps": [], "prompt_for_claude": "",
                    "source": {"kind": "pool", "ref": "none"}, "action_id": None,
                    "rule_id": None, "evidence_summary": "", "limitation": "", "validation_kind": "none"}
        rule_id = f"{kind}:{ref}"
        main["sequence"] = main.get("sequence", 0) + 1
        previous = {"source": {"kind": kind, "ref": ref}, "rule_id": rule_id,
                    "action_id": f"{rule_id}:{main['sequence']}", "assigned_on": today.isoformat(),
                    "missing_data_fallback": kind == "pool" and not safe_alternative
                        and not any(d.score is not None for d in dims)}
        main["assignment"] = previous
        dim = next((d for d in dims if kind == "dimension" and d.key == ref), None)
        previous["evidence"] = [{k: e[k] for k in ("rule_id", "numerator", "denominator", "window_days")}
                                for e in getattr(dim, "evidence", [])]
        if path is not None:
            _save_progress(path, progress)
    text = (quest_text if kind == "quest" else dimension_tip if kind == "dimension" else pool_tip)(ref, locale)
    summary = "; ".join(f"{e['rule_id']}: {e['numerator']}/{e['denominator']} ({e['window_days']}d)"
                        for e in previous.get("evidence", [])) or action_copy("safe" if kind == "pool" else "practice", locale)
    return {"title": text["title"], "why": text["why"], "steps": text["steps"],
            "prompt_for_claude": text["prompt"], "source": {"kind": kind, "ref": ref},
            "action_id": previous["action_id"], "rule_id": previous["rule_id"],
            "evidence_summary": summary, "limitation": action_copy("heuristic" if kind == "dimension" else "practice", locale),
            "validation_kind": "self_report" if kind == "pool" else "structured_observation"}


def action_feedback(path: Path, action_id: str, feedback: str, reason: str | None, today: date) -> bool:
    if feedback not in FEEDBACK or reason is not None and reason not in REASONS:
        return False
    progress = _read_progress(path)
    main = progress.get("main_action", {})
    assignment = main.get("assignment")
    if not assignment or assignment["action_id"] != action_id:
        return False
    rule = assignment["rule_id"]
    if feedback == "never":
        main["never"] = sorted(set(main["never"]) | {rule})
    else:
        main["snoozed"][rule] = (today + timedelta(days=7 if feedback == "not_suitable" else 1)).isoformat()
    main["feedback"].append({"action_id": action_id, "feedback": feedback, "reason": reason, "date": today.isoformat()})
    main["assignment"] = None
    main["safe_alternative"] = feedback != "completed"
    _save_progress(path, progress)
    return True


def reset_preferences(path: Path) -> None:
    progress = _read_progress(path)
    main = progress.get("main_action")
    if main:
        main.update(assignment=None, snoozed={}, never=[], safe_alternative=False)
        _save_progress(path, progress)
