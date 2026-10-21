"""Read local Codex usage, activity markers, and rate-limit snapshots."""
from datetime import datetime, timezone
import json
from pathlib import Path

from agentfit.engine.collectors.base import register
from agentfit.engine.events import CompactEvent
from agentfit.engine.inventory import Inventory, codex_inventory
from agentfit.engine.scan_state import ScanState


def _session_files(home: Path) -> list[Path]:
    root = home / ".codex"
    return sorted(
        file
        for directory in ("sessions", "archived_sessions")
        for file in (root / directory).rglob("*.jsonl")
        if not any(word in file.name.lower() for word in ("auth", "token"))
    )


def _record(raw: str) -> dict | None:
    try:
        row = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(row, dict) or not isinstance(row.get("payload"), dict):
        return None
    return row


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
        event.model = context.get("model") or "codex-unknown"
        event.cache_read = usage.get("cached_input_tokens", 0)
        event.input = max(0, usage.get("input_tokens", 0) - event.cache_read)
        event.output = usage.get("output_tokens", 0)
        event.cache_write = usage.get("cache_write_input_tokens") or 0
    elif kind == "response_item" and subtype in {"function_call", "custom_tool_call"}:
        name = payload.get("name")
        if not isinstance(name, str):
            return None
        event.key = f"tool:{payload['call_id']}" if payload.get("call_id") else f"tool:{file.stem}:{line_no}"
        event.tool_calls = {name: 1}
        event.sidechain = name.startswith("spawn_agent")
    elif kind == "event_msg" and subtype == "task_started":
        event.key = f"turn:{file.stem}:{line_no}"
        event.turn_start = 1
    elif kind == "event_msg" and subtype == "turn_aborted":
        event.key = f"abort:{file.stem}:{line_no}"
        event.aborted = 1
    elif kind == "response_item" and subtype == "compaction":
        event.key = f"compact:{file.stem}:{line_no}"
        event.compacted = 1
    else:
        return None
    return event


class CodexCollector:
    tool = "codex"
    tier = "deep"

    def detect(self, home: Path) -> bool:
        return (home / ".codex").is_dir()

    def inventory(self, home: Path) -> Inventory:
        return codex_inventory(home)

    def scan(self, home: Path, state: ScanState) -> list[CompactEvent]:
        files = _session_files(home)
        result = []
        for file in files:
            lines, reset = state.read_new_lines(self.tool, file)
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
                    continue
                if row.get("type") == "turn_context":
                    context = {key: row["payload"].get(key) for key in ("model", "effort", "cwd")}
                    continue
                event = _event(row, context, file, line_no)
                if event is None:
                    continue
                if event.model:
                    if event.key in seen:
                        continue
                    seen.add(event.key)
                events.append(event)
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
                if not isinstance(limits, dict) or not isinstance(limits.get("primary"), dict):
                    continue
                try:
                    timestamp = datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00"))
                    if timestamp.tzinfo is None:
                        timestamp = timestamp.replace(tzinfo=timezone.utc)
                    value = {"plan_type": limits.get("plan_type")}
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
