# 365 AI Master for macOS — 新手村 v1 Implementation Plan

> **For agentic workers:** Execute task-by-task, in order. Steps use checkbox (`- [ ]`) syntax. After each task: run the full test suite, commit, then STOP and report (the reviewer gates the next task). Spec: `docs/superpowers/specs/2026-10-21-macos-newbie-village-design.md`.

**Goal:** A macOS menu-bar app that reads local AI-coding-tool logs, shows usage/quota, scores the user, and walks them through a 9-quest "新手村" with one daily tip — fully offline.

**Architecture:** A Python engine (`agentfit/engine/`, new package) scans logs incrementally, builds a numeric profile, evaluates quests, and prints one JSON snapshot. A SwiftUI menu-bar app (`macos/`) runs the bundled engine binary every 60 s and renders the snapshot. App and engine share only the snapshot JSON contract (§Snapshot schema).

**Tech Stack:** Python 3.11+ (stdlib + pydantic already in deps), pytest; PyInstaller via `uv` (Python 3.12) for the engine binary; Swift 6 / SwiftUI / SwiftPM, macOS 13+.

## Global Constraints

- **Zero network:** no module under `agentfit/engine/` or `macos/` may import/use `urllib`, `http.client`, `requests`, `httpx`, `socket`, `URLSession`, `NWConnection`. Enforced by a test (Task 10).
- **No credentials:** never open `~/.codex/auth.json`, `~/.claude/.credentials*`, `~/.claude.json` `oauthAccount` data, Keychain, OpenCode `credential`/`account` tables, or any credential/auth/oauth file. Usage logs whose names merely contain "token" (e.g. Qwen `token-usage-*.jsonl`) are usage data and ARE allowed.
- **Read-only on user files:** never write under `~/.claude`, `~/.codex`, `~/.gemini`, `~/.local/share/opencode`, `~/.qwen`. Engine writes only to its `--state-dir` (default `~/Library/Application Support/365AIMaster/`).
- **No content in output:** prompt/response text and absolute paths must never appear in the snapshot. Content may be inspected in memory only for the markers named in this plan.
- **Do not touch** these files (they carry someone else's uncommitted work on `main`): `agentfit/analyzer/rules.py`, `agentfit/collector/codex.py`, `agentfit/cli.py`, `tests/test_*_pilot.py`. The new engine lives in `agentfit/engine/` (deviation from spec §7's `agentfit/collector/`, made to avoid that conflict).
- **Tokei:** use https://github.com/cclank/tokei only to learn log paths/field names. The repo has no LICENSE file — do NOT copy its code; write our own.
- **Money wording:** costs are labelled 折算 / "API-equivalent"; never claim dollars saved.
- **Locale:** `zh` if the system language starts with `zh`, else `en`. All user-facing strings in the snapshot come from `agentfit/engine/content.py`.
- **Tests:** `.venv/bin/python -m pytest -q` must stay green except the two pre-existing failures in `tests/test_analytics_api.py` (`test_get_30day_analytics`, `test_export_analytics_csv`).
- Commit messages end with `Co-Authored-By: Codex <noreply@openai.com>`.

## File Map

| File | Responsibility |
|---|---|
| `agentfit/models/checkup.py` | `DimensionScore`, `CheckupIssue`, `TimeInsight` (moved from `cloud/models.py`) |
| `agentfit/checkup.py` | Four-dimension scoring (moved from `cloud/coach.py`) — single source |
| `agentfit/engine/__init__.py`, `__main__.py` | Package; CLI entry `python -m agentfit.engine snapshot --json` |
| `agentfit/engine/events.py` | `CompactEvent` dataclass + JSON round-trip |
| `agentfit/engine/scan_state.py` | Incremental per-file reader + persisted cursors/event cache |
| `agentfit/engine/collectors/base.py` | `Collector` protocol, registry |
| `agentfit/engine/collectors/claude_code.py` | Claude Code (deep) |
| `agentfit/engine/collectors/codex.py` | Codex (deep) + rate limits |
| `agentfit/engine/collectors/gemini.py`, `opencode.py`, `qwen.py` | Usage-only collectors |
| `agentfit/engine/inventory.py` | Environment inventory (skills, instructions, hooks, MCP…) |
| `agentfit/engine/profile.py` | Events + inventory → `Profile` (windows, dedupe, signals) |
| `agentfit/engine/content.py` | All zh/en copy: quests, dimension tips, tip pool, labels |
| `agentfit/engine/village.py` | Quest evaluation, progress persistence, rank, today tip |
| `agentfit/engine/snapshot.py` | Orchestration → snapshot dict |
| `scripts/build_engine.sh` | PyInstaller one-file build → `dist/365engine` |
| `macos/Package.swift`, `macos/Sources/AIMaster/*.swift` | Menu-bar app |
| `macos/Resources/*.lproj/Localizable.strings` | UI chrome strings |
| `scripts/package_app.sh` | Assemble `365 AI Master.app` with embedded engine |
| `tests/engine/…` | Tests + fixtures |

---

### Task 1: Move four-dimension scoring into `agentfit` (single source)

**Files:**
- Create: `agentfit/models/checkup.py`, `agentfit/checkup.py`, `tests/engine/__init__.py` (empty), `tests/engine/test_checkup_move.py`
- Modify: `cloud/models.py` (delete classes `TimeInsight`, `DimensionScore`, `CheckupIssue`; re-export), `cloud/coach.py` (delete moved functions; import them)

**Interfaces:**
- Produces: `agentfit.checkup` exposing `diagnose_model_mix(usage_by_model, total_cost_7d) -> (str, float, dict)`, `analyze_time_habits(hist) -> (list[TimeInsight], list[int], dict)`, `compute_checkup(rule_hits, mix_flags, time_flags, cache_hit_rate, saving) -> (list[DimensionScore], list[CheckupIssue])`, `overall_from_dimensions(dims) -> int`, `tier_for_score(score) -> str`, `checkup_score(...) -> (int, str)`, constants `FAST_VS_PREMIUM_COST_RATIO`, `ROUTABLE_SHARE_OF_PREMIUM`, `DIMENSION_WEIGHTS`.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_checkup_move.py`:

```python
import subprocess, sys

def test_checkup_importable_without_cloud():
    code = (
        "import sys\n"
        "import agentfit.checkup as c\n"
        "assert 'cloud' not in sys.modules, sorted(m for m in sys.modules if m.startswith('cloud'))\n"
        "dims, _ = c.compute_checkup({}, {}, {}, None, 0.0)\n"
        "print(c.overall_from_dimensions(dims))\n"
    )
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert out.stdout.strip() == "91"

def test_cloud_reexports_same_objects():
    import agentfit.checkup as a, cloud.coach as c, agentfit.models.checkup as am, cloud.models as cm
    assert c.compute_checkup is a.compute_checkup
    assert c.overall_from_dimensions is a.overall_from_dimensions
    assert cm.DimensionScore is am.DimensionScore
```

- [ ] **Step 2:** Run `.venv/bin/python -m pytest tests/engine/test_checkup_move.py -q` → FAIL (`No module named 'agentfit.checkup'`).
- [ ] **Step 3: Move models.** Cut the three classes `TimeInsight`, `DimensionScore`, `CheckupIssue` verbatim from `cloud/models.py` into `agentfit/models/checkup.py` (add `from typing import List, Literal` and `from pydantic import BaseModel, Field` as needed). In `cloud/models.py`, at the import block add `from agentfit.models.checkup import CheckupIssue, DimensionScore, TimeInsight  # noqa: F401  (single source)`.
- [ ] **Step 4: Move functions.** Cut verbatim from `cloud/coach.py` into `agentfit/checkup.py`: constants `FAST_VS_PREMIUM_COST_RATIO`, `ROUTABLE_SHARE_OF_PREMIUM`; functions `diagnose_model_mix`, `analyze_time_habits`, `_clamp`, `compute_checkup`; `DIMENSION_WEIGHTS`, `overall_from_dimensions`, `tier_for_score`, `checkup_score`. Header of `agentfit/checkup.py`:

```python
"""四维体检评分 — CLI / 引擎 / 云端共用的唯一来源。"""
from typing import Dict, List, Optional, Tuple

from agentfit.models.checkup import CheckupIssue, DimensionScore, TimeInsight
from agentfit.pricing import classify_model
```

In `cloud/coach.py` replace the removed code with:

```python
from agentfit.checkup import (  # noqa: F401  re-exported for cloud.api / tests
    DIMENSION_WEIGHTS, FAST_VS_PREMIUM_COST_RATIO, ROUTABLE_SHARE_OF_PREMIUM,
    analyze_time_habits, checkup_score, compute_checkup, diagnose_model_mix,
    overall_from_dimensions, tier_for_score,
)
```
Remove now-unused imports from `cloud/coach.py`'s `cloud.models` import list only if flake reports them unused; keep `ActionItem`, `CoachReport`, `ModelRoutingAdvice` etc.
- [ ] **Step 5:** Run full suite `.venv/bin/python -m pytest -q` → only the 2 pre-existing failures.
- [ ] **Step 6: Commit** `git add -A agentfit/models/checkup.py agentfit/checkup.py cloud/models.py cloud/coach.py tests/engine && git commit -m "refactor: move four-dimension scoring into agentfit.checkup"`

---

### Task 2: Engine core — events, incremental scan state, collector protocol

**Files:**
- Create: `agentfit/engine/__init__.py` (empty), `agentfit/engine/events.py`, `agentfit/engine/scan_state.py`, `agentfit/engine/collectors/__init__.py`, `agentfit/engine/collectors/base.py`, `tests/engine/test_scan_state.py`

**Interfaces — Produces:**

```python
# agentfit/engine/events.py
@dataclass
class CompactEvent:
    tool: str                 # "claude_code" | "codex" | "gemini_cli" | "opencode" | "qwen_code"
    key: str                  # dedupe key, unique per (tool, real request)
    ts: str                   # ISO8601 with offset (UTC ok)
    model: str
    input: int = 0            # non-cached input tokens
    output: int = 0
    cache_read: int = 0
    cache_write: int = 0
    tool_calls: dict[str, int] = field(default_factory=dict)   # tool name -> count
    skill_calls: dict[str, int] = field(default_factory=dict)  # skill name -> count
    sidechain: bool = False
    effort: str | None = None
    turn_start: int = 0       # user turns started (prompts)
    aborted: int = 0          # turns interrupted/aborted
    compacted: int = 0        # context compactions
    hook_success: int = 0
    cwd: str | None = None    # engine-internal only, NEVER emitted
    def to_dict(self) -> dict: ...
    @staticmethod
    def from_dict(d: dict) -> "CompactEvent": ...
    def dt(self) -> datetime: ...   # aware datetime parsed from ts

# agentfit/engine/scan_state.py
class ScanState:
    def __init__(self, path: Path): ...          # JSON file; missing/corrupt -> empty
    def read_new_lines(self, tool: str, file: Path) -> tuple[list[str], bool]:
        """Return (complete new lines since cursor, reset). reset=True when the file
        shrank or its first 256 bytes changed -> caller must drop cached events for it."""
    def cached_events(self, tool: str, file: Path) -> list[CompactEvent]: ...
    def set_events(self, tool: str, file: Path, events: list[CompactEvent]) -> None: ...
    def files(self, tool: str) -> list[str]: ...
    def forget_missing(self, tool: str, existing: set[str]) -> None: ...
    def prune_before(self, cutoff: datetime) -> None: ...   # drop events older than cutoff
    def save(self) -> None: ...                  # atomic write (tmp + os.replace)

# agentfit/engine/collectors/base.py
class Collector(Protocol):
    tool: str
    tier: str                 # "deep" | "usage"
    def detect(self, home: Path) -> bool: ...
    def scan(self, home: Path, state: ScanState) -> list[CompactEvent]: ...  # ALL cached+new events
    def inventory(self, home: Path) -> "Inventory | None": ...
REGISTRY: list[Collector]    # filled by later tasks via register()
def register(c: Collector) -> Collector: ...
```

Cursor format per file in the JSON: `{"size": int, "offset": int, "head": sha1(first 256 bytes) hex, "events": [CompactEvent.to_dict(), ...]}` under `state["tools"][tool][str(file)]`. Only complete lines (ending in `\n`) advance `offset`.

- [ ] **Step 1: Failing tests** — `tests/engine/test_scan_state.py`:

