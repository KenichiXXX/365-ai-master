"""Bounded installation diagnostics. CLI callers hold engine.lock."""
from collections import Counter
from datetime import date, datetime, timedelta, timezone
import json

from agentfit.engine.codex_book import _save_progress

EVENTS = {
    "first_launch": "installation", "measurement_start": "installation",
    "foreground_open": "installation", "share_preview": "share_card",
    "share_copy": "share_card", "share_save": "share_card", "feedback_copy": "feedback",
    "trial_start": "entitlement", "activation": "entitlement", "renewal": "entitlement",
    "checkout_return": "entitlement",
}
RESULTS = {"ok", "imported_verified", "active", "expired", "pending", "unavailable", "revoked"}


def parse(value):
    try:
        at = datetime.fromisoformat(value)
        return at if at.tzinfo else None
    except (TypeError, ValueError):
        return None


def window_start(now):
    return (now.astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
            - timedelta(days=89)).astimezone(timezone.utc)


def valid_state(state):
    if not isinstance(state, dict) or not parse(state.get("measurement_start")):
        return False
    try:
        if state["installation_date"] is not None:
            date.fromisoformat(state["installation_date"])
        return (state["activation_status"] in RESULTS and state["renewal_status"] in RESULTS
                and isinstance(state["events"], list) and isinstance(state["expired_counts"], dict)
                and all(name in EVENTS and isinstance(count, int) and count >= 0
                        for name, count in state["expired_counts"].items())
                and all(isinstance(row, dict) and set(row) == {"name", "object_id", "utc", "local_date", "result"}
                        and row["name"] in EVENTS and row["object_id"] == EVENTS[row["name"]]
                        and row["result"] in RESULTS and parse(row["utc"])
                        and date.fromisoformat(row["local_date"])
                        for row in state["events"]))
    except (KeyError, TypeError, ValueError):
        return False


class LocalMetrics:
    def __init__(self, state_dir, now):
        self.path = state_dir / "local_metrics.json"
        reset = False
        try:
            self.state = json.loads(self.path.read_text(encoding="utf-8"))
            if not valid_state(self.state):
                raise ValueError("invalid local metrics")
        except (FileNotFoundError, ValueError):
            reset = self.path.exists()
            existing = any(p.name != "engine.lock" for p in state_dir.iterdir()) if state_dir.exists() else False
            self.state = {"measurement_start": now.astimezone(timezone.utc).isoformat(),
                          "installation_date": None if existing else now.astimezone().date().isoformat(),
                          "events": [], "expired_counts": {}, "activation_status": "unavailable",
                          "renewal_status": "unavailable", "measurement_reset": reset}
            self.record("measurement_start" if existing else "first_launch", now)

    def record(self, name, now, result="ok"):
        if name not in EVENTS or result not in RESULTS:
            raise ValueError("unreviewed local event")
        self.prune(now)
        day = now.astimezone().date().isoformat()
        if name == "trial_start" and self.count(name, lifetime=True):
            return
        if not any(row["name"] == name and row["local_date"] == day and row["result"] == result
                   for row in self.state["events"]):
            self.state["events"].append({"name": name, "object_id": EVENTS[name],
                                         "utc": now.astimezone(timezone.utc).isoformat(),
                                         "local_date": day, "result": result})
        if name in {"activation", "renewal"}:
            self.state[name + "_status"] = result
        self.prune(now)
        _save_progress(self.path, self.state)

    def count(self, name, lifetime=False):
        return sum(row["name"] == name for row in self.state["events"]) + (
            self.state["expired_counts"].get(name, 0) if lifetime else 0)

    def prune(self, now):
        cutoff = window_start(now)
        rows = self.state["events"]
        kept = [row for row in rows if parse(row["utc"]) and parse(row["utc"]) >= cutoff]
        expired = [row for row in rows if row not in kept]
        if len(kept) > 2048:
            expired += kept[:-2048]
            kept = kept[-2048:]
        counters = Counter(self.state["expired_counts"])
        counters.update(row["name"] for row in expired)
        self.state.update(events=kept, expired_counts=dict(counters))

    def summary(self, progress, coverage, now):
        self.prune(now)
        _save_progress(self.path, self.state)
        start = max(parse(self.state["measurement_start"]), window_start(now))
        in_window = lambda value: (at := parse(value)) is not None and start <= at <= now
        practice = progress.get("practice", {})
        attempts = [a for a in practice.get("attempts", []) if in_window(a.get("started_at"))]
        events = [e for e in practice.get("events", {}).values()
                  if e.get("kind") == "log_observed" and in_window(e.get("occurred_at"))
                  and in_window(e.get("first_seen_at"))]
        observed_ids = {e.get("attempt_id") for e in events}
        observed = sum(a.get("attempt_id") in observed_ids for a in attempts)
        days_by_skill = {}
        for event in events:
            days_by_skill.setdefault(event["skill_id"], set()).add(event["local_date"])
        reused = sum(len(days) >= 2 for days in days_by_skill.values())
        practice_days = {e["local_date"] for e in events}
        foreground = {row["local_date"] for row in self.state["events"]
                      if row["name"] == "foreground_open" and in_window(row["utc"])}
        installation = self.state["installation_date"]
        def returning(offset):
            result = {"status": "unknown_installation", "denominator": 0, "foreground": 0, "practice": 0}
            if not installation:
                return result
            target = (datetime.fromisoformat(installation).date() + timedelta(days=offset)).isoformat()
            if target > now.astimezone().date().isoformat():
                result["status"] = "not_yet"
            elif target < start.astimezone().date().isoformat():
                result["status"] = "outside_window"
            else:
                result.update(status="observed", denominator=1, foreground=int(target in foreground),
                              practice=int(target in practice_days))
            return result
        self_reported = sum(in_window(a.get("self_reported_at")) for a in attempts)
        return {"first_practice_funnel": {"denominator": 1, "started": int(bool(attempts)),
                                          "observed": int(observed > 0), "self_reported": int(self_reported > 0),
                                          "reused": int(reused > 0)},
                "reuse_rate": {"numerator": reused, "denominator": len(days_by_skill)},
                "measurement_reset": self.state.get("measurement_reset", False),
                "cohort": "new_installation" if installation else "post_upgrade",
                "installation_date": installation, "measurement_start": self.state["measurement_start"],
                "window_start": start.isoformat(), "window_end": now.isoformat(), "window_days": 90,
                "truncated": bool(self.state["expired_counts"]), "expired_counts": self.state["expired_counts"],
                "counts": dict(Counter(row["name"] for row in self.state["events"] if in_window(row["utc"]))),
                "funnel": {"attempts": len(attempts), "observed": observed,
                           "self_reported": self_reported,
                           "reused": reused},
                "observation_rate": {"numerator": observed, "denominator": len(attempts)},
                "d1": returning(1), "d7": returning(7),
                "unsupported_sources": sum(row.get("status") != "ok" for row in coverage.values()),
                "source_denominator": len(coverage),
                "trial_starts": self.count("trial_start", lifetime=True),
                "activation_status": self.state["activation_status"],
                "renewal_status": self.state["renewal_status"], "paid_purchases": None}
