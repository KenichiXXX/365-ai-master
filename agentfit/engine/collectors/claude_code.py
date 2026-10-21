"""Read Claude Code logs into per-file compact usage and activity events."""
from collections import Counter
import json
from pathlib import Path

from agentfit.engine.collectors.base import register
from agentfit.engine.events import CompactEvent
from agentfit.engine.scan_state import ScanState


def _parse(line: dict) -> CompactEvent | None:
    kind = line.get("type")
    message = line.get("message") or {}
    event = CompactEvent(
        tool="claude_code",
        key="",
        ts=line["timestamp"],
        model="",
        sidechain=line.get("isSidechain") is True,
        effort=line.get("effort") if isinstance(line.get("effort"), str) else None,
        cwd=line.get("cwd"),
    )
    if kind == "assistant":
        usage = message.get("usage")
        if not usage:
            return None
        event.model = message.get("model") or "unknown"
        event.input = usage.get("input_tokens", 0)
        event.output = usage.get("output_tokens", 0)
        if event.model == "<synthetic>" or event.input + event.output == 0:
            return None
        event.key = message.get("id") or line.get("requestId") or line["uuid"]
        event.cache_read = usage.get("cache_read_input_tokens", 0)
        event.cache_write = usage.get("cache_creation_input_tokens", 0)
        calls = Counter()
        skills = Counter()
        for block in message.get("content", []):
            if block.get("type") != "tool_use":
                continue
            name = block["name"]
            calls["mcp" if name.startswith("mcp__") else name] += 1
            if name == "Skill":
                skill = block.get("input", {}).get("skill")
                if skill:
                    skills[skill] += 1
        event.tool_calls = dict(calls)
        event.skill_calls = dict(skills)
    elif kind == "user":
        content = message.get("content", [])
        texts = [content] if isinstance(content, str) else [
            block.get("text", "") for block in content if block.get("type") == "text"
        ]
        if not texts:
            return None
        event.key = f"turn:{line['uuid']}"
        event.aborted = int(any("[Request interrupted by user" in text for text in texts))
        event.turn_start = 1 - event.aborted
    elif kind == "system" and line.get("subtype") == "compact_boundary":
        event.key = f"compact:{line['uuid']}"
        event.compacted = 1
    elif kind == "attachment" and line.get("attachment", {}).get("type") == "hook_success":
        event.key = f"hook:{line['uuid']}"
        event.hook_success = 1
    else:
        return None
    return event


def _merge(previous: CompactEvent, new: CompactEvent) -> CompactEvent:
    winner = new if new.output > previous.output else previous
    winner.tool_calls = dict(Counter(previous.tool_calls) + Counter(new.tool_calls))
    winner.skill_calls = dict(Counter(previous.skill_calls) + Counter(new.skill_calls))
    return winner


class ClaudeCodeCollector:
    tool = "claude_code"
    tier = "deep"

    def detect(self, home: Path) -> bool:
        return (home / ".claude").is_dir()

    def inventory(self, home: Path) -> None:
        return None

    def scan(self, home: Path, state: ScanState) -> list[CompactEvent]:
        files = sorted((home / ".claude").glob("projects/**/*.jsonl"))
        result = []
        for file in files:
            lines, reset = state.read_new_lines(self.tool, file)
            cached = [] if reset else state.cached_events(self.tool, file)
            events = {event.key: event for event in cached}
            for raw in lines:
                try:
                    line = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if not isinstance(line, dict) or not line.get("timestamp"):
                    continue
                event = _parse(line)
                if event is None:
                    continue
                if event.key in events and event.model:
                    event = _merge(events[event.key], event)
                events[event.key] = event
            state.set_events(self.tool, file, list(events.values()))
            result.extend(events.values())
        state.forget_missing(self.tool, {str(file) for file in files})
        return result


register(ClaudeCodeCollector())