```python
from pathlib import Path
from datetime import datetime, timezone, timedelta
from agentfit.engine.scan_state import ScanState
from agentfit.engine.events import CompactEvent

def test_incremental_reads_only_new_complete_lines(tmp_path):
    log = tmp_path / "a.jsonl"; log.write_text('{"a":1}\n{"b":2}\n{"partial"')
    st = ScanState(tmp_path / "state.json")
    lines, reset = st.read_new_lines("t", log)
    assert lines == ['{"a":1}', '{"b":2}'] and reset is False
    with open(log, "a") as f: f.write(':3}\n{"c":4}\n')
    lines, _ = st.read_new_lines("t", log)
    assert lines == ['{"partial":3}', '{"c":4}']

def test_truncated_file_resets(tmp_path):
    log = tmp_path / "a.jsonl"; log.write_text('{"a":1}\n{"b":2}\n')
    st = ScanState(tmp_path / "s.json"); st.read_new_lines("t", log)
    log.write_text('{"z":9}\n')
    lines, reset = st.read_new_lines("t", log)
    assert reset is True and lines == ['{"z":9}']

def test_events_persist_and_prune(tmp_path):
    p = tmp_path / "s.json"; log = tmp_path / "a.jsonl"; log.write_text("x\n")
    st = ScanState(p); st.read_new_lines("t", log)
    old = (datetime.now(timezone.utc) - timedelta(days=40)).isoformat()
    new = datetime.now(timezone.utc).isoformat()
    st.set_events("t", log, [CompactEvent(tool="t", key="1", ts=old, model="m"),
                             CompactEvent(tool="t", key="2", ts=new, model="m")])
    st.prune_before(datetime.now(timezone.utc) - timedelta(days=30)); st.save()
    again = ScanState(p)
    assert [e.key for e in again.cached_events("t", log)] == ["2"]

def test_corrupt_state_file_starts_empty(tmp_path):
    p = tmp_path / "s.json"; p.write_text("{not json")
    assert ScanState(p).files("t") == []
```

- [ ] **Step 2:** Run → FAIL (module missing).
- [ ] **Step 3: Implement** `events.py` (dataclass with `asdict` for `to_dict`, `CompactEvent(**{k: d[k] for k in fields if k in d})` for `from_dict`, `dt()` via `datetime.fromisoformat(ts.replace("Z", "+00:00"))`, naive → assume UTC), `scan_state.py` (binary read from `offset`, split on `b"\n"`, keep trailing partial unread, decode utf-8 with `errors="ignore"`; head check: if `size < cursor.size` or sha1 of first 256 bytes differs → reset offset 0 and clear events), and `collectors/base.py` (Protocol via `typing.Protocol`, `REGISTRY: list = []`, `register` appends and returns).
- [ ] **Step 4:** Run tests → PASS; full suite green.
- [ ] **Step 5: Commit** `feat(engine): compact events, incremental scan state, collector protocol`

---

### Task 3: Claude Code collector (deep)

**Files:**
- Create: `agentfit/engine/collectors/claude_code.py`, `tests/engine/fixtures/claude/projects/-tmp-demo/s1.jsonl`, `tests/engine/test_claude_code.py`

**Interfaces:** Consumes Task 2. Produces `ClaudeCodeCollector` (tool=`"claude_code"`, tier=`"deep"`) registered in `REGISTRY`; `inventory` added in Task 6 (return `None` for now).

**Parsing rules (verified against real logs 2026-10-21):**
- Files: `<home>/.claude/projects/*/*.jsonl` and `<home>/.claude/projects/*/*/subagents/*.jsonl` if present (`glob("projects/**/*.jsonl")`).
- `type=="assistant"` with `message.usage`: one event per `message.id` **within a file** (the same id repeats across several lines — 1628 of 1933 ids in a real sample). For repeats: take usage from the line with the largest `output_tokens`; sum `tool_use` blocks across lines. `key = message.id` (fallback `requestId`, then `uuid`).
- Tokens: `input_tokens` → input, `output_tokens` → output, `cache_read_input_tokens` → cache_read, `cache_creation_input_tokens` → cache_write. `model = message.model or "unknown"`; skip model `"<synthetic>"` and events whose input+output == 0.
- `tool_calls`: count `content[].type=="tool_use"` by `name`; names starting `mcp__` count as `"mcp"`. If `name=="Skill"`, also `skill_calls[input["skill"]] += 1`.
- `sidechain = line.isSidechain is True`; `effort = line.effort` (string or None); `cwd = line.cwd`.
- `type=="user"`: if `message.content` is a `str`, or a list containing a `{"type":"text"}` block → it is a prompt: emit a zero-token marker event `key=f"turn:{uuid}"`, `model=""`, `turn_start=1`; if that text contains `[Request interrupted by user` → instead `aborted=1, turn_start=0`. Lists made only of `tool_result` blocks are not prompts.
- `type=="system"` and `subtype=="compact_boundary"` → marker event `compacted=1`, key `compact:{uuid}`.
- `type=="attachment"` and `attachment.type=="hook_success"` → marker event `hook_success=1`, key `hook:{uuid}`.
- Every event's `ts` = line `timestamp`. Malformed JSON lines are skipped.
- `scan()`: for each file, `lines, reset = state.read_new_lines(...)`; parse new lines; merge with `[] if reset else state.cached_events(...)`, applying the same-id merge rule against cached events of that file; `state.set_events(...)`; `state.forget_missing(...)`; return all events.

- [ ] **Step 1: Fixture** `tests/engine/fixtures/claude/projects/-tmp-demo/s1.jsonl` (one JSON per line, exactly):

```
{"type":"user","uuid":"u1","timestamp":"2026-10-20T01:00:00Z","cwd":"/tmp/demo","message":{"role":"user","content":"please fix the bug"}}
{"type":"assistant","uuid":"a1","timestamp":"2026-10-20T01:00:05Z","cwd":"/tmp/demo","effort":"high","isSidechain":false,"requestId":"r1","message":{"id":"msg_1","model":"claude-opus-5","role":"assistant","content":[{"type":"tool_use","name":"Read","input":{}}],"usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}
{"type":"assistant","uuid":"a2","timestamp":"2026-10-20T01:00:06Z","cwd":"/tmp/demo","effort":"high","isSidechain":false,"requestId":"r1","message":{"id":"msg_1","model":"claude-opus-5","role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{}},{"type":"tool_use","name":"Skill","input":{"skill":"tdd"}}],"usage":{"input_tokens":10,"output_tokens":50,"cache_read_input_tokens":100,"cache_creation_input_tokens":20}}}
{"type":"user","uuid":"u2","timestamp":"2026-10-20T01:01:00Z","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}
{"type":"assistant","uuid":"a3","timestamp":"2026-10-20T01:02:00Z","isSidechain":true,"message":{"id":"msg_2","model":"claude-haiku-4-5","role":"assistant","content":[{"type":"tool_use","name":"mcp__github__search","input":{}}],"usage":{"input_tokens":3,"output_tokens":4}}}
{"type":"user","uuid":"u3","timestamp":"2026-10-20T01:03:00Z","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}
{"type":"system","subtype":"compact_boundary","uuid":"s1","timestamp":"2026-10-20T01:04:00Z"}
{"type":"attachment","uuid":"h1","timestamp":"2026-10-20T01:05:00Z","attachment":{"type":"hook_success","hookEvent":"Stop"}}
{"type":"assistant","uuid":"a4","timestamp":"2026-10-20T01:06:00Z","message":{"id":"msg_3","model":"<synthetic>","role":"assistant","content":[],"usage":{"input_tokens":0,"output_tokens":0}}}
not json at all
```

- [ ] **Step 2: Failing test** `tests/engine/test_claude_code.py`:

```python
import shutil
from pathlib import Path
from agentfit.engine.collectors.claude_code import ClaudeCodeCollector
from agentfit.engine.scan_state import ScanState

FIX = Path(__file__).parent / "fixtures" / "claude"

def _home(tmp_path):
    shutil.copytree(FIX, tmp_path / ".claude"); return tmp_path

def test_parses_and_dedupes(tmp_path):
    home = _home(tmp_path); c = ClaudeCodeCollector()
    assert c.detect(home)
    ev = c.scan(home, ScanState(tmp_path / "s.json"))
    usage = {e.key: e for e in ev if e.model}
    assert set(usage) == {"msg_1", "msg_2"}
    m1 = usage["msg_1"]
    assert (m1.input, m1.output, m1.cache_read, m1.cache_write) == (10, 50, 100, 20)
    assert m1.tool_calls == {"Read": 1, "Edit": 1, "Skill": 1}
    assert m1.skill_calls == {"tdd": 1} and m1.effort == "high"
    assert usage["msg_2"].sidechain and usage["msg_2"].tool_calls == {"mcp": 1}
    assert sum(e.turn_start for e in ev) == 1
    assert sum(e.aborted for e in ev) == 1
    assert sum(e.compacted for e in ev) == 1
    assert sum(e.hook_success for e in ev) == 1

def test_second_scan_is_incremental(tmp_path):
    home = _home(tmp_path); st = ScanState(tmp_path / "s.json"); c = ClaudeCodeCollector()
    first = c.scan(home, st); second = c.scan(home, st)
    assert sorted(e.key for e in first) == sorted(e.key for e in second)

def test_not_detected_without_dir(tmp_path):
    assert ClaudeCodeCollector().detect(tmp_path) is False
```

- [ ] **Step 3:** Run → FAIL. **Step 4:** Implement per the rules. **Step 5:** PASS + full suite.
- [ ] **Step 6: Commit** `feat(engine): Claude Code deep collector`

---

### Task 4: Codex collector (deep) + rate limits

**Files:**
- Create: `agentfit/engine/collectors/codex.py`, `tests/engine/fixtures/codex/sessions/2026/10/20/rollout-1.jsonl`, `tests/engine/test_codex_engine.py`

**Interfaces:** Produces `CodexCollector` (tool=`"codex"`, tier=`"deep"`) and module function `latest_rate_limits(home: Path) -> dict | None` returning `{"primary_pct": float, "primary_window_min": int, "primary_resets_at": iso, "secondary_pct": float|None, "secondary_window_min": int|None, "secondary_resets_at": iso|None, "plan_type": str|None}` from the newest `token_count` event across the 5 most recently modified session files.

**Parsing rules (verified 2026-10-21):** lines are `{"timestamp","type","payload"}`.
- `type=="turn_context"` → remember `payload.model`, `payload.effort`, `payload.cwd` for following events in the file.
- `type=="token_usage_record"` → usage event, `key = payload.response_id` (fallback `payload.turn_id`). From `payload.usage`: `cache_read = cached_input_tokens`, `input = input_tokens - cached_input_tokens` (min 0; Codex input includes cache), `output = output_tokens`, `cache_write = cache_write_input_tokens or 0`. `model` = current turn_context model or `"codex-unknown"`.
- `type=="response_item"` and `payload.type in {"function_call","custom_tool_call"}` → add `payload.name` to `tool_calls` of a marker event `key=f"tool:{payload.call_id}"`, model `""`; if name starts with `spawn_agent` set `sidechain=True`.
- `type=="event_msg"` and `payload.type=="task_started"` → marker `turn_start=1`; `"turn_aborted"` → marker `aborted=1`.
- `type=="response_item"` and `payload.type=="compaction"` → marker `compacted=1`.
- Marker keys must be unique per line: `f"{kind}:{file.stem}:{line_no}"` where no id exists.
- Files: `<home>/.codex/sessions/**/*.jsonl` and `<home>/.codex/archived_sessions/**/*.jsonl`.
- `rate_limits`: `payload.rate_limits.primary/secondary` of `event_msg/token_count`; `resets_at` is a unix epoch int → ISO8601 UTC.

- [ ] **Step 1: Fixture** (exact lines):

```
{"timestamp":"2026-10-20T02:00:00Z","type":"session_meta","payload":{"id":"sess1","cwd":"/tmp/x","cli_version":"0.162.1"}}
{"timestamp":"2026-10-20T02:00:01Z","type":"turn_context","payload":{"model":"gpt-6.1-sol","effort":"low","cwd":"/tmp/x"}}
{"timestamp":"2026-10-20T02:00:02Z","type":"event_msg","payload":{"type":"task_started"}}
{"timestamp":"2026-10-20T02:00:03Z","type":"response_item","payload":{"type":"function_call","name":"shell","call_id":"c1"}}
{"timestamp":"2026-10-20T02:00:04Z","type":"token_usage_record","payload":{"response_id":"resp1","turn_id":"t1","usage":{"input_tokens":1000,"cached_input_tokens":800,"cache_write_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":1050}}}
{"timestamp":"2026-10-20T02:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","primary":{"used_percent":42.5,"window_minutes":300,"resets_at":1792540800},"secondary":{"used_percent":10.0,"window_minutes":10080,"resets_at":1793000000},"plan_type":"pro"}}}
{"timestamp":"2026-10-20T02:00:06Z","type":"token_usage_record","payload":{"response_id":"resp1","turn_id":"t1","usage":{"input_tokens":1000,"cached_input_tokens":800,"cache_write_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":1050}}}
{"timestamp":"2026-10-20T02:00:07Z","type":"response_item","payload":{"type":"custom_tool_call","name":"spawn_agent","call_id":"c2"}}
{"timestamp":"2026-10-20T02:00:08Z","type":"event_msg","payload":{"type":"turn_aborted"}}
{"timestamp":"2026-10-20T02:00:09Z","type":"response_item","payload":{"type":"compaction"}}
```

