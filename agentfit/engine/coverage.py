"""Content-free source coverage; absence is meaningful only for covered signals."""
from datetime import timezone

FORMATS = {
    "claude_code": "claude-jsonl-v1",
    "codex": "codex-response-usage-v1",
    "gemini_cli": "gemini-journal-protobuf-v1",
    "opencode": "opencode-message-v1",
    "qwen_code": "qwen-usage-v1",
}
SIGNALS = ("usage", "tool_calls", "skill_calls", "turn_start", "aborted", "compacted", "hook_success", "sidechain")
SUPPORTED = {
    "claude_code": {"usage", "tool_calls", "skill_calls", "turn_start", "compacted", "hook_success", "sidechain"},
    "codex": {"usage", "tool_calls", "turn_start", "aborted", "compacted", "sidechain"},
}


def source_coverage(tool, detected, events, state, error=None):
    cursors = list(state.state["tools"].get(tool, {}).values()) if detected else []
    malformed = sum(c.get("malformed", 0) for c in cursors)
    skipped = sum(c.get("skipped", 0) for c in cursors)
    issues = state.issues.get(tool, [])
    usage = {e.key: e for e in events if e.model}
    bounds = [e.dt().astimezone(timezone.utc) for e in usage.values()]
    if error == "permission_denied" or ("permission_denied" in issues and not usage):
        status = "permission_denied"
    elif not detected and not error:
        status = "not_detected"
    elif error or issues or malformed or skipped:
        status = "partial" if usage or error or "partial" in issues else "unsupported"
    elif not cursors or not any(c.get("size", 0) or c.get("signature") for c in cursors):
        status = "no_logs"
    elif not usage:
        status = "unsupported"
    else:
        status = "ok"
    supported = SUPPORTED.get(tool, {"usage"})
    return {
        "adapter_version": "1", "format": FORMATS.get(tool, "unknown"), "status": status,
        "start_utc": min(bounds).isoformat() if bounds else None,
        "end_utc": max(bounds).isoformat() if bounds else None,
        "valid_usage_count": len(usage), "malformed_count": malformed, "skipped_count": skipped,
        "signals": {s: ("unsupported" if s not in supported else
                          "available" if status == "ok" else "unknown") for s in SIGNALS},
    }
