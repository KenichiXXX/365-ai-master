"""Read local Codex usage, activity markers, and rate-limit snapshots."""
import json
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path

from agentfit.engine.collectors._usage import (
    allowed,
    identifier,
    number,
    safe_key,
    source_files,
)
from agentfit.engine.collectors.base import register
from agentfit.engine.events import CompactEvent
from agentfit.engine.inventory import Inventory, codex_inventory
from agentfit.engine.scan_state import ScanState


def _session_files(home: Path, state: ScanState | None = None) -> list[Path]:
    root = home / ".codex"
    return sorted(
        file
        for directory in ("sessions", "archived_sessions")
        for file in source_files(root / directory, state, "codex")
        if file.suffix == ".jsonl"
        if not any(word in file.name.lower() for word in ("auth", "token"))
        and allowed(file, root / directory)
    )


def _record(raw: str) -> dict | None:
    try:
        row = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(row, dict) or not isinstance(row.get("payload"), dict):
        return None
    return row


def _identity(row):
    # Only supported metadata contributes to id-less marker identities.
    payload = row["payload"]
    identity = {"timestamp": row.get("timestamp"), "type": row.get("type"),
                **{key: payload.get(key) for key in ("type", "turn_id", "id", "name")}}
    return sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()


def _event(row: dict, context: dict, file: Path, line_no: int) -> CompactEvent | None:
    payload = row["payload"]
    kind = row.get("type")
    subtype = payload.get("type")
    if not row.get("timestamp"):
        return None
    event = CompactEvent(
        tool="codex", key="", ts=row["timestamp"], model="",
        effort=context.get("effort"), cwd=context.get("cwd"),
    )
    if kind == "token_usage_record":
        usage = payload.get("usage")
        event.key = payload.get("response_id") or payload.get("turn_id")
        if not event.key or not isinstance(usage, dict):
            return None
        event.model = identifier(context.get("model")) or "codex-unknown"
        event.cache_read = number(usage.get("cached_input_tokens", 0))
        event.input = max(0, number(usage.get("input_tokens", 0)) - event.cache_read)
        event.output = number(usage.get("output_tokens", 0))
        event.cache_write = number(usage.get("cache_write_input_tokens") or 0)
    elif kind == "response_item" and subtype in {"function_call", "custom_tool_call"}:
        name = identifier(payload.get("name"))
        if not name:
            return None
        event.key = f"tool:{payload['call_id']}" if payload.get("call_id") else f"tool:{_identity(row)}"
        event.tool_calls = {name: 1}
        event.sidechain = name.startswith("spawn_agent")
    elif kind == "event_msg" and subtype == "task_started":
        event.key = f"turn:{_identity(row)}"
        event.turn_start = 1
    elif kind == "event_msg" and subtype == "turn_aborted":
        event.key = f"abort:{_identity(row)}"
        event.aborted = 1
    elif kind == "response_item" and subtype == "compaction":
        event.key = f"compact:{_identity(row)}"
        event.compacted = 1
    else:
        return None
    event.key = safe_key(event.key)
    return event


class CodexCollector:
    tool = "codex"
    tier = "deep"

    def detect(self, home: Path) -> bool:
        return (home / ".codex").is_dir()

    def inventory(self, home: Path) -> Inventory:
        return codex_inventory(home)

    def scan(self, home: Path, state: ScanState) -> list[CompactEvent]:
        files = _session_files(home, state)
        result = []
        for file in files:
            try:
                lines, reset = state.read_new_lines(self.tool, file)
            except PermissionError:
                state.issue(self.tool, "permission_denied")
                continue
            cursor = state.state["tools"][self.tool][str(file)]
            # Context can precede any usage, so persist it independently of events.
            context = {} if reset else cursor.get("context", {})
            line_no = 0 if reset else cursor.get("line_no", 0)
            events = [] if reset else state.cached_events(self.tool, file)
            seen = {event.key for event in events if event.model}
            for raw in lines:
                line_no += 1
                row = _record(raw)
                if row is None:
                    state.note(self.tool, file, "malformed")
                    continue
                if row.get("type") == "turn_context":
                    context = {"model": identifier(row["payload"].get("model")),
                               "cwd": row["payload"].get("cwd")}
                    effort = row["payload"].get("effort")
                    context["effort"] = effort if effort in {"low", "medium", "high", "xhigh"} else None
                    continue
                try:
                    event = _event(row, context, file, line_no)
                    if event is not None:
                        event.dt()
                except (ValueError, TypeError, KeyError, AttributeError):
                    state.note(self.tool, file, "malformed")
                    continue
                if event is None:
                    if (row.get("type") == "event_msg" and row["payload"].get("type") == "token_count"
                            and row["payload"].get("info") is not None):
                        state.note(self.tool, file, "skipped")
                        state.issue(self.tool, "partial")
                    elif row.get("type") not in {"session_meta", "response_item", "event_msg"}:
                        state.note(self.tool, file, "skipped")
                    continue
                if event.model:
                    if event.key in seen:
                        continue
                    seen.add(event.key)
                events.append(event)
            if cursor.get("skipped", 0):
                state.issue(self.tool, "partial")
            cursor.update(context=context, line_no=line_no)
            state.set_events(self.tool, file, events)
            result.extend(events)
        state.forget_missing(self.tool, {str(file) for file in files})
        return result


def latest_rate_limits(home: Path) -> dict | None:
    files = sorted(_session_files(home), key=lambda file: file.stat().st_mtime_ns, reverse=True)[:5]
    newest = None
    result = None
    for file in files:
        with file.open(encoding="utf-8", errors="ignore") as stream:
            for raw in stream:
                if not raw.endswith("\n"):
                    continue
                row = _record(raw)
                if row is None or row.get("type") != "event_msg" or row["payload"].get("type") != "token_count":
                    continue
                limits = row["payload"].get("rate_limits")
                if not isinstance(limits, dict) or not any(isinstance(limits.get(name), dict)
                                                            for name in ("primary", "secondary")):
                    continue
                try:
                    timestamp = datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00"))
                    if timestamp.tzinfo is None:
                        timestamp = timestamp.replace(tzinfo=timezone.utc)
                    value = {"plan_type": limits.get("plan_type"), "recorded_at": timestamp.isoformat()}
                    for name in ("primary", "secondary"):
                        window = limits.get(name)
                        value[f"{name}_pct"] = float(window["used_percent"]) if window else None
                        value[f"{name}_window_min"] = int(window["window_minutes"]) if window else None
                        value[f"{name}_resets_at"] = datetime.fromtimestamp(window["resets_at"], timezone.utc).isoformat() if window else None
                except (KeyError, TypeError, ValueError, OverflowError, OSError):
                    continue
                if newest is None or timestamp > newest:
                    newest, result = timestamp, value
    return result


register(CodexCollector())