- [ ] **Step 2: Failing test:**

```python
import shutil
from pathlib import Path
from agentfit.engine.collectors.codex import CodexCollector, latest_rate_limits
from agentfit.engine.scan_state import ScanState

FIX = Path(__file__).parent / "fixtures" / "codex"

def _home(tmp_path):
    shutil.copytree(FIX, tmp_path / ".codex"); return tmp_path

def test_codex_usage_and_markers(tmp_path):
    home = _home(tmp_path)
    ev = CodexCollector().scan(home, ScanState(tmp_path / "s.json"))
    usage = [e for e in ev if e.model]
    assert len({e.key for e in usage}) == 1          # resp1 deduped (profile also dedupes)
    u = usage[0]
    assert (u.input, u.cache_read, u.output, u.model, u.effort) == (200, 800, 50, "gpt-6.1-sol", "low")
    calls = {}
    for e in ev:
        for k, v in e.tool_calls.items(): calls[k] = calls.get(k, 0) + v
    assert calls == {"shell": 1, "spawn_agent": 1}
    assert any(e.sidechain for e in ev)
    assert sum(e.turn_start for e in ev) == 1 and sum(e.aborted for e in ev) == 1
    assert sum(e.compacted for e in ev) == 1

def test_rate_limits(tmp_path):
    rl = latest_rate_limits(_home(tmp_path))
    assert rl["primary_pct"] == 42.5 and rl["primary_window_min"] == 300
    assert rl["secondary_pct"] == 10.0 and rl["plan_type"] == "pro"
    assert rl["primary_resets_at"].startswith("2026-")

def test_rate_limits_none_without_logs(tmp_path):
    assert latest_rate_limits(tmp_path) is None
```

(Within one file the collector must emit `resp1` once: keep a per-file `seen` set of usage keys.)
- [ ] **Step 3–5:** FAIL → implement → PASS + full suite.
- [ ] **Step 6: Commit** `feat(engine): Codex deep collector with offline rate limits`

---

### Task 5: Usage-only collectors — Gemini CLI, OpenCode, Qwen Code

**Files:**
- Create: `agentfit/engine/collectors/gemini.py`, `opencode.py`, `qwen.py`; fixtures under `tests/engine/fixtures/{gemini,opencode,qwen}/`; `tests/engine/test_usage_collectors.py`

**Interfaces:** Each a `Collector` with `tier="usage"`, `inventory()` returns `None`, tools `"gemini_cli"`, `"opencode"`, `"qwen_code"`. Only token/model/ts fields are filled.

- [ ] **Step 1: Learn the formats (read only, no copying).** Fetch Tokei's source and tests for reference:

```bash
mkdir -p /tmp/tokei-ref && cd /tmp/tokei-ref
for f in usage.30s.py tests/test_gemini_usage.py tests/test_opencode_sqlite.py tests/test_qwencode.py CALCULATION.md; do
  curl -fsSL "https://raw.githubusercontent.com/cclank/tokei/main/$f" -o "$(basename $f)"; done
grep -n "^def scan_gemini\|^def scan_opencode\|^def scan_qwencode\|^GEMINI_\|^OPENCODE_\|^QWEN_CODE" usage.30s.py
```
Read `scan_gemini` (≈line 5381), `scan_opencode` (≈12280), `scan_qwencode` (≈13376), their path constants, the matching test fixtures, and CALCULATION.md §2 field mapping (Gemini/Codex input already includes cache). Write down for each tool: file locations, record shape, token field names, model field, timestamp field, dedupe id.
- [ ] **Step 2: Fixtures.** For each tool create the smallest fixture that matches the real shape you documented (for OpenCode build a tiny SQLite file in the test with `sqlite3` using the same table/column names, opened read-only `file:...?mode=ro`, `uri=True`). Use invented values only.
- [ ] **Step 3: Failing tests** — `tests/engine/test_usage_collectors.py` must assert for each collector: `detect()` True with fixture / False on empty home; `scan()` returns the expected number of usage events with exact `input/output/cache_read/model` values from your fixture; re-scan returns the same keys (incremental); a malformed record is skipped without raising.
- [ ] **Step 4:** Implement. OpenCode SQLite must be opened read-only (`sqlite3.connect(f"file:{path}?mode=ro", uri=True)`); because SQLite is not line-based, OpenCode bypasses `read_new_lines` and stores its cursor as the max row id/time it has seen via `state.set_events` on the db path.
- [ ] **Step 5:** PASS + full suite. **Step 6: Commit** `feat(engine): usage-only collectors for Gemini CLI, OpenCode, Qwen Code`

---

### Task 6: Environment inventory

**Files:**
- Create: `agentfit/engine/inventory.py`, `tests/engine/test_inventory.py`
- Modify: `agentfit/engine/collectors/claude_code.py` and `codex.py` — `inventory()` delegates to `inventory.claude_inventory(home, project_dirs)` / `inventory.codex_inventory(home)`.

**Interfaces — Produces:**

```python
@dataclass
class Inventory:
    skills_installed: list[str]      # skill directory names (sorted, unique)
    instructions_bytes: int          # max size among global + project instruction files
    hooks: int                       # number of hook event types configured
    mcp_servers: int
    subagents: int
    plugins: int
    def to_public(self) -> dict      # counts only: {"skills_installed": len, "instructions_bytes", "hooks", "mcp_servers", "subagents", "plugins"}

def claude_inventory(home: Path, project_dirs: set[str]) -> Inventory
def codex_inventory(home: Path) -> Inventory
```

Rules:
- Claude: skills = names of dirs in `~/.claude/skills/*` that contain `SKILL.md`, plus `~/.claude/plugins/cache/*/*/*/skills/*/SKILL.md` parent dir names; instructions = sizes of `~/.claude/CLAUDE.md` and `<project_dir>/CLAUDE.md` for each dir in `project_dirs` (only `stat`, never read); hooks = `len(settings.json["hooks"])`; mcp = `len(~/.claude.json["mcpServers"])`; subagents = count `~/.claude/agents/*.md`; plugins = count of truthy values in `settings.json["enabledPlugins"]`. Any missing/invalid file → 0 for that field.
- Codex: skills = dirs in `~/.codex/skills/*` containing `SKILL.md`; instructions = size of `~/.codex/AGENTS.md`; mcp = number of `[mcp_servers.<name>]` tables in `~/.codex/config.toml` (use `tomllib`); hooks/subagents/plugins = 0.
- Never read the content of instruction files.

- [ ] **Step 1: Failing test:**

```python
import json
from pathlib import Path
from agentfit.engine.inventory import claude_inventory, codex_inventory

def test_claude_inventory(tmp_path):
    c = tmp_path / ".claude"
    (c / "skills" / "tdd").mkdir(parents=True); (c / "skills" / "tdd" / "SKILL.md").write_text("x")
    (c / "skills" / "empty").mkdir()
    (c / "agents").mkdir(); (c / "agents" / "a.md").write_text("x")
    (c / "CLAUDE.md").write_text("y" * 300)
    (c / "settings.json").write_text(json.dumps({"hooks": {"Stop": [], "PreToolUse": []}, "enabledPlugins": {"p@m": True, "q@m": False}}))
    (tmp_path / ".claude.json").write_text(json.dumps({"mcpServers": {"a": {}, "b": {}}}))
    proj = tmp_path / "proj"; proj.mkdir(); (proj / "CLAUDE.md").write_text("z" * 900)
    inv = claude_inventory(tmp_path, {str(proj)})
    assert inv.skills_installed == ["tdd"]
    assert (inv.instructions_bytes, inv.hooks, inv.mcp_servers, inv.subagents, inv.plugins) == (900, 2, 2, 1, 1)
    assert set(inv.to_public()) == {"skills_installed", "instructions_bytes", "hooks", "mcp_servers", "subagents", "plugins"}
    assert inv.to_public()["skills_installed"] == 1

def test_codex_inventory(tmp_path):
    x = tmp_path / ".codex"; (x / "skills" / "s1").mkdir(parents=True); (x / "skills" / "s1" / "SKILL.md").write_text("x")
    (x / "AGENTS.md").write_text("a" * 250)
    (x / "config.toml").write_text('[mcp_servers.one]\ncommand="a"\n[mcp_servers.two]\ncommand="b"\n')
    inv = codex_inventory(tmp_path)
    assert (inv.skills_installed, inv.instructions_bytes, inv.mcp_servers) == (["s1"], 250, 2)

def test_missing_everything(tmp_path):
    inv = claude_inventory(tmp_path, set())
    assert inv.to_public() == {"skills_installed": 0, "instructions_bytes": 0, "hooks": 0, "mcp_servers": 0, "subagents": 0, "plugins": 0}
```

- [ ] **Step 2–4:** FAIL → implement → PASS + full suite. **Step 5: Commit** `feat(engine): environment inventory`

---

### Task 7: Profile builder

**Files:**
- Create: `agentfit/engine/profile.py`, `tests/engine/test_profile.py`

**Interfaces — Produces:**

```python
@dataclass
class Profile:
    now: datetime
    usage_by_model_7d: dict[str, dict]     # {"model": {"tokens": int, "cost": float, "requests": int}}
    hourly_histogram_7d: list[int]         # 24 buckets, local time, usage events only
    cache_hit_rate_7d: float | None        # cache_read / (input + cache_read)
    total_cost_7d: float
    by_tool: dict[str, dict]               # tool -> {"today": {"tokens","cost_usd"}, "7d": {...}, "by_model": [{"model","tokens","cost_usd"}]} (7d, desc tokens)
    tool_calls_14d: dict[str, int]
    skill_calls_14d: dict[str, int]
    sidechain_14d: int
    turns_14d: int
    aborted_14d: int
    compactions_14d: int
    hook_success_14d: int
    light_token_share_14d: float           # fast-tier tokens / all tokens (0.0 if none)
    project_dirs_14d: set[str]             # engine-internal only
    def rule_hits(self) -> dict[str, bool]: # {"RULE_CONTEXT_BLOAT": compactions_14d >= 3,
                                            #  "RULE_ERROR_RETRY_LOOP": turns_14d >= 10 and aborted_14d / turns_14d >= 0.10}

def event_cost(e: CompactEvent) -> float   # agentfit.pricing.TIER_PRICES[classify_model(e.model)]: input*p_in + output*p_out + cache_read*p_cache, per 1e6
def build_profile(events: list[CompactEvent], now: datetime) -> Profile
def dimensions(p: Profile) -> list[DimensionScore]   # via agentfit.checkup: diagnose_model_mix(usage_by_model_7d, total_cost_7d), analyze_time_habits(hourly_histogram_7d), compute_checkup(p.rule_hits(), mix_flags, time_flags, cache_hit_rate_7d, saving)
```

Rules: dedupe by `(tool, key)` — when two events share a key keep tokens from the one with larger `output`, sum `tool_calls`/`skill_calls`/markers, OR `sidechain`. "Usage events" = `model != ""`. Tokens = input + output (cache excluded, same as existing `build_profile`). Windows: `today` = same local calendar date as `now`; `7d`/`14d` = `ts >= now - N days`. `requests` = number of usage events.

- [ ] **Step 1: Failing test:**

