"""Consumer-facing explanations of the existing v1 score, without changing it."""
from agentfit.checkup import analyze_time_habits, compute_checkup, diagnose_model_mix
from agentfit.engine.content import checkup_detail_copy, dimension_tip
from agentfit.engine.coverage import ASSESSABLE_SIGNALS, SUPPORTED


def dimension_details(profile, dims, locale, coverage=None):
    copy = checkup_detail_copy(locale)
    _, saving, mix = diagnose_model_mix(profile.scoring_usage_7d, profile.scoring_weight_7d)
    _, _, time = analyze_time_habits(profile.hourly_histogram_7d)
    _, issues = compute_checkup(profile.rule_hits(), mix, time, profile.cache_hit_rate_7d, saving)
    penalties = {
        "routing": [("model_overuse", 40), ("fast_gap", 20)],
        "timing": [("late_night", 25), ("fragmented", 20)],
        "context": [("context_bloat", 35), ("cache", 20), ("retry", 15)],
        "leverage": [("fragmented", 10)],
    }
    issue_rules = {
        "旗舰模型承担了过多常规任务": "model_overuse", "几乎没有使用轻量模型": "fast_gap",
        "深夜高强度使用": "late_night", "全天碎片化使用": "fragmented",
        "会话上下文膨胀": "context_bloat", "无效重试循环": "retry",
    }
    active = {issue_rules.get(issue.title, "cache" if issue.title.startswith("缓存命中率仅") else ""): issue
              for issue in issues}
    result = []
    for dim in dims:
        deductions = []
        steps = []
        for rule, points in penalties[dim.key]:
            if dim.score is not None and active.get(rule):
                title, fixes = copy[rule]
                deductions.append({"title": title, "points": points})
                steps.extend(fixes)
        rows = []
        for evidence in dim.evidence:
            rule = evidence["rule_id"]
            copy_key = rule
            if rule == "model_overuse" and not sum(u["cost"] for u in profile.scoring_usage_7d.values()):
                copy_key = "premium_tokens"
            title, target = copy["evidence"][copy_key]
            n, d = evidence["numerator"], evidence["denominator"]
            if n is None or d is None:
                value = "—"
            elif rule in ("context_bloat", "retry"):
                value = f"{n:,} / {d:,}"
            elif rule == "concentrated":
                value = str(sum(v > 0 for v in profile.hourly_histogram_7d))
            else:
                value = f"{n / d:.0%}" if d else "—"
            rows.append({**evidence, "label": title, "value": value, "target": target})
        if dim.key == "leverage":
            sources = profile.usage_tools_14d | profile.behavior_tools_14d
            skill_counts_available = any(
                (coverage.get(tool, {}).get("signals", {}).get("skill_calls") in ASSESSABLE_SIGNALS
                 if coverage is not None else "skill_calls" in SUPPORTED.get(tool, set()))
                for tool in sources)
            rows.append({"label": copy["evidence"]["reuse"][0],
                         "value": str(sum(profile.skill_calls_14d.values())) if skill_counts_available else "—"})
        base = {"routing": 95, "timing": 95 if time["concentrated"] else 90,
                "context": 95, "leverage": 85}[dim.key]
        verdict = deductions[0]["title"] if deductions else copy["healthy"]
        result.append({
            "key": dim.key, "label": dim.label, "score": dim.score,
            "availability": dim.availability, "base": base, "evidence": rows,
            "deductions": deductions, "verdict": verdict if dim.score is not None else copy["unknown"],
            "steps": list(dict.fromkeys(steps))[:3] or [copy["keep"] if dim.score is not None else copy["unknown"]],
            "prompt": dimension_tip(dim.key, locale)["prompt"] if dim.score is not None else "",
        })
    return result
