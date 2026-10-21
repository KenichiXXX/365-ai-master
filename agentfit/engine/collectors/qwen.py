"""Qwen Code cumulative session summaries; no request-log or credential reads."""
from pathlib import Path

from agentfit.engine.collectors.base import register
from agentfit.engine.collectors._usage import allowed, event, number, record
from agentfit.engine.scan_state import ScanState


class QwenCollector:
    tool = "qwen_code"
    tier = "usage"

    def detect(self, home: Path) -> bool:
        return (home / ".qwen").is_dir()

    def inventory(self, home: Path) -> None:
        return None

    def scan(self, home: Path, state: ScanState) -> list:
        path = home / ".qwen/usage_record.jsonl"
        if not path.is_file() or not allowed(path):
            state.forget_missing(self.tool, set())
            return []
        lines, reset = state.read_new_lines(self.tool, path)
        events = {} if reset else {e.key: e for e in state.cached_events(self.tool, path)}
        for raw in lines:
            row = record(raw)
            session = row.get("sessionId")
            models = row.get("models")
            if row.get("version") != 1 or not isinstance(session, str) or not session or not isinstance(models, dict):
                continue
            # A summary replaces the previous snapshot, including removed models.
            prefix = str(len(session)) + ":" + session + ":"
            replacement = {}
            try:
                for model, usage in models.items():
                    if not isinstance(usage, dict):
                        raise ValueError("Invalid model usage")
                    total = number(usage.get("inputTokens", 0))
                    cached = number(usage.get("cachedTokens", 0))
                    cached = min(cached, total) if total else cached
                    e = event(self.tool, prefix + model,
                              row.get("timestamp") or row.get("startTime"), model,
                              max(0, total - cached),
                              number(usage.get("outputTokens", 0)) + number(usage.get("thoughtsTokens", 0)), cached)
                    replacement[e.key] = e
            except (ValueError, TypeError, OverflowError, OSError):
                continue
            events = {k: e for k, e in events.items() if not k.startswith(prefix)}
            events.update(replacement)
        result = list(events.values())
        state.set_events(self.tool, path, result)
        state.forget_missing(self.tool, {str(path)})
        return result


register(QwenCollector())