```python
from datetime import datetime, timezone, timedelta
from agentfit.engine.events import CompactEvent
from agentfit.engine.profile import build_profile, dimensions, event_cost

NOW = datetime(2026, 10, 21, 12, 0, tzinfo=timezone.utc)
def ev(**kw):
    base = dict(tool="claude_code", key="k", ts=(NOW - timedelta(hours=1)).isoformat(), model="claude-sonnet-5")
    base.update(kw); return CompactEvent(**base)

def test_dedupe_and_windows():
    events = [
        ev(key="a", input=100, output=10, tool_calls={"Edit": 1}),
        ev(key="a", input=100, output=40, tool_calls={"Read": 1}),          # same message, later line
        ev(key="b", model="claude-haiku-4-5", input=50, output=50, ts=(NOW - timedelta(days=3)).isoformat()),
        ev(key="old", input=999, output=999, ts=(NOW - timedelta(days=20)).isoformat()),
        ev(key="t1", model="", turn_start=1), ev(key="ab", model="", aborted=1),
        ev(key="cx", tool="codex", model="gpt-6.1-sol", input=200, cache_read=800, output=50),
    ]
    p = build_profile(events, NOW)
    assert p.usage_by_model_7d["claude-sonnet-5"] == {"tokens": 140, "cost": round(event_cost(ev(input=100, output=40)), 6), "requests": 1}
    assert p.tool_calls_14d == {"Edit": 1, "Read": 1}
    assert "old" not in str(p.usage_by_model_7d) and p.turns_14d == 1 and p.aborted_14d == 1
    assert p.light_token_share_14d == round(100 / (140 + 100 + 250), 4)
    assert abs(p.cache_hit_rate_7d - 800 / (100 + 50 + 200 + 800)) < 1e-6
    assert set(p.by_tool) == {"claude_code", "codex"}
    assert p.by_tool["codex"]["7d"]["tokens"] == 250

def test_dimensions_four_keys():
    dims = dimensions(build_profile([], NOW))
    assert [d.key for d in dims] == ["routing", "timing", "context", "leverage"]
```

(Store `cost` rounded to 6 decimals and `light_token_share_14d` rounded to 4.)
- [ ] **Step 2–4:** FAIL → implement → PASS + full suite. **Step 5: Commit** `feat(engine): profile builder with dedupe and time windows`

---

### Task 8: Content (zh / en)

**Files:**
- Create: `agentfit/engine/content.py`, `tests/engine/test_content.py`

**Interfaces — Produces:** `QUESTS: list[str]` (ordered keys), `quest_text(key, locale) -> dict(title, why, steps: list[str], prompt)`, `dimension_tip(key, locale) -> dict(title, why, steps, prompt)`, `POOL: list[str]` ids + `pool_tip(id, locale) -> dict`, `rank_title(level:int, locale) -> str`, `label(name, locale) -> str` for `routing|timing|context|leverage|tool_unavailable|no_tools`. `locale_from_env() -> "zh"|"en"` (reads `LANG`/`LC_ALL`, or `defaults read -g AppleLanguages` is NOT allowed — env only; App passes `--locale`).

Use exactly this copy (`QUESTS` order = table order):

| key | zh title | zh why | zh steps | zh prompt |
|---|---|---|---|---|
| first_edit | 出生点：让 AI 动手改一次文件 | 让 AI 真正改动文件，才算开始用起来。 | 在一个项目目录里打开 Claude Code / Codex；让它改一个小地方；看一眼它改了什么 | 请在当前项目里做一个小改动：找到 README（没有就新建），在末尾加一行今天的日期和一句项目简介，改完告诉我改了哪里。 |
| rules_file | 立规矩：写第一份 CLAUDE.md | CLAUDE.md / AGENTS.md 是 AI 每次开工先读的说明书，写一次长期生效。 | 让 AI 读项目结构；生成 CLAUDE.md 草稿；你删改后保存在项目根目录 | 请阅读当前项目结构，帮我写一份 CLAUDE.md：项目简介、常用命令（安装/运行/测试）、代码风格约定、不要做的事，控制在 60 行以内，写完给我看。 |
| light_model | 会分工：机械活交给轻量模型 | 格式转换、批量提取这类活用轻量模型更快，也更省额度。 | 输入 /model 看可选模型；机械任务切到最轻的一档；复杂设计再切回来 | 接下来这个任务是机械性的（批量整理/格式转换），请用最轻量的模型完成；如果当前不是轻量模型，告诉我怎么用 /model 切换。 |
| first_skill | 第一件装备：真正用起一个 skill | skill 把常干的活固化成一句话就能调用的能力。 | 看看已安装的 skill；挑一个最贴近你项目的；用它完成一个小任务 | 请列出我当前已安装的 skill，挑一个最适合这个项目的，说明它能做什么，然后用它完成一个小任务。 |
| parallel | 会并行：让子代理同时干活 | 子代理可以同时查好几处，主对话保持清爽。 | 把一个任务拆成两件互不依赖的事；让 AI 用子代理并行做；看汇总结果 | 请启动子代理并行完成两件事：A 梳理项目目录结构，B 找出所有 TODO 注释；完成后汇总给我。 |
| less_rework | 少返工：先对齐再动手 | 中断和反复重试最浪费；先说清目标和验收标准。 | 开工前让 AI 复述目标；确认验收标准；再让它动手 | 开始之前，请先用三句话复述你理解的任务目标、验收标准和打算的步骤，等我确认后再动手。 |
| automation | 自动化：配置第一个 hook | hook 让固定动作自动发生，比如改完代码自动跑测试。 | 选一个每次都要做的动作；让 AI 配成 hook；改一次文件验证它触发 | 请帮我配置一个 Claude Code hook：每次你改完文件后自动运行本项目的格式化或测试命令。先告诉我要改哪个配置文件、写什么，我确认后再写入。 |
| declutter | 断舍离：清理用不上的 skill | 装太多 skill 会挤占上下文，用不上的就该卸掉。 | 列出所有 skill；标出两周没用过的；自己决定卸载哪些 | 请列出 ~/.claude/skills 下的所有 skill，标出最近两周没用过的，给我一份建议卸载清单（只列出，不要删除）。 |
| graduate | 出师：四维全面达标 | 模型分工、作息、上下文、复用四项都 ≥85 分，你已经出师。 | 看四维里最低的一项；照今日一招练一周；再体检 | 请根据我最近的使用习惯，指出我在模型选择、作息、上下文管理、复用沉淀四方面最弱的一项，并给我一个本周练习计划。 |

| key | en title | en why | en steps | en prompt |
|---|---|---|---|---|
| first_edit | Spawn point: let the AI edit a file | You've really started once the AI changes a file for you. | Open Claude Code / Codex in a project; ask for one small change; review the diff | Make a small change in this project: open README (create it if missing), append today's date and a one-line project summary, then tell me exactly what you changed. |
| rules_file | House rules: write your first CLAUDE.md | CLAUDE.md / AGENTS.md is the brief your AI reads before every task — write it once, benefit forever. | Let the AI read the project; generate a draft; trim it and save it at the repo root | Read this project's structure and write a CLAUDE.md: summary, common commands (install/run/test), code style, and things not to do. Keep it under 60 lines and show me. |
| light_model | Delegate: give chores to a light model | Light models do formatting and bulk extraction faster and save quota. | Type /model to see options; switch to the lightest for chores; switch back for design work | The next task is mechanical (bulk cleanup / format conversion). Use the lightest model; if you aren't on one, tell me how to switch with /model. |
| first_skill | First gear: actually use a skill | A skill turns a recurring job into a one-line command. | List installed skills; pick the one closest to your project; use it on a small task | List the skills I have installed, pick the best one for this project, explain what it does, then use it on a small task. |
| parallel | Go parallel: put sub-agents to work | Sub-agents look in several places at once and keep your main chat clean. | Split a task into two independent parts; ask for sub-agents; read the summary | Start sub-agents to do two things in parallel: A) map the project structure, B) find every TODO comment. Then summarize both for me. |
| less_rework | Less rework: align before acting | Interruptions and blind retries waste the most; state the goal and acceptance first. | Ask the AI to restate the goal; agree on acceptance criteria; then let it work | Before starting, restate in three sentences the goal, the acceptance criteria, and your planned steps. Wait for my confirmation before acting. |
| automation | Automate: set up your first hook | Hooks make routine steps automatic, e.g. run tests after every edit. | Pick a step you always repeat; have the AI configure it as a hook; edit a file to see it fire | Configure a Claude Code hook that runs this project's formatter or tests after you edit files. First tell me which config file and what you'll add; write it only after I confirm. |
| declutter | Declutter: drop skills you don't use | Too many skills crowd the context; remove the ones you never use. | List all skills; mark the ones unused for two weeks; decide what to remove | List every skill under ~/.claude/skills, mark those unused in the last two weeks, and give me a suggested removal list (list only — don't delete anything). |
| graduate | Graduate: all four dimensions on target | Routing, timing, context and reuse are all ≥85 — you've graduated. | Find your lowest dimension; practise today's tip for a week; re-check | Based on my recent usage, tell me which of model choice, timing, context management and reuse is weakest, and give me a one-week practice plan. |

Dimension tips (`routing`, `timing`, `context`, `leverage`):

| key | zh title / why / prompt | en title / why / prompt |
|---|---|---|
| routing | 模型分工再优化 / 旗舰模型留给难题，日常用均衡档，杂活用轻量档。 / 请根据我接下来要做的三件事，分别建议用哪一档模型，并说明理由。 | Tune model routing / Save the flagship for hard problems; use balanced for daily work and light for chores. / For the next three things I'm going to do, recommend which model tier to use for each and why. |
| timing | 固定 AI 工作时段 / 零散使用要反复交代背景，攒在固定时段批量处理更省。 / 请帮我把今天零散的 AI 任务整理成两个集中时段的清单。 | Batch your AI time / Scattered use means re-explaining context; batching into fixed slots is cheaper. / Turn my scattered AI tasks for today into two focused time-block lists. |
| context | 管好上下文 / 一个任务一个会话，长会话及时开新的，常用背景写进 CLAUDE.md。 / 请总结当前会话的结论和待办，写成一段可以粘到新会话开头的交接说明。 | Keep context clean / One task per session; start fresh when it gets long; put recurring background in CLAUDE.md. / Summarize this session's conclusions and open items as a hand-off note I can paste into a new session. |
| leverage | 把重复的活沉淀下来 / 同一件事做第三次时，就把它写成 skill 或模板。 / 请找出我最近重复做过的一类任务，把它写成一个可复用的 skill 草稿。 | Turn repeats into assets / The third time you do something, make it a skill or template. / Find a task I've repeated recently and draft a reusable skill for it. |

(steps for dimension tips: zh `["看一眼原因", "复制下面的指令给 AI", "明天再看分数变化"]`; en `["Read why", "Paste the prompt below to your AI", "Check the score again tomorrow"]`.)

Pool (after graduation), ids `fresh_session`, `background_agent`, `privacy_check`:
- fresh_session — zh「长会话记得开新会话，省钱又提质」/ 会话越长，每次请求都在为历史付费，注意力也被稀释。 / en "Start fresh sessions" / Long sessions pay for history on every request and dilute attention.
- background_agent — zh「批量任务交给后台 agent，你只看结果」/ 翻译、清洗一批数据这类活，让 agent 在后台跑完再叫你。 / en "Hand batch jobs to a background agent" / Let an agent run translations or data cleanup in the background and ping you when done.
- privacy_check — zh「任何要读你聊天记录的 AI 产品，先问三件事」/ 数据存哪、是否用于训练、能否一键删除。 / en "Three questions before granting an AI app your chat history" / Where is data stored, is it used for training, can you delete it in one click.
(pool prompt: zh/en "请就这一条，结合我的使用方式给我一个具体建议。" / "Give me one concrete suggestion on this, based on how I work.")

Rank titles by level (number of passed quests): 0–2 → zh `AI 探索者` / en `Explorer`; 3–5 → `AI 熟练者` / `Practitioner`; 6–8 → `AI 大师` / `Master`; 9 → `AI 宗师` / `Grandmaster`.
Labels: routing 模型路由/Routing, timing 时间习惯/Timing, context 上下文卫生/Context, leverage 沉淀复用/Reuse, tool_unavailable 该工具数据暂不可用/Data temporarily unavailable, no_tools 还没检测到 Claude Code 或 Codex。先安装一个，再回来体检。/No Claude Code or Codex found yet. Install one, then come back.

- [ ] **Step 1: Failing test:**

```python
import pytest
from agentfit.engine import content as C

@pytest.mark.parametrize("loc", ["zh", "en"])
def test_every_entry_complete(loc):
    assert C.QUESTS == ["first_edit","rules_file","light_model","first_skill","parallel","less_rework","automation","declutter","graduate"]
    for k in C.QUESTS:
        t = C.quest_text(k, loc); assert t["title"] and t["why"] and len(t["steps"]) == 3 and t["prompt"]
    for k in ["routing","timing","context","leverage"]:
        t = C.dimension_tip(k, loc); assert t["title"] and t["prompt"] and C.label(k, loc)
    for pid in C.POOL: assert C.pool_tip(pid, loc)["title"]
    assert [C.rank_title(n, loc) for n in (0, 3, 6, 9)] == (["AI 探索者","AI 熟练者","AI 大师","AI 宗师"] if loc == "zh" else ["Explorer","Practitioner","Master","Grandmaster"])

def test_no_money_saving_claims():
    import inspect; src = inspect.getsource(C)
    for bad in ("省了 $", "save $", "saved $", "每月可省"): assert bad not in src

def test_locale_from_env(monkeypatch):
    monkeypatch.setenv("LANG", "zh_CN.UTF-8"); monkeypatch.delenv("LC_ALL", raising=False); assert C.locale_from_env() == "zh"
    monkeypatch.setenv("LANG", "ja_JP.UTF-8"); assert C.locale_from_env() == "en"
```

