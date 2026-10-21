"""Local daily scores and calendar-week progress summaries."""
from datetime import datetime, timedelta
from pathlib import Path

from agentfit.engine.codex_book import _read_progress, _save_progress


def record_history(progress_path: Path, now: datetime, score: int,
                   dims: dict[str, int], active_dates: list[str]) -> tuple[dict, dict]:
    today = now.astimezone().date()
    week_start = today - timedelta(days=today.weekday())
    previous_start = (week_start - timedelta(days=7)).isoformat()
    start = week_start.isoformat()
    end = today.isoformat()
    progress = _read_progress(progress_path)
    history = progress.setdefault("history", {})
    history[end] = {"score": score, "dims": dims}
    cutoff = (today - timedelta(days=89)).isoformat()
    history = {day: history[day] for day in sorted(history) if cutoff <= day <= end}
    progress["history"] = history
    _save_progress(progress_path, progress)
    previous = [record["score"] for day, record in history.items() if previous_start <= day < start]
    delta = score - previous[-1] if previous else None
    growth = {"days": [{"date": day, "score": record["score"]}
                       for day, record in history.items()
                       if day >= (today - timedelta(days=29)).isoformat()],
              "week_delta": delta}

    def this_week(timestamp: str) -> bool:
        day = datetime.fromisoformat(timestamp).astimezone().date().isoformat()
        return start <= day <= end

    weekly = {"week_start": start, "score_delta": delta,
              "cards_lit_this_week": [key for key, record in progress["lit"].items() if this_week(record["at"])],
              "quests_passed_this_week": [key for key, at in progress["passed"].items() if this_week(at)],
              "days_active": len({day for day in active_dates if start <= day <= end})}
    return growth, weekly
