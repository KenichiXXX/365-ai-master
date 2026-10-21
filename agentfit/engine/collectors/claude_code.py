"""Read Claude Code logs into per-file compact usage and activity events."""
import json
from collections import Counter
from dataclasses import replace
from hashlib import sha256
from pathlib import Path

from agentfit.engine.collectors._usage import (
    identifier,
    number,
    safe_files,
    safe_key,
    source_files,
)
from agentfit.engine.collectors.base import register
from agentfit.engine.events import CompactEvent
from agentfit.engine.inventory import Inventory, claude_inventory
from agentfit.engine.scan_state import ScanState


def _parse(line: dict) -> CompactEvent | None:
    kind = line.get("type")
    message = line.get("message") or {}
    if not isinstance(message, dict):
        raise ValueError("Invalid message")
    event = CompactEvent(
        tool="claude_code",
        key="",
        ts=line["timestamp"],
        model="",
        sidechain=line.get("isSidechain") is True,
        effort=line.get("effort") if line.get("effort") in {"low", "medium", "high", "xhigh"} else None,
        cwd=line.get("cwd"),
    )
    if kind == "assistant":
        usage = message.get("usage")
        if not usage:
            return None
        event.model = identifier(message.get("model")) or "unknown"
        event.input = number(usage.get("input_tokens", 0))
        event.output = number(usage.get("output_tokens", 0))
        if message.get("model") == "<synthetic>" or event.input + event.output == 0:
            return None
        event.key = message.get("id") or line.get("requestId") or line["uuid"]
        event.cache_read = number(usage.get("cache_read_input_tokens", 0))
        event.cache_write = number(usage.get("cache_creation_input_tokens", 0))
        calls = Counter()
        skills = Counter()
        for ordinal, block in enumerate(message.get("content", [])):
            if block.get("type") != "tool_use":
                continue
            name = identifier(block.get("name"))
            if not name:
                continue
            name = "mcp" if name.startswith("mcp__") else name
            # Older fixtures lack block IDs: the stable block shape is the fallback,
            # never its input. A real ID distinguishes two calls of the same tool.
            identity = identifier(block.get("id")) or f"{event.key}:{ordinal}:{name}"
            identity = sha256(identity.encode()).hexdigest()
            event.markers[identity] = name
            calls[name] += 1
            if name == "Skill":
                skill = identifier((block.get("input") or {}).get("skill"))
                if skill:
                    skills[skill] += 1
                    event.markers[identity + ":skill"] = "skill:" + skill
        event.tool_calls = dict(calls)
        event.skill_calls = dict(skills)
    elif kind == "user":
        content = message.get("content", [])
        # A user string is a structured user turn; never classify its words.
        has_text = isinstance(content, str) or any(
            isinstance(b, dict) and b.get("type") == "text" for b in content)
        if not has_text:
            return None
        event.key = f"turn:{line['uuid']}"
        event.turn_start = 1
    elif kind == "system" and line.get("subtype") == "compact_boundary":
        event.key = f"compact:{line['uuid']}"
        event.compacted = 1
    elif kind == "attachment" and line.get("attachment", {}).get("type") == "hook_success":
        event.key = f"hook:{line['uuid']}"
        event.hook_success = 1
    else:
        return None
    event.key = safe_key(event.key)
    return event


def _merge(previous: CompactEvent, new: CompactEvent) -> CompactEvent:
    winner = new if new.output > previous.output else previous
    markers = previous.markers | new.markers
    return replace(winner, markers=markers,
                   tool_calls=dict(Counter(v for v in markers.values() if not v.startswith("skill:"))),
                   skill_calls=dict(Counter(v[6:] for v in markers.values() if v.startswith("skill:"))))



class ClaudeCodeCollector:
    tool = "claude_code"
    tier = "deep"

    def detect(self, home: Path) -> bool:
        return (home / ".claude").is_dir()

    def inventory(self, home: Path, project_dirs: set[str] | None = None) -> Inventory:
        return claude_inventory(home, project_dirs or set())

    def scan(self, home: Path, state: ScanState) -> list[CompactEvent]:
        files = safe_files([p for p in source_files(home / ".claude/projects", state, self.tool)
                            if p.suffix == ".jsonl"],
                           home / ".claude/projects", state, self.tool)
        result = []
        for file in files:
            try:
                lines, reset = state.read_new_lines(self.tool, file)
            except PermissionError:
                state.issue(self.tool, "permission_denied")
                continue
            cached = [] if reset else state.cached_events(self.tool, file)
            events = {event.key: event for event in cached}
            for raw in lines:
                try:
                    line = json.loads(raw)
                except json.JSONDecodeError:
                    state.note(self.tool, file, "malformed")
                    continue
                if not isinstance(line, dict) or not line.get("timestamp"):
                    state.note(self.tool, file, "skipped")
                    continue
                try:
                    event = _parse(line)
                    if event is not None:
                        event.dt()
                except (KeyError, TypeError, ValueError, AttributeError):
                    state.note(self.tool, file, "malformed")
                    continue
                if event is None:
                    if line.get("type") not in {"user", "assistant", "system", "attachment"}:
                        state.note(self.tool, file, "skipped")
                    continue
                if event.key in events and event.model:
                    event = _merge(events[event.key], event)
                events[event.key] = event
            state.set_events(self.tool, file, list(events.values()))
            result.extend(events.values())
        state.forget_missing(self.tool, {str(file) for file in files})
        return result


register(ClaudeCodeCollector())