- [ ] **Step 2–4:** FAIL → implement (zh steps split on `；`) → PASS + full suite. **Step 5: Commit** `feat(engine): zh/en master content`

---

### Task 9: Village — quests, progress, rank, today tip

**Files:**
- Create: `agentfit/engine/village.py`, `tests/engine/test_village.py`

**Interfaces — Produces:**

```python
def evaluate(p: Profile, inv: dict[str, Inventory], dims: list[DimensionScore]) -> dict[str, tuple[bool, str]]
    # quest key -> (met_now, progress_hint_code)
def advance(met: dict[str, tuple[bool, str]], progress_path: Path, now: datetime) -> dict
    # loads/saves progress.json {"passed": {key: iso}, "regress_notified": [keys]}
    # sequential: walk QUESTS in order; a quest can be newly passed only if all previous are passed.
    # returns {"passed": {...}, "current": key|None, "regressed": [keys newly regressed & not yet notified]}
def today_tip(state: dict, dims: list[DimensionScore], locale: str, today: date) -> dict
    # -> {"title","why","steps","prompt_for_claude","source":{"kind":"quest|dimension|pool","ref":key}}
def village_block(state: dict, met: dict, locale: str) -> dict   # snapshot["village"]
```

Quest conditions (`met_now`), 14-day window, inventories summed across tools:

| key | condition |
|---|---|
| first_edit | `tool_calls_14d.get("Edit",0) + tool_calls_14d.get("Write",0) + tool_calls_14d.get("apply_patch",0) >= 1` |
| rules_file | `max(inv.instructions_bytes) > 200` |
| light_model | `light_token_share_14d > 0.05` |
| first_skill | `any(v >= 3 for v in skill_calls_14d.values())` |
| parallel | `sidechain_14d >= 1` (Profile counts usage or marker events with `sidechain=True`) |
| less_rework | `turns_14d >= 10 and aborted_14d / turns_14d < 0.10 and not rule_hits()["RULE_ERROR_RETRY_LOOP"]` |
| automation | `sum(inv.hooks) >= 1 and hook_success_14d >= 1` |
| declutter | installed = union of skills_installed; used = installed names n where any call key `k == n or k.split(":")[-1] == n`; pass if `not installed or len(used)/len(installed) >= 0.5` |
| graduate | `all(d.score >= 85 for d in dims)` |

`progress_hint_code` is `""` when met, otherwise one of `"need_data"` (less_rework with turns_14d < 10) or `"not_yet"`.
Today tip: if `current` exists and its condition is not met → quest tip for `current`; else if any dim < 85 → tip for the lowest dim (ties: order routing,timing,context,leverage); else pool tip `POOL[today.toordinal() % len(POOL)]`. Deterministic for the same inputs and date. Snapshot quest status: `passed` (in progress.passed), `current`, else `locked`.

- [ ] **Step 1: Failing test** — `tests/engine/test_village.py`:

```python
from datetime import datetime, timezone, date, timedelta
from agentfit.engine.events import CompactEvent
from agentfit.engine.profile import build_profile
from agentfit.engine.inventory import Inventory
from agentfit.models.checkup import DimensionScore
from agentfit.engine import village as V

NOW = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
def dims(*s): return [DimensionScore(key=k, label=k, score=v) for k, v in zip(["routing","timing","context","leverage"], s)]
def inv(**kw):
    base = dict(skills_installed=[], instructions_bytes=0, hooks=0, mcp_servers=0, subagents=0, plugins=0); base.update(kw)
    return {"claude_code": Inventory(**base)}
def prof(**tool_calls):
    return build_profile([CompactEvent(tool="claude_code", key="a", ts=(NOW - timedelta(hours=1)).isoformat(), model="claude-sonnet-5", input=10, output=10, tool_calls=tool_calls)], NOW)

def test_sequential_unlock_and_persistence(tmp_path):
    pp = tmp_path / "progress.json"
    met = V.evaluate(prof(Edit=1), inv(instructions_bytes=500), dims(90,90,90,90))
    assert met["first_edit"][0] and met["rules_file"][0] and not met["light_model"][0]
    st = V.advance(met, pp, NOW)
    assert set(st["passed"]) == {"first_edit", "rules_file"} and st["current"] == "light_model"
    met2 = V.evaluate(prof(), inv(), dims(90,90,90,90))       # regressed: no edits, no CLAUDE.md
    st2 = V.advance(met2, pp, NOW)
    assert set(st2["passed"]) == {"first_edit", "rules_file"}  # never taken away
    assert set(st2["regressed"]) == {"first_edit", "rules_file"}
    assert V.advance(met2, pp, NOW)["regressed"] == []         # notified only once

def test_later_quest_not_passed_before_earlier(tmp_path):
    met = V.evaluate(prof(), inv(instructions_bytes=500), dims(90,90,90,90))   # rules_file met, first_edit not
    st = V.advance(met, tmp_path / "p.json", NOW)
    assert st["passed"] == {} and st["current"] == "first_edit"

def test_declutter_and_empty_install():
    assert V.evaluate(prof(), inv(), dims(90,90,90,90))["declutter"][0] is True
    p = build_profile([CompactEvent(tool="claude_code", key="s", ts=NOW.isoformat(), model="m", skill_calls={"plug:tdd": 3})], NOW)
    assert V.evaluate(p, inv(skills_installed=["tdd", "x", "y"]), dims(90,90,90,90))["declutter"][0] is False
    assert V.evaluate(p, inv(skills_installed=["tdd", "x"]), dims(90,90,90,90))["declutter"][0] is True
    assert V.evaluate(p, inv(), dims(90,90,90,90))["first_skill"][0] is True

def test_today_tip_order_and_determinism(tmp_path):
    st = {"passed": {}, "current": "first_edit", "regressed": []}
    t = V.today_tip(st, dims(90,90,90,90), "zh", date(2026,10,21))
    assert t["source"] == {"kind": "quest", "ref": "first_edit"} and t["prompt_for_claude"]
    done = {"passed": {k: "x" for k in V.QUESTS}, "current": None, "regressed": []}
    assert V.today_tip(done, dims(90,60,70,90), "en", date(2026,10,21))["source"] == {"kind": "dimension", "ref": "timing"}
    a = V.today_tip(done, dims(90,90,90,90), "en", date(2026,10,21)); b = V.today_tip(done, dims(90,90,90,90), "en", date(2026,10,21))
    assert a == b and a["source"]["kind"] == "pool"
```

(Import `QUESTS` into `village` from `content` so `V.QUESTS` works.)
- [ ] **Step 2–4:** FAIL → implement → PASS + full suite. **Step 5: Commit** `feat(engine): newbie village quests, progress and today tip`

---

### Task 10: Snapshot + engine entry point + privacy guard

**Files:**
- Create: `agentfit/engine/snapshot.py`, `agentfit/engine/__main__.py`, `tests/engine/test_snapshot.py`, `tests/engine/test_privacy.py`
- Modify: `agentfit/engine/collectors/__init__.py` — import all five collector modules so `REGISTRY` is populated.

**Interfaces — Produces:** `build_snapshot(home: Path, state_dir: Path, locale: str, now: datetime | None = None, enabled: set[str] | None = None) -> dict` matching the spec §6 schema with `"schema": 1`. CLI: `python -m agentfit.engine snapshot --json [--home PATH] [--state-dir PATH] [--locale zh|en] [--tools claude_code,codex,...]` prints the JSON (UTF-8, `ensure_ascii=False`) and exits 0; any uncaught exception → prints `{"schema":1,"error":"<ExceptionType>"}` and exits 2.

Assembly: for each enabled registered collector: `detected = c.detect(home)`; if detected, `events += c.scan(home, state)` inside try/except → on error set `tools[i].error = "unavailable"` (never the message). Prune state events older than 30 days, save state. Build profile, inventories (Claude gets `profile.project_dirs_14d`), dims, `overall = {"score": overall_from_dimensions(dims), "tier": tier_for_score(...)}`, quests via village (progress at `state_dir/progress.json`), `today_tip`, `quota = {"codex": latest_rate_limits(home)}`, `inventory = {tool: inv.to_public()}`, `notices` (codes: `"no_tools"` when no deep tool detected; `"regressed:<key>"` per regression). Dimension labels via `content.label(key, locale)`. Tools list entries: `{"tool","tier","detected","error","usage_today","usage_7d","by_model"}` (from `profile.by_tool`, zeros if absent).

- [ ] **Step 1: Failing tests** — `tests/engine/test_snapshot.py`:

```python
import json, shutil, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path
from agentfit.engine.snapshot import build_snapshot

FIX = Path(__file__).parent / "fixtures"
NOW = datetime(2026, 10, 20, 12, tzinfo=timezone.utc)

def _home(tmp_path):
    home = tmp_path / "home"
    shutil.copytree(FIX / "claude", home / ".claude"); shutil.copytree(FIX / "codex", home / ".codex")
    return home

def test_snapshot_shape(tmp_path):
    s = build_snapshot(_home(tmp_path), tmp_path / "state", "zh", now=NOW)
    assert s["schema"] == 1 and s["locale"] == "zh"
    assert {t["tool"] for t in s["tools"] if t["detected"]} == {"claude_code", "codex"}
    assert [d["key"] for d in s["dimensions"]] == ["routing", "timing", "context", "leverage"]
    assert s["dimensions"][0]["label"] == "模型路由"
    assert len(s["village"]["quests"]) == 9 and s["village"]["rank_title"].startswith("AI")
    assert s["today_tip"]["prompt_for_claude"]
    assert s["quota"]["codex"]["primary_pct"] == 42.5
    assert s["overall"]["tier"] in {"S", "A", "B", "C"}

def test_no_content_or_paths_leak(tmp_path):
    raw = json.dumps(build_snapshot(_home(tmp_path), tmp_path / "state", "en", now=NOW), ensure_ascii=False)
    for needle in ("please fix the bug", "/tmp/demo", "/tmp/x", str(tmp_path), "Request interrupted"):
        assert needle not in raw

def test_empty_home_notice(tmp_path):
    s = build_snapshot(tmp_path / "empty", tmp_path / "state", "en", now=NOW)
    assert "no_tools" in s["notices"]

def test_cli_entry(tmp_path):
    out = subprocess.run([sys.executable, "-m", "agentfit.engine", "snapshot", "--json", "--home", str(_home(tmp_path)),
                          "--state-dir", str(tmp_path / "st"), "--locale", "en"], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert json.loads(out.stdout)["schema"] == 1
```

`tests/engine/test_privacy.py`:

```python
import re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
BANNED = re.compile(r"\b(import (urllib|http\.client|requests|httpx|socket)|from (urllib|http|requests|httpx|socket)\b|URLSession|NWConnection)")

def _files():
    yield from (ROOT / "agentfit" / "engine").rglob("*.py")
    yield from (ROOT / "macos").rglob("*.swift")

def test_no_network_code():
    hits = [str(p) for p in _files() if BANNED.search(p.read_text(encoding="utf-8"))]
    assert hits == []

def test_no_credential_paths():
    for p in (ROOT / "agentfit" / "engine").rglob("*.py"):
        t = p.read_text(encoding="utf-8")
        assert "auth.json" not in t and ".credentials" not in t and "Keychain" not in t, p
```

- [ ] **Step 2–4:** FAIL → implement → PASS + full suite.
- [ ] **Step 5: Real-machine smoke (read-only):** `.venv/bin/python -m agentfit.engine snapshot --json --state-dir /tmp/365st | head -c 1500` → valid JSON with real tools detected. Do not commit any real output.
- [ ] **Step 6: Commit** `feat(engine): snapshot assembly, CLI entry and privacy guard`

---

### Task 11: Engine binary (PyInstaller)

**Files:**
- Create: `scripts/build_engine.sh`, `scripts/engine_entry.py`
- Modify: `.gitignore` (add `build/`, `dist/`, `*.spec`)

