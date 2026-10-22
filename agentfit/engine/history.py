"""Versioned daily observations and complete matched-weekday comparisons."""
from datetime import datetime, timedelta
from pathlib import Path
import os
import re
from statistics import mean

from agentfit.engine.codex_book import _read_progress, _save_progress
from agentfit.engine.content import review_labels

SCORE_VERSION = "1"
RULE_VERSION = "1"
LEGACY = "legacy_unknown_version"


def _comparison(history, today, score_version):
    monday = today - timedelta(days=today.weekday())
    days = [monday + timedelta(days=n) for n in range(today.weekday())]
    result = {"window": "matched_completed_weekdays", "current_dates": [d.isoformat() for d in days],
              "previous_dates": [(d - timedelta(days=7)).isoformat() for d in days],
              "score_version": score_version, "reason": None}
    current = [history.get(d, {}) for d in result["current_dates"]]
    previous = [history.get(d, {}) for d in result["previous_dates"]]
    rows = current + previous
    if not rows or any(type(r.get("score")) is not int or not 0 <= r["score"] <= 100 for r in rows):
        result["reason"] = "incomplete_window"
    elif any(r.get("score_version") != score_version or r.get("rule_version") != RULE_VERSION for r in rows):
        result["reason"] = "version_changed"
    if result["reason"]:
        return None, result
    return round(mean(r["score"] for r in current) - mean(r["score"] for r in previous), 2), result


def record_history(progress_path: Path, now: datetime, score: int | None,
                   dims: dict[str, int | None], active_dates: list[str], *, coverage=None,
                   score_version=SCORE_VERSION, price_version="unreviewed-v1", locale="en",
                   next_practice="review_capability_v1") -> tuple[dict, dict]:
    local = now.astimezone()
    today = local.date()
    start = (today - timedelta(days=today.weekday())).isoformat()
    end = today.isoformat()
    progress = _read_progress(progress_path)
    history = progress.setdefault("history", {})
    for row in history.values():
        row.setdefault("score_version", LEGACY)
        row.setdefault("rule_version", LEGACY)
        row.setdefault("coverage", None)
        row.setdefault("timezone", None)
        row.setdefault("price_version", LEGACY)
    # An observation can be unknown. Never carry yesterday's score into today.
    history[end] = {"score": score, "dims": dims, "score_version": score_version,
                    "rule_version": RULE_VERSION, "coverage": coverage or {},
                    "timezone": os.environ.get("TZ") or str(local.tzinfo), "price_version": price_version}
    cutoff = (today - timedelta(days=89)).isoformat()
    history = {day: history[day] for day in sorted(history) if cutoff <= day <= end}
    progress["history"] = history
    _save_progress(progress_path, progress)
    delta, comparison = _comparison(history, today, score_version)
    days = []
    for n in range(29, -1, -1):
        day = (today - timedelta(days=n)).isoformat()
        row = history.get(day, {})
        days.append({"date": day, "score": row.get("score"), "dims": row.get("dims", {}),
                     "score_version": row.get("score_version"), "rule_version": row.get("rule_version"),
                     "coverage": row.get("coverage"), "timezone": row.get("timezone"),
                     "price_version": row.get("price_version")})
    growth = {"days": days, "week_delta": delta, "comparison": comparison,
              "labels": review_labels(locale)}

    def this_week(timestamp):
        try:
            occurred = datetime.fromisoformat(timestamp)
            return occurred <= now and start <= occurred.astimezone().date().isoformat() <= end
        except (ValueError, TypeError):
            return False

    def safe_id(value):
        return isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_:.-]{1,160}", value) is not None

    practice = progress.get("practice", {})
    observations = {key: row for key, row in practice.get("events", {}).items()
                    if safe_id(key) and row.get("kind") == "log_observed"
                    and start <= row.get("local_date", "") <= end and this_week(row.get("occurred_at"))}
    reports = [key for key, row in practice.get("self_reports", {}).items()
               if safe_id(key) and start <= row.get("local_date", "") <= end]
    configured = [key for key, row in practice.get("configurations", {}).items()
                  if safe_id(key) and this_week(row.get("first_seen_at"))]
    # Reuse needs earlier, different-date evidence for the same capability.
    reuse = [key for key, row in observations.items() if any(
        prev.get("kind") == "log_observed" and prev.get("skill_id") == row.get("skill_id")
        and prev.get("local_date", "") < row["local_date"]
        and prev.get("occurred_at", "") < row["occurred_at"]
        for prev in practice.get("events", {}).values())]
    copy = review_labels(locale)
    change = {"text": copy["observed"].format(count=len(observations)) if observations else copy["no_change"],
              "metric_id": "practice.new_observations", "evidence_ids": sorted(observations)}
    uncertainty = {"text": copy["accumulating"] if delta is None else copy["uncertainty"],
                   "reason": comparison["reason"] or "output_quality_unknown"}
    next_practice = next_practice if safe_id(next_practice) else "review_capability_v1"
    next_step = {"text": copy["next_practice"], "practice_id": next_practice}
    report = [change["text"], uncertainty["text"],
              copy["separate"].format(configured=len(configured), self_reported=len(reports), reuse=len(reuse)),
              copy["next_practice"] + ": " + next_practice,
              "practice.new_observations: " + ", ".join(sorted(observations))]
    if delta is not None:
        report.append(copy["delta"].format(delta=f"{delta:+g}"))
    weekly = {"week_start": start, "score_delta": delta, "comparison": comparison,
              "cards_lit_this_week": [key for key, row in progress["lit"].items() if this_week(row["at"])],
              "quests_passed_this_week": [key for key, at in progress["passed"].items() if this_week(at)],
              "days_active": len({day for day in active_dates if start <= day <= end}),
              "observed_change": change, "uncertainty": uncertainty, "next_practice": next_step,
              "self_report_ids": sorted(reports), "configuration_ids": sorted(configured),
              "reuse_evidence_ids": sorted(reuse), "report_text": "\n".join(report)}
    return growth, weekly
