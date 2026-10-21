"""Read Qwen usage requests and cumulative session summaries."""
from dataclasses import replace
import json
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
        paths = [home / ".qwen/usage_record.jsonl"]
        paths += sorted((home / ".qwen/usage").glob("token-usage-*.jsonl"))
        paths = [p for p in paths if p.is_file() and allowed(p)]
        summaries = []
        requests = {}
        for path in paths:
            if path.name == "usage_record.jsonl":
                summaries = self._summaries(path, state)
                continue
            lines, reset = state.read_new_lines(self.tool, path)
            cached = {} if reset else {e.key: e for e in state.cached_events(self.tool, path)}
            for raw in lines:
                row = record(raw)
                if row.get("schemaVersion") != 1:
                    continue
                session, ident = row.get("sessionId"), row.get("id")
                if not all(isinstance(v, str) and v for v in (session, ident)):
                    continue
                try:
                    total = number(row.get("inputTokens", 0))
                    cached_tokens = min(total, number(row.get("cachedTokens", 0)))
                    key = json.dumps([session, row.get("model"), ident])
                    e = event(self.tool, key, row.get("timestamp"), row.get("model"),
                              total - cached_tokens,
                              number(row.get("outputTokens", 0)) + number(row.get("thoughtsTokens", 0)),
                              cached_tokens)
                except (ValueError, TypeError, OverflowError, OSError):
                    continue
                cached[key] = e
            state.set_events(self.tool, path, list(cached.values()))
            requests.update(cached)
        state.forget_missing(self.tool, {str(p) for p in paths})
        # Summaries fill gaps only: request totals already represent this usage.
        totals = {}
        for e in requests.values():
            session, model, _ = json.loads(e.key)
            summary_key = str(len(session)) + ":" + session + ":" + model
            counts = totals.setdefault(summary_key, [0, 0, 0])
            for i, value in enumerate((e.input, e.output, e.cache_read)):
                counts[i] += value
        result = list(requests.values())
        for e in summaries:
            used = totals.get(e.key, [0, 0, 0])
            remaining = [max(0, value - count) for value, count in zip(
                (e.input, e.output, e.cache_read), used)]
            if any(remaining) or e.key not in totals:
                result.append(replace(e, input=remaining[0], output=remaining[1], cache_read=remaining[2]))
        return result

    def _summaries(self, path: Path, state: ScanState) -> list:
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
        return result


register(QwenCollector())