`scripts/engine_entry.py`:

```python
from agentfit.engine.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
```
(`agentfit/engine/__main__.py` must expose `def main(argv: list[str] | None = None) -> int` and call it under `if __name__ == "__main__"`.)

`scripts/build_engine.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
uv run --python 3.12 --with pyinstaller --with "pydantic>=2" \
  pyinstaller --onefile --name 365engine --clean --noconfirm \
  --exclude-module fastapi --exclude-module sqlalchemy --exclude-module cloud \
  scripts/engine_entry.py
ls -lh dist/365engine
```

- [ ] **Step 1:** `chmod +x scripts/build_engine.sh && scripts/build_engine.sh` → `dist/365engine` exists.
- [ ] **Step 2: No-Python smoke:** `env -i HOME="$HOME" PATH=/usr/bin:/bin ./dist/365engine snapshot --json --state-dir /tmp/365st2 | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['schema'], len(d['tools']))"` → prints `1 5`. (`env -i` strips the venv/PATH so the binary cannot lean on a Python install.)
- [ ] **Step 3:** Record binary size in the commit message. **Commit** `build: one-file engine binary via PyInstaller`

---

### Task 12: SwiftUI menu-bar app

**Files:**
- Create: `macos/Package.swift`, `macos/Sources/AIMaster/{AIMasterApp.swift, StatusItemController.swift, Snapshot.swift, EngineRunner.swift, SnapshotStore.swift, PopoverView.swift, TipCard.swift, VillageGrid.swift, DimensionRings.swift, UsageSection.swift, SettingsView.swift}`, `macos/Resources/en.lproj/Localizable.strings`, `macos/Resources/zh-Hans.lproj/Localizable.strings`, `macos/Tests/AIMasterTests/SnapshotDecodingTests.swift`, `macos/Tests/AIMasterTests/Fixtures/snapshot.json` (generate with `python -m agentfit.engine snapshot --json --home <fixture home from Task 10> --locale zh`)
- Reference only (do not modify): `~/Documents/724.fund-research/macos-app/` — reuse its `StatusItemController` popover pattern.

`macos/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "AIMaster",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AIMaster", path: "Sources/AIMaster", resources: [.process("../../Resources")]),
        .testTarget(name: "AIMasterTests", dependencies: ["AIMaster"], path: "Tests/AIMasterTests", resources: [.copy("Fixtures")]),
    ]
)
```
(If SwiftPM rejects the `../../Resources` path, move `Resources/` to `Sources/AIMaster/Resources/` and use `.process("Resources")`.)

`Snapshot.swift` — `Decodable` mirror of spec §6 (all optional where the engine may emit null):

```swift
struct Snapshot: Decodable {
    let schema: Int
    let generatedAt: String?
    let locale: String?
    let tools: [ToolUsage]?
    let quota: Quota?
    let dimensions: [Dimension]?
    let overall: Overall?
    let village: Village?
    let todayTip: Tip?
    let notices: [String]?
    let error: String?
}
struct ToolUsage: Decodable, Identifiable { var id: String { tool }; let tool: String; let tier: String; let detected: Bool; let error: String?; let usageToday: Usage?; let usage7d: Usage?; let byModel: [ModelUsage]? }
struct Usage: Decodable { let tokens: Int; let costUsd: Double }
struct ModelUsage: Decodable, Identifiable { var id: String { model }; let model: String; let tokens: Int; let costUsd: Double }
struct Quota: Decodable { let codex: CodexQuota? }
struct CodexQuota: Decodable { let primaryPct: Double; let primaryWindowMin: Int?; let primaryResetsAt: String?; let secondaryPct: Double?; let secondaryWindowMin: Int?; let secondaryResetsAt: String?; let planType: String? }
struct Dimension: Decodable, Identifiable { var id: String { key }; let key: String; let label: String; let score: Int }
struct Overall: Decodable { let score: Int; let tier: String }
struct Village: Decodable { let current: String?; let rankTitle: String; let quests: [Quest] }
struct Quest: Decodable, Identifiable { var id: String { key }; let key: String; let title: String; let status: String; let passedAt: String?; let progressHint: String? }
struct Tip: Decodable { let title: String; let why: String; let steps: [String]; let promptForClaude: String; let source: TipSource }
struct TipSource: Decodable { let kind: String; let ref: String }
// Decode with: let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
```
(Engine keys `usage_7d` → `usage7d` with convertFromSnakeCase: verify in the decoding test; if it maps to `usage7D`, add explicit `CodingKeys` for that field.)

`EngineRunner.swift`:

```swift
import Foundation
enum EngineError: Error { case missing, failed(Int32), badJSON }
struct EngineRunner {
    /// Bundled engine: Contents/Resources/365engine. Dev fallback: env AIMASTER_ENGINE.
    static func engineURL() -> URL? {
        if let p = ProcessInfo.processInfo.environment["AIMASTER_ENGINE"] { return URL(fileURLWithPath: p) }
        return Bundle.main.url(forResource: "365engine", withExtension: nil)
    }
    static func run(locale: String, tools: [String]) throws -> Snapshot {
        guard let url = engineURL() else { throw EngineError.missing }
        let p = Process(); p.executableURL = url
        p.arguments = ["snapshot", "--json", "--locale", locale, "--tools", tools.joined(separator: ",")]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        guard let snap = try? dec.decode(Snapshot.self, from: data) else { throw EngineError.badJSON }
        if p.terminationStatus != 0 { throw EngineError.failed(p.terminationStatus) }
        return snap
    }
}
```

`SnapshotStore.swift` — `@MainActor final class SnapshotStore: ObservableObject` with `@Published var snapshot: Snapshot?`, `@Published var lastError: String?`, `@Published var lastRun: Date?`; `refresh()` runs `EngineRunner.run` on a background `Task.detached`, keeps the previous snapshot on failure (spec: show stale data with timestamp); a `Timer` every `UserDefaults "refreshSeconds"` (default 60). Locale: `Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"`. Enabled tools from `UserDefaults "enabledTools"` (default all five).

`StatusItemController.swift` — `NSStatusItem` whose button title is the current quest number in a circle (`"①"…"⑨"`, `"✓"` after graduation, `"○"` with no data) plus `" •"` when today's tip source is a quest not yet met; popover 360×560 hosting `PopoverView`.

`PopoverView.swift` — vertical stack: `TipCard` (title, why, numbered steps, buttons **Copy prompt** → `NSPasteboard.general.setString(tip.promptForClaude, forType: .string)` and **Check now** → `store.refresh()`), `VillageGrid` (3×3 cells: passed = filled, current = outlined accent, locked = dimmed; caption `rankTitle`), `DimensionRings` (4 small rings with label + score), `UsageSection` (per detected tool: today / 7d tokens and "≈$x (API-equivalent)" / "≈$x（折算）"; Codex quota bar `primaryPct`), footer (last run time, Settings, Quit). Notice `no_tools` → replace the body with the install guidance text from the snapshot labels. Stale data → footer shows "Updated HH:mm (stale)".

`SettingsView.swift` — toggles per tool (writes `enabledTools`), refresh interval picker (30/60/300 s), "Launch at login" via `SMAppService.mainApp.register()/unregister()`, "View my snapshot" (sheet with pretty-printed JSON of the last run), and a static line: "This app makes no network connections." / 「本应用不联网。」

`Localizable.strings` — only chrome strings: Copy prompt / 复制给 Claude 的指令, Check now / 做完了，帮我检查, Settings / 设置, Quit / 退出, Updated / 更新于, stale / 数据可能过期, Launch at login / 开机启动, View my snapshot / 查看我的快照, This app makes no network connections. / 本应用不联网。, Refresh interval / 刷新间隔.

`SnapshotDecodingTests.swift`:

```swift
import XCTest
@testable import AIMaster
final class SnapshotDecodingTests: XCTestCase {
    func testDecodesEngineFixture() throws {
        let url = Bundle.module.url(forResource: "snapshot", withExtension: "json", subdirectory: "Fixtures")!
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        let s = try dec.decode(Snapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(s.schema, 1)
        XCTAssertEqual(s.village?.quests.count, 9)
        XCTAssertFalse(s.todayTip?.promptForClaude.isEmpty ?? true)
        XCTAssertEqual(s.quota?.codex?.primaryPct, 42.5)
    }
}
```

- [ ] **Step 1:** Generate the fixture JSON; write `SnapshotDecodingTests`; `cd macos && swift test` → FAIL (types missing).
- [ ] **Step 2:** Implement `Snapshot.swift` → `swift test` PASS.
- [ ] **Step 3:** Implement the remaining files; `swift build` succeeds with zero errors.
- [ ] **Step 4:** Dev run: `AIMASTER_ENGINE=$PWD/../dist/365engine swift run AIMaster &` → a menu-bar item appears; kill it after checking. Run `pytest tests/engine/test_privacy.py` (now also scans `macos/`).
- [ ] **Step 5: Commit** `feat(macos): SwiftUI menu-bar app rendering engine snapshot`

---

### Task 13: App bundle packaging

**Files:**
- Create: `scripts/package_app.sh`, `macos/Info.plist`

`macos/Info.plist` keys: `CFBundleName`=`365 AI Master`, `CFBundleIdentifier`=`com.tonyzhao.365aimaster`, `CFBundleExecutable`=`AIMaster`, `CFBundleShortVersionString`=`0.4.0`, `CFBundleVersion`=`1`, `LSMinimumSystemVersion`=`13.0`, `LSUIElement`=`true`, `CFBundleDevelopmentRegion`=`en`, `CFBundleLocalizations`=`[en, zh-Hans]`.

`scripts/package_app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x dist/365engine ] || scripts/build_engine.sh
( cd macos && swift build -c release )
APP="dist/365 AI Master.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp macos/Info.plist "$APP/Contents/Info.plist"
cp macos/.build/release/AIMaster "$APP/Contents/MacOS/AIMaster"
cp -R macos/.build/release/AIMaster_AIMaster.bundle "$APP/Contents/Resources/" 2>/dev/null || true
cp dist/365engine "$APP/Contents/Resources/365engine"
codesign --force --deep --sign - "$APP"   # ad-hoc; real signing needs Kenichi's Developer ID
echo "built: $APP"
```

- [ ] **Step 1:** `chmod +x scripts/package_app.sh && scripts/package_app.sh` → `dist/365 AI Master.app` exists; `ls "dist/365 AI Master.app/Contents/Resources/365engine"`.
- [ ] **Step 2:** `open "dist/365 AI Master.app"`; verify (via `pgrep -f "365 AI Master.app"`) it is running; then `pkill -f "365 AI Master.app"`.
- [ ] **Step 3: Commit** `build: package 365 AI Master.app with embedded engine`

---

## Snapshot schema

Authoritative: spec §6. Additions fixed by this plan: `tools[].error` is `null` or `"unavailable"`; `village.quests[].progress_hint` is `""`, `"need_data"` or `"not_yet"`; `notices` are codes (`"no_tools"`, `"regressed:<key>"`); top-level `error` only on engine failure.

## Self-review notes (plan author)

- Spec coverage: §3 → Tasks 2–6; §4 → 7–9; §5 → 12; §6 → 10; §8 privacy → 10/12; §8 packaging → 11/13; §9 branch/WIP constraint → Global Constraints. Spec §7 location change (`agentfit/engine/` instead of `agentfit/collector/`) is deliberate (WIP conflict) and noted above.
- Spec §7 also listed a `365aimaster snapshot` CLI subcommand; replaced by `python -m agentfit.engine snapshot` so `agentfit/cli.py` (WIP) stays untouched.

---

# Phase 2 — v2 redesign (spec §11)

Global Constraints still apply, with ONE amendment: `macos/Sources/AIMaster/ContentUpdater.swift` is the only file allowed to use the network (`URLSession`), for a single plain HTTPS GET of the fixed content URL. The engine stays network-free. Update `tests/engine/test_privacy.py` accordingly (Task 16).

### Task 14: Content file — schema, bundled default, loader

**Files:** Create `agentfit/engine/content_pool.json`, `content/daily.json` (identical copy — the public file), `agentfit/engine/content_pool.py`, `tests/engine/test_content_pool.py`. Add `agentfit/engine/content_pool.json` to PyInstaller data in `scripts/build_engine.sh` (`--add-data agentfit/engine/content_pool.json:agentfit/engine`).

