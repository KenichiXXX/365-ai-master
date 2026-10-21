"""Local content-free evidence and attempt attribution. Caller holds engine.lock."""
from datetime import datetime, timezone
import os

from agentfit.engine.coverage import FORMATS
from agentfit.pricing import classify_model


def utc(at):
    return at.astimezone(timezone.utc).isoformat()


def compatible(card, coverage):
    return any(tool in card["compatibility"] and row.get("format") == card["compatibility"][tool]["format"]
               and row.get("adapter_version") in card["compatibility"][tool]["adapter_versions"]
               for tool, row in coverage.items())


def validation_available(card, coverage):
    rule = card["validator"]
    if rule == "self":
        return False
    signal = ("tool_calls" if rule.startswith("tool:") or rule in {"mcp", "edit"} else
              "skill_calls" if rule == "skill_any" else
              {"sidechain": "sidechain", "hook": "hook_success", "compaction": "compacted",
               "light_model": "usage", "effort": "usage"}.get(rule.split(":")[0]))
    return any(compatible(card, {tool: row}) and row.get("status") == "ok"
               and row.get("signals", {}).get(signal) == "available"
               for tool, row in coverage.items())


def qualifying(card, event, coverage):
    row = coverage.get(event.tool, {})
    if not compatible(card, {event.tool: row}):
        return False
    rule = card["validator"]
    signal = ("tool_calls" if rule.startswith("tool:") or rule in {"mcp", "edit"} else
              "skill_calls" if rule == "skill_any" else
              {"sidechain": "sidechain", "hook": "hook_success", "compaction": "compacted",
               "light_model": "usage"}.get(rule))
    if signal and row.get("signals", {}).get(signal) != "available":
        return False
    if rule == "edit":
        return any(event.tool_calls.get(name, 0) > 0 for name in ("Edit", "Write", "apply_patch"))
    if rule.startswith("tool:"):
        return event.tool_calls.get(rule.split(":", 1)[1], 0) > 0
    if rule.startswith("effort:"):
        return row.get("status") == "ok" and event.effort in rule.split(":", 1)[1].split("|")
    return {"mcp": event.tool_calls.get("mcp", 0) > 0,
            "skill_any": any(event.skill_calls.values()), "sidechain": event.sidechain,
            "hook": event.hook_success > 0, "compaction": event.compacted > 0,
            "light_model": bool(event.model and classify_model(event.model) == "fast"
                                and event.input + event.output > 0)}.get(rule, False)


class PracticeLedger:
    def __init__(self, progress, now):
        self.state = progress.setdefault("practice", {"version": 1, "events": {}, "attempts": [], "seen": {}})
        self.attempts = self.state["attempts"]

    def seen(self, card_id, now):
        self.state["seen"].setdefault(card_id, utc(now))

    def start(self, card, action_id, now):
        attempt = {"attempt_id": str(len(self.attempts) + 1), "skill_id": card["id"],
                   "action_id": action_id, "validator": card["validator"], "rule_version": "1",
                   "compatibility": card["compatibility"],
                   "content_revision": card.get("content_revision", "2026-10-21"),
                   "seen_at": self.state["seen"].get(card["id"]), "started_at": utc(now),
                   "started_local_date": now.astimezone().date().isoformat(),
                   "started_timezone": os.environ.get("TZ") or str(now.astimezone().tzinfo),
                   "self_reported_at": None, "first_observed_at": None,
                   "baseline": list(self.state["events"]), "reuse_dates": [],
                   "stopped_at": None, "observations": []}
        self.attempts.append(attempt)
        return attempt

    def stop(self, attempt_id, now=None):
        for attempt in self.attempts:
            if attempt["attempt_id"] == attempt_id:
                attempt["stopped_at"] = utc(now or datetime.now(timezone.utc))
                return True
        return False

    def self_report(self, card, now, unsupported=False):
        if card["validator"] != "self" and not unsupported:
            return False
        attempt = next((a for a in reversed(self.attempts) if a["skill_id"] == card["id"]
                        and a["stopped_at"] is None), None)
        record = self.state.setdefault("self_reports", {}).setdefault(card["id"], {
            "skill_id": card["id"], "kind": "self_reported", "self_reported_at": utc(now),
            "local_date": now.astimezone().date().isoformat(),
            "timezone": os.environ.get("TZ") or str(now.astimezone().tzinfo),
            "content_revision": card.get("content_revision", "2026-10-21"), "rule_version": "1"})
        if attempt is not None:
            attempt["self_reported_at"] = attempt["self_reported_at"] or record["self_reported_at"]
        return True

    def observe(self, events, cards, coverage, now):
        for event in sorted(events, key=lambda e: e.dt()):
            occurred = event.dt()
            if occurred > now:
                continue
            identity = event.identity()
            if identity in self.state["events"]:
                continue
            local = occurred.astimezone()
            row = coverage.get(event.tool, {})
            record = {"occurred_at": utc(occurred), "first_seen_at": utc(now),
                      "local_date": local.date().isoformat(),
                      "timezone": os.environ.get("TZ") or str(local.tzinfo),
                      "tool": event.tool, "adapter_version": row.get("adapter_version", "1"),
                      "format": row.get("format", FORMATS.get(event.tool, "unknown")),
                      "event_id": identity, "kind": "historical", "attempt_id": None,
                      "skill_id": None, "action_id": None, "rule_version": "1", "content_revision": None}
            candidates = [a for a in self.attempts if a["stopped_at"] is None
                          and identity not in a["baseline"] and occurred > datetime.fromisoformat(a["started_at"])
                          and qualifying(a, event, coverage)]
            if candidates:
                attempt = max(candidates, key=lambda a: (a["started_at"], int(a["attempt_id"])))
                record.update(kind="log_observed", attempt_id=attempt["attempt_id"],
                              skill_id=attempt["skill_id"], action_id=attempt["action_id"],
                              content_revision=attempt["content_revision"])
                if attempt["first_observed_at"] is None:
                    attempt["first_observed_at"] = utc(occurred)
                if any(previous["skill_id"] == attempt["skill_id"]
                       and previous["kind"] == "log_observed"
                       and previous["local_date"] != record["local_date"]
                       and datetime.fromisoformat(previous["occurred_at"]) < occurred
                       for previous in self.state["events"].values()):
                    attempt["reuse_dates"] = sorted(set(attempt["reuse_dates"]) | {record["local_date"]})
                attempt["observations"].append(identity)
            self.state["events"][identity] = record

    def evidence(self, card_id, legacy=None):
        attempts = [a for a in self.attempts if a["skill_id"] == card_id]
        if any(a["reuse_dates"] for a in attempts):
            return "reuse"
        if any(a["first_observed_at"] for a in attempts):
            return "log_observed"
        if card_id in self.state.get("self_reports", {}) or any(a["self_reported_at"] for a in attempts):
            return "self_reported"
        if any(a["stopped_at"] is None for a in attempts):
            return "started"
        return "historical" if legacy else "ready"