**Schema (version 1):**
```json
{"version": 1, "updated_at": "2026-10-21",
 "skills": [{"id": "web_search", "level": 1, "detect": "tool:WebSearch",
             "title": {"zh": "", "en": ""}, "why": {"zh": "", "en": ""}, "prompt": {"zh": "", "en": ""}}],
 "rankings": {"skill": [{"name": "", "url": "", "tagline": {"zh": "", "en": ""}, "match": []}],
              "agent": [{"name": "", "url": "", "tagline": {"zh": "", "en": ""}, "match": []}]},
 "tips": [{"id": "", "title": {"zh": "", "en": ""}, "detail": {"zh": "", "en": ""}, "source": ""}]}
```
`detect` grammar: `tool:<ToolName>` | `mcp` | `skill_any` | `sidechain` | `hook` | `light_model` | `effort:<v1>|<v2>` | `compaction` | `instructions:claude` | `instructions:codex` | `self`.
`match`: inventory skill names that mean "installed" (may be empty).

**Interfaces — Produces:** `load_content(path: Path | None) -> dict` — if `path` is given, exists, parses, has `version == 1` and passes `validate(d)`, return it; otherwise return the bundled file (loaded via `importlib.resources` / `Path(__file__).with_name(...)`, works inside PyInstaller). `validate(d) -> bool`: every skill has id/level/detect/title/why/prompt with both zh and en non-empty, detect matches the grammar, ids unique; rankings and tips have zh+en text.

**Skill cards** (exact copy; order = recommendation order):

| id | detect | zh title / why / prompt | en title / why / prompt |
|---|---|---|---|
| rules_file | instructions:claude | 写一份 CLAUDE.md / AI 每次开工先读它，写一次长期省事 / 请读一下这个项目，帮我写一份 60 行以内的 CLAUDE.md，写完给我看 | Write a CLAUDE.md / Your AI reads it before every task — write once, save time forever / Read this project and write a CLAUDE.md under 60 lines, then show me |
| web_search | tool:WebSearch | 让 AI 联网搜索 / 问最新的东西时让它先查再答，少编造 / 请先联网搜索这个问题的最新资料，再给我结论和出处：[你的问题] | Let the AI search the web / For anything recent, have it look things up first — fewer made-up answers / Search the web for the latest on this, then give me a conclusion with sources: [your question] |
| web_fetch | tool:WebFetch | 让 AI 读一个网页 / 贴个链接让它读完再总结，省得你自己翻 / 请读这个网页并用 5 条要点总结：[链接] | Have the AI read a page / Paste a link and let it read and summarize for you / Read this page and summarize it in 5 bullet points: [link] |
| plan_mode | tool:ExitPlanMode | Plan 模式：先出方案再动手 / 大改动前先看步骤，你点头再执行，返工更少 / 进入 Plan 模式（Shift+Tab 切换），先给我方案，不要改文件：[你的任务] | Plan mode: plan before acting / See the steps before big changes and approve them — less rework / Enter plan mode (Shift+Tab), give me a plan first and don't edit files: [your task] |
| todo_list | tool:TodoWrite | 让 AI 列任务清单 / 长任务拆成清单逐项打勾，不容易漏 / 请先把这个任务拆成一个待办清单，再一项项完成：[你的任务] | Let the AI keep a to-do list / Long tasks get split into a checklist so nothing is missed / Break this task into a to-do list first, then work through it item by item: [your task] |
| ask_first | tool:AskUserQuestion | 让 AI 先问你 / 需求不清时让它先提问，比猜错再改快 / 开始之前，如果有任何不确定的地方，先用选择题问我 | Let the AI ask first / When the request is fuzzy, questions beat wrong guesses / Before you start, ask me multiple-choice questions about anything unclear |
| subagent | sidechain | 子代理：同时开几条线 / 让子代理并行查资料，主对话保持清爽 / 请用子代理并行完成：A 梳理目录结构，B 找出所有 TODO，最后汇总给我 | Sub-agents: work in parallel / Sub-agents research side by side and keep your main chat clean / Use sub-agents in parallel: A) map the project structure, B) find all TODOs, then summarize |
| light_model | light_model | 机械活交给轻量模型 / 格式转换这类活用轻量档更快更省 / 这个任务是机械性的，请用最轻量的模型完成；如果当前不是，告诉我怎么用 /model 切换 | Give chores to a light model / Formatting-type work is faster and cheaper on a light tier / This task is mechanical — use the lightest model; if you aren't on one, tell me how to switch with /model |
| effort_up | effort:high\|xhigh\|max | 难题调高推理强度 / 架构和疑难调试时让它多想一会儿 / 这个问题比较难，请用更高的推理强度仔细想清楚再回答：[你的问题] | Raise reasoning effort for hard problems / Let it think longer on architecture and tricky bugs / This one is hard — use higher reasoning effort and think it through before answering: [your question] |
| first_skill | skill_any | 用起第一个 skill / 把常干的活变成一句话能调用的能力 / 请列出我装了哪些 skill，挑一个最适合这个项目的，用它完成一个小任务 | Use your first skill / Turn a recurring job into a one-line command / List the skills I have installed, pick the best one for this project, and use it on a small task |
| mcp | mcp | 用 MCP 连接外部工具 / 让 AI 直接读写 GitHub、文档等外部系统 / 请告诉我我已经连了哪些 MCP 工具，并用其中一个帮我完成一件小事 | Connect tools with MCP / Let the AI work directly with GitHub, docs, and other systems / Tell me which MCP tools I have connected and use one of them for a small task |
| hook | hook | Hook：让固定动作自动发生 / 比如改完代码自动跑测试，不用每次提醒 / 请帮我配置一个 hook：每次改完文件自动运行测试。先告诉我要改什么，我确认后再写 | Hooks: automate the routine / For example, run tests after every edit without reminding it / Set up a hook that runs tests after you edit files. Tell me what you'll change first; write it after I confirm |
| compact | compaction | 长对话压缩一下 / 会话太长时压缩，保留结论、扔掉过程 / 请用 /compact 压缩当前对话，只保留结论和待办 | Compact long chats / Compress a long session — keep conclusions, drop the noise / Use /compact to compress this conversation, keeping only conclusions and open items |
| worktree | tool:EnterWorktree | 用 worktree 并行开发 / 两件事互不干扰地同时改，不怕弄乱 / 请在一个新的 git worktree 里完成这个改动，别动我当前的工作区：[你的任务] | Parallel work with worktrees / Change two things at once without stepping on each other / Do this change in a new git worktree and leave my current working tree alone: [your task] |
| codex_agents | instructions:codex | 给 Codex 写 AGENTS.md / Codex 的项目说明书，作用和 CLAUDE.md 一样 / 请读一下这个项目，帮我写一份 AGENTS.md，控制在 60 行以内 | Write an AGENTS.md for Codex / Codex's project brief — same idea as CLAUDE.md / Read this project and write an AGENTS.md under 60 lines |
| init_cmd | self | /init 自动生成说明书 / 在项目里输入 /init，AI 会自己读代码写初稿 / 在这个项目里运行 /init，然后把生成的 CLAUDE.md 给我看 | Generate a brief with /init / Type /init in a project and the AI drafts the brief from the code / Run /init in this project, then show me the generated CLAUDE.md |
| clear_session | self | 一个任务一个会话 / 换话题就 /clear，上下文干净、回答更准 / （换新任务前输入 /clear） | One task per session / Switch topics with /clear for cleaner context and sharper answers / (type /clear before starting a new task) |
| resume | self | 接着上次的会话 / 用 claude --resume 或 codex resume 找回昨天的对话 / （在终端输入 claude --resume，选择要继续的会话） | Pick up where you left off / Use claude --resume or codex resume to reopen yesterday's chat / (run claude --resume in your terminal and choose a session) |
| at_mention | self | 用 @ 引用文件 / 输入 @ 加文件名，直接把文件交给 AI 看 / 请看一下 @README.md，告诉我这个项目缺什么 | Reference files with @ / Type @ plus a filename to hand that file to the AI / Look at @README.md and tell me what this project is missing |
| paste_image | self | 贴截图让 AI 看 / 报错截图、设计稿直接粘贴进对话 / （把截图粘贴进对话）请看这张图，告诉我问题出在哪 | Paste a screenshot / Drop error screenshots or designs straight into the chat / (paste a screenshot) Look at this image and tell me what's wrong |
| headless | self | 非交互模式跑批量活 / claude -p 或 codex exec 一行命令跑完就走 / （在终端试：claude -p "用三句话总结这个项目"） | Headless mode for batch jobs / claude -p or codex exec runs a task in one command / (try in a terminal: claude -p "summarize this project in three sentences") |
| custom_command | self | 自定义斜杠命令 / 把常用提示词存成 /命令，一键复用 / 请帮我把"检查代码风格并修复"做成一个自定义斜杠命令 | Custom slash commands / Save a prompt you reuse as a /command / Turn "check code style and fix it" into a custom slash command for me |
| review_diff | self | 让 AI 改完自查 / 改完先让它自己看一遍 diff，问题少一半 / 请检查你刚才的改动：列出可能的问题和遗漏，先别继续改 | Have the AI review its own diff / A self-review pass catches many problems early / Review the change you just made: list possible problems and gaps, and don't change anything yet |
| permissions | self | 设好常用权限 / 常用的安全命令设成免确认，少被打断 / 请帮我看看哪些常用命令可以安全地加入免确认列表，先列出来不要改 | Set up permissions / Allow safe, frequent commands so you're interrupted less / Suggest which frequent commands are safe to auto-allow — list them, don't change anything |

**Rankings and tips:** build from `cloud/master.py` — `SKILL_POOL` → `rankings.skill`, `AGENT_POOL` → `rankings.agent` (name, url, zh tagline = `tagline`; write a faithful short English tagline; `match`: for `anthropics/skills` use `[]`, others `[]`), and the `kind=="tip"` items of `CONTENT_POOL` → `tips` (zh title/detail as-is, faithful English translation, `source`). Do not invent projects or facts.

- [ ] Step 1: write failing tests: bundled file loads and validates; `load_content(bad_path)` falls back to bundled; a file with a bad `detect` or missing `en` text is rejected; `content/daily.json` is byte-identical to `agentfit/engine/content_pool.json`; there are exactly 24 skills in the order above.
- [ ] Step 2–4: FAIL → implement → PASS + full suite (`--basetemp=.pytest_cache/tmp`). Step 5: commit `feat(engine): bundled daily content pool and loader`.

### Task 15: Engine v2 — skill codex (图鉴), today's new skill, rankings, streak, badges, usage summary

**Files:** Modify `agentfit/engine/profile.py` (30-day fields), `agentfit/engine/snapshot.py` (new blocks, `--content` and `mark-tried`), `agentfit/engine/__main__.py`; create `agentfit/engine/codex_book.py`, `tests/engine/test_codex_book.py`; extend `tests/engine/test_snapshot.py`.

**Profile additions (30-day window, same dedupe):** `tool_calls_30d`, `skill_calls_30d`, `sidechain_30d`, `hook_success_30d`, `compactions_30d`, `light_token_share_30d`, `efforts_30d: set[str]`, `active_dates_30d: list[str]` (sorted local `YYYY-MM-DD` with ≥1 usage event).

**`codex_book.py` — Produces:**
```python
def detected(card: dict, p: Profile, inv: dict[str, Inventory]) -> bool | None   # None for "self"
def update_book(content: dict, p: Profile, inv, progress_path: Path, now: datetime) -> dict
    # progress.json gains {"lit": {id: {"at": iso, "how": "log"|"self"}}}; lighting is permanent.
    # returns {"lit": n, "total": N, "cards": [{"id","title","why","prompt","level","lit","how"}], "today": card-dict}
def today_skill(cards: list[dict], today: date) -> dict
    # unlit cards in content order; pick unlit[today.toordinal() % len(unlit)]; if none, rotate all cards
def mark_tried(card_id: str, progress_path: Path, now: datetime) -> bool   # only for detect=="self"; False otherwise
def daily_rankings(content: dict, inv, locale, today: date, n: int = 5) -> dict
    # {"skill": [...], "agent": [...]}: rotate each list by today.toordinal() % len, take n;
    # item: {"name","url","tagline","installed": bool}  installed = any(m in union(skills_installed) for m in match)
def daily_tip(content, locale, today) -> dict          # tips[today.toordinal() % len]
def streak(active_dates: list[str], today: date) -> int  # consecutive days ending today (or yesterday if no usage yet today)
def badges(streak_days: int, lit: int, total: int, village_passed: int, locale) -> list[dict]
    # ids: streak_3, streak_7, streak_14, streak_30, book_5, book_10, book_20, book_all, village_done;
    # each {"id","title","earned": bool}. zh/en titles: 连续 3 天/3-day streak, 一周修行/One-week streak,
    # 两周修行/Two-week streak, 一月修行/30-day streak, 图鉴 5 张/5 cards lit, 图鉴 10 张/10 cards lit,
    # 图鉴 20 张/20 cards lit, 图鉴全收集/Full collection, 新手村出师/Village graduate
```
Detect rules: `tool:X` → `tool_calls_30d.get(X,0)>=1`; `mcp` → `tool_calls_30d.get("mcp",0)>=1`; `skill_any` → any `skill_calls_30d`; `sidechain`/`hook`/`compaction` → respective 30d counter ≥1; `light_model` → `light_token_share_30d > 0`; `effort:a|b` → intersection with `efforts_30d`; `instructions:claude|codex` → that tool's `inventory.instructions_bytes > 200`; `self` → None.

**Snapshot schema v2** (bump `"schema": 2`; keep all v1 keys): add `"book"` (update_book result, localized), `"rankings"`, `"daily_tip"`, `"streak": {"days": int}`, `"badges"`, `"usage_summary": {"tokens_7d": int, "cost_usd_7d": float, "codex_quota_pct": float|null}`. CLI: `snapshot --json [--content PATH]` (loads via `load_content`), and new subcommand `mark-tried <card_id> [--state-dir]` → prints `{"ok": true|false}`.

- [ ] Step 1: failing tests — each detect kind lights a card from a crafted Profile; lit stays lit after the signal disappears; `self` cards light only via `mark_tried`, and `mark_tried` on a log card returns False; `today_skill` prefers unlit and is deterministic per date; rankings rotate daily and set `installed` from `match`; `streak` handles gaps and "no usage yet today"; badges thresholds; snapshot v2 keys present, still no content/path leaks; `mark-tried` CLI round-trip.
- [ ] Step 2–4: FAIL → implement → PASS + full suite. Step 5: real-machine smoke into `.pytest_cache/smoke-state` (print `book.lit/total`, today skill id, streak). Step 6: commit `feat(engine): skill codex, daily skill, rankings, streak and badges`.

### Task 16: App v2 — three tabs, content updater

**Files:** Create `ContentUpdater.swift`, `CheckupTab.swift`, `TodaySkillTab.swift`, `TrainingTab.swift`, `RingView.swift`; modify `PopoverView.swift` (segmented tabs), `Snapshot.swift` (v2 fields, all optional), `EngineRunner.swift` (pass `--content <AppSupport>/content.json` when the file exists; add `markTried(id:)`), `SnapshotStore.swift`, `StatusItemController.swift`, `Localizable.strings`, tests, `tests/engine/test_privacy.py`. Delete `UsageSection.swift` (replaced by the one-line summary).

- **ContentUpdater**: `static let url = URL(string: "https://raw.githubusercontent.com/KenichiXXX/365-ai-master/main/content/daily.json")!`. `refreshIfNeeded()`: if `UserDefaults "contentFetchedAt"` is today, return. Otherwise `URLRequest(url:)`, `httpMethod = "GET"`, `cachePolicy = .reloadIgnoringLocalCacheData`, **no** extra headers/body/cookies (`httpShouldHandleCookies = false`), ephemeral session, 15 s timeout; accept only HTTP 200 and ≤1 MB; parse JSON and require `version == 1` and non-empty `skills`; write atomically to `AppSupport/365AIMaster/content.json`; set `contentFetchedAt`. Any failure → keep the old file silently. Called on launch and when the popover opens.
- **PopoverView**: `Picker` segmented control with 体检 / 今日新技能 / 修炼 (en: Check-up / New today / Training); remember last tab in UserDefaults.
- **CheckupTab**: large `RingView(score: overall.score)` + `village.rankTitle` + "新手村第 N 关 · 连续 X 天" + four small `RingView`s with dimension labels + the today_tip card (title, why, buttons Copy prompt / Check now) + one grey caption from `usage_summary`: zh `本周 2,867 万 tokens · 折算 $577 · Codex 周额度 13%` / en `This week 28.7M tokens · ≈$577 API-equivalent · Codex weekly 13%` (format tokens with 万/亿 in zh, K/M/B in en; omit the quota part when null).
- **TodaySkillTab**: `book.today` card with a "NEW · 你还没用过 / New for you" badge when unlit, title, why, buttons **复制试一下 / Copy and try** (copies prompt) and **试过了 / I tried it** (log-detectable → triggers refresh; `self` → `EngineRunner.markTried` then refresh); then "今日 Skill 榜 / Today's skills" and "今日 Agent 榜 / Today's agents" lists (name, tagline, right-side badge 已装/未装 · Installed/Not installed, click opens url via `NSWorkspace.shared.open` — only on explicit click); then `daily_tip` as "大师一句话 / Master's tip".
- **TrainingTab**: village 3×3 grid (existing `VillageGrid`), "技能图鉴 N/M 已点亮 / Skill book N/M lit" grid of small tiles (lit = filled; `self`-lit shows a small 自评/self tag; unlit = dashed; tap shows the card's why + prompt), streak line, badges row (earned filled, others dimmed).
- **Menu bar title**: `③` style quest number as now, plus `•` when today's skill is unlit.
- **Privacy test**: allow `URLSession` only in `ContentUpdater.swift`; assert that file contains exactly one `https://` literal equal to the URL above, contains `httpMethod = "GET"`, and does not contain `httpBody`, `setValue(`, `addValue(`, or `uploadTask`.
- **RenderPreviewTests**: render each tab to `RENDER_OUT` with suffixes `-checkup.png`, `-today.png`, `-training.png`.

- [ ] Step 1: failing Swift tests — v2 snapshot fixture decodes (regenerate fixture with schema 2); token formatter (2867万 / 28.7M); ContentUpdater rejects non-200, oversize, wrong version (inject a fake loader closure — no real network in tests). Step 2–4: FAIL → implement → `swift build` + `swift test` pass; privacy test passes. Step 5: render the three tabs from a real engine run (from `macos/`: `AIMASTER_ENGINE=$PWD/../dist/365engine RENDER_OUT=$PWD/../.pytest_cache/v2 swift test --filter RenderPreviewTests` after rebuilding the engine). Step 6: commit `feat(macos): v2 three-tab popover with daily skill and skill book`.

### Task 17: Repackage and verify

- [ ] Rebuild with `scripts/package_app.sh` (engine includes `content_pool.json`). Launch the .app for ≤5 s, confirm with `pgrep`, kill it. Run the full Python suite and `swift test`. Commit any packaging changes as `build: repackage v2`.

### Task 18: Daily rankings harvester + publish to the `content` branch + launchd schedule

Context: Kenichi approved a daily job that collects Skill/Agent rankings from public sources and syncs them into the app's public content file. Only the orphan branch `content` of `origin` is pushed — never `main` or `feat/*`.

**Hosting change:** the public file moves to branch `content`, path `daily.json`:
`https://raw.githubusercontent.com/KenichiXXX/365-ai-master/content/daily.json`. Update `ContentUpdater.url`, the privacy test's expected URL, and spec §11.4 wording (`content` branch instead of `main/content/`).

**Sources (verified 2026-10-21 by the reviewer):**
1. The Skill Leaderboard — `GET https://www.skillleaderboard.com/api/catalog` (declared public dataset in its schema.org `Dataset.distribution`, robots `Allow: /`). JSON `{"metrics","facets","catalog":[...]}`; catalog items have `repo, owner, name, rank, category, tagline, summary, stars, forks, stars7d, stars30d, tractionScore, compatibleAgents`.
2. GitHub Search API via the `gh` CLI (`gh api search/repositories ...`, user's own auth). Agent queries (each `sort=stars&order=desc&per_page=50`): `topic:ai-agents stars:>1000 archived:false fork:false pushed:>{today-30d}`, same for `topic:ai-agent`, `topic:coding-agent`, `topic:agent-framework`.
Send `User-Agent: 365aimaster-harvester/0.1 (+https://github.com/19800104zhao-svg/365-ai-master)`; one request per source/query per run; timeout 30 s.

**Files:**
- Create `scripts/harvest/harvest.py` (stdlib only + subprocess for `gh` and optional `claude`), `scripts/harvest/run_daily.sh`, `scripts/harvest/com.365aimaster.harvest.plist`, `scripts/harvest/install_daily.sh`, `tests/harvest/test_harvest.py`, `tests/harvest/fixtures/{skillleaderboard_catalog.json,github_search_agents.json}` (small hand-made fixtures in the real shapes; no network in tests).
- Modify `agentfit/engine/inventory.py` (`Inventory.plugins_installed: list[str]` = `enabledPlugins` keys with truthy value, name part before `@`; include in `to_public()` as a count `plugins` only — names stay internal), `agentfit/engine/codex_book.py` (`installed` = any `match` entry equals a skill name or plugin name, case-insensitive; rotation only when `content["rankings"].get("rotate", True)` is true — live data sets it false and lists are shown in order; pass through `rankings.source` and `rankings.updated_at`), `agentfit/engine/content_pool.py` validation (allow optional `rotate`, `source`, `updated_at`, and per-item optional numeric `stars`, `stars7d`).

**`harvest.py` interface:**
```python
def fetch_skill_leaderboard(fetch=urllib_fetch) -> list[dict]
def fetch_github_agents(run_gh=subprocess_gh, today=date.today()) -> list[dict]
def select_skills(items, n=20) -> list[dict]
    # keep stars >= 300, non-empty summary/tagline; sort by stars7d desc then stars desc; top n
def select_agents(items, history: dict, n=20) -> list[dict]
    # dedupe by full_name; drop archived/fork/no description/no license; delta7d = stars - history[7 days ago] when known
    # sort by delta7d desc (unknown deltas after known), then stars; top n
def to_ranking_item(repo: str, url: str, en: str, zh: str | None, stars: int, stars7d: int | None) -> dict
    # {"name", "url", "tagline": {"en": en, "zh": zh or en}, "match": [repo.split("/")[1].lower()], "stars", "stars7d"}
def translate_zh(texts: list[str], run_claude=subprocess_claude) -> list[str | None]
    # one `claude -p --model haiku` call (if `claude` exists) asking for a JSON array of faithful, short Chinese
    # translations of the given English one-liners, same order, no additions. Parse strictly; any error -> all None.
def build_content(base: dict, skills: list, agents: list, today: date) -> dict
    # copy base (skills cards + tips unchanged); rankings = {"skill": skills, "agent": agents, "rotate": False,
    # "source": "The Skill Leaderboard · GitHub", "updated_at": today.isoformat()}; updated_at = today
def main(argv=None) -> int
    # --base agentfit/engine/content_pool.json --out <path> --history <path> [--no-translate]
    # Abort (exit 3, write nothing) if either list has < 10 items or validate() fails.
```
History file (`stars-history.json`, kept on the `content` branch next to `daily.json`): `{"YYYY-MM-DD": {"owner/repo": stars}}`, keep the last 35 days.

**`run_daily.sh`** (bash, `set -euo pipefail`): ensure a dedicated clone at `~/Library/Application Support/365AIMaster-harvest/repo` (first run: `git clone --single-branch --branch content` if the branch exists on origin, else create an orphan `content` branch there with only `README.md` explaining the file); `git pull --ff-only`; run `harvest.py` from the main checkout path passed as `$1` (default: the script's repo root) with `--out repo/daily.json --history repo/stars-history.json`; if `daily.json` changed: `git add daily.json stars-history.json && git commit -m "content: daily $(date +%F)" && git push origin content`. The clone must never check out or push any other branch. Log to `~/Library/Logs/365aimaster-harvest.log`.

**launchd:** `com.365aimaster.harvest.plist` runs `run_daily.sh` at 07:30 local daily (`StartCalendarInterval` Hour 7 Minute 30), `StandardOutPath`/`StandardErrorPath` = the log, `EnvironmentVariables` PATH including `/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin`. `install_daily.sh` copies it to `~/Library/LaunchAgents/` with the absolute repo path substituted and runs `launchctl bootstrap gui/$(id -u) <plist>`; prints how to uninstall. **Do not run `install_daily.sh` or `run_daily.sh` yourself** — the reviewer runs them outside the sandbox.

**Tests (no network):** selection/filtering/sorting rules; delta7d from history; translation fallback (fake runner returning bad JSON → zh falls back to en); `build_content` output passes `validate()` and keeps the 24 skill cards and tips unchanged; abort when a list has < 10 items; `installed` matches plugin names; `rotate: False` keeps order; ContentUpdater URL/privacy test updated.

- [ ] TDD steps as usual; commit `feat(harvest): daily rankings from The Skill Leaderboard and GitHub, published to the content branch`.
