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

### Task 19: v2.1 polish — bigger popover, click-outside closes, adversarial-review fixes

From Kenichi's trial (2026-10-21) plus the reviewer's adversarial pass. Swift unless noted.

1. **Bigger UI**: popover 440×720 (StatusItemController.contentSize and PopoverView.frame). Body text one step larger: card titles `.title2.bold()`, descriptions `.body`, ranking names `.headline`, taglines `.callout`; minimum font 11pt everywhere (no `.system(size: 9)`); main ring 150pt, dimension rings 64pt.
2. **Click outside closes the popover**: root cause — the LSUIElement app never activates, so `.transient` doesn't see outside clicks. Fix: `NSApp.activate(ignoringOtherApps: true)` before `popover.show`, keep `.transient`, AND add an `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])` while shown that calls `popover.performClose(nil)`; remove the monitor in `popoverDidClose` (set `popover.delegate`). Esc also closes.
3. **Copy feedback**: after any copy button, swap its label to「已复制 ✓ / Copied ✓」for 1.5 s.
4. **"试过了 / I tried it" feedback**: for log-detectable cards, re-scan; if still unlit show inline「还没在日志里看到它——真正用一次后会自动点亮 / Not seen in your logs yet — it lights up automatically after you use it once」; for `self` cards show「已点亮 ✓ / Lit ✓」.
5. **Rankings rows**: replace the always-"未装" pill with growth info: `★ 30.2万 · 本周 +3,946` / `★ 302K · +3,946 this week` (omit the weekly part when stars7d is null); show an「已装 / Installed」pill only when `installed` is true. Number formatting via the existing token formatter style (zh 万/亿, en K/M). Engine already emits `stars`/`stars7d` per ranking item (Task 18); ensure the Swift model decodes them.
6. **Skill-book card detail**: replace the `.sheet` (awkward inside a transient popover) with an inline expandable panel under the grid showing why + prompt + a copy button.
7. **Battery**: background timer every 300 s (was 60 s; settings options 60/300/900, default 300); always refresh immediately when the popover opens.
8. **First run**: if `UserDefaults "onboarded"` is false, show a one-time banner at the top of the Check-up tab:「365 AI Master 每天读你本机的 AI 使用记录（只读、不上传），给你一个提升动作和一个新技能。」with buttons「开机自动启动」(SMAppService register) and「知道了」. en equivalent.
9. **Quit placement**: move Quit into Settings (footer keeps only Updated time + Settings) to avoid accidental quits.
10. **Engine (Python)**: snapshot `book.today` must not repeat a card the user already saw yesterday if other unlit cards exist — use `unlit[(today.toordinal()) % len(unlit)]` but skip index equal to yesterday's pick when len(unlit) > 1 (deterministic; test it).

Tests: Swift unit tests for the formatter strings in (5), the copy-feedback state reset, and the onboarding flag; Python test for (10). Render all three tabs at the new size via RenderPreviewTests (frame 440 wide). Commit `feat(macos): v2.1 polish — larger popover, click-outside close, review fixes`.

### Task 20: Opt-in anonymous score for "you beat X% of AI users"

Kenichi's decision (2026-10-21): optional, **default off**; only after the user agrees, upload the overall score and the four dimension scores. Nothing else. Backend runs on Cloudflare Workers + D1; Kenichi authorizes wrangler, the reviewer deploys.

**Backend = Cloudflare Worker + D1** (Kenichi switched from Railway, 2026-10-21; free tier, no sleeping). Code in `server/ranking-worker/` (deps already installed by the reviewer: wrangler 4.151.3, vitest 4.1.12, `@cloudflare/vitest-plugin` 1.4.6 — read its README in node_modules for the vitest config; network is unavailable, do not npm install). Plain JavaScript (ES modules) is fine.
- `wrangler.toml`: `name = "365aimaster-ranking"`, `main = "src/index.js"`, `compatibility_date = "2026-10-01"`, D1 binding `DB` → database `365aimaster-ranking` with `database_id = "REPLACE_AFTER_CREATE"` (the reviewer fills it after `wrangler d1 create`). `migrations_dir = "migrations"`.
- `migrations/0001_init.sql`: `devices(device_token TEXT PRIMARY KEY, score INTEGER NOT NULL, routing INTEGER, timing INTEGER, context INTEGER, leverage INTEGER, app_version TEXT, updated_at TEXT NOT NULL)` and `score_counts(score INTEGER PRIMARY KEY, n INTEGER NOT NULL DEFAULT 0)` pre-filled with rows 0..100 (n = 0).
- Why the counts table: D1 bills rows *scanned*; counting "how many scored lower" over `devices` would scan every row per request. Ranking must read only `score_counts` (≤101 rows).
- `POST /v1/score`: body ≤ 1 KB, JSON with EXACTLY `device_token` (8–64 chars `[A-Za-z0-9-]`), `score` (int 0–100), `dims` (object with exactly `routing,timing,context,leverage`, ints 0–100), `app_version` (string ≤ 20). Anything else → 422 `{"error":"invalid"}`. Upsert in one `DB.batch`: if the device exists with a different score, decrement the old bucket; increment the new bucket (or leave buckets unchanged if the score didn't change); upsert the device row. Throttle: if the device's `updated_at` is < 1 hour ago, don't write — just return the ranking. Response 200: `{"total": T, "rank": count(score > s) + 1, "percentile": T >= 20 ? round(100 * beaten / (T - 1)) : null, "small_sample": T < 20}` where `beaten = count(score < s)`, all from `score_counts`.
- Every other path/method → 404. No CORS headers. Never log the request body or IP.
- Tests (`test/index.test.js`, run with `npm test` inside `server/ranking-worker`, local D1 with the migration applied): extra field / missing dims key / out-of-range → 422; first device → total 1, rank 1, small_sample true; same device re-posting with a new score after the throttle window keeps total 1 and moves its bucket (simulate time by updating `updated_at` in D1 directly); 25 devices → percentile math correct; GET → 404.
- `server/ranking-worker/README.md`: deploy steps for the reviewer: `npx wrangler login`, `npx wrangler d1 create 365aimaster-ranking`, paste id, `npx wrangler d1 migrations apply 365aimaster-ranking --remote`, `npx wrangler deploy`.
- Add `server/ranking-worker/node_modules/` and `.wrangler/` to `.gitignore`; commit `package.json` and `package-lock.json`.

**App (Swift):**
- `ScoreReporter.swift` — the second (and last) file allowed to use the network. `static let endpoint = URL(string: "https://365aimaster-ranking.REPLACE.workers.dev/v1/score")!` (the reviewer replaces it after deploy; while the host contains `REPLACE`, the reporter must not send anything). Encodes a `struct Payload: Encodable { let device_token: String; let score: Int; let dims: Dims; let app_version: String }` — nothing else. `httpMethod = "POST"`, `Content-Type: application/json` only, ephemeral session, no cookies, 15 s timeout, accept HTTP 200 only, decode `AppScoreOut`. The device token is a random UUID created on first opt-in and stored in UserDefaults `anonDeviceToken` (never derived from hardware or account). Report at most once per day (`scoreReportedAt`) and only when `UserDefaults "shareAnonymousScore"` is true; store the last result in UserDefaults for display. When the user turns sharing off, stop reporting (server row stays; say so in Settings).
- Consent UI: onboarding banner (Task 19 #8) gets a third choice; Settings gets a toggle「匿名参与全球排名 / Join the anonymous global ranking」with the exact explanation:「开启后，每天最多一次上传：总分和四个维度分，以及一个随机编号。不上传任何使用记录、文件或对话。随时可以关闭。」/ "When on, once a day at most we upload your overall score, your four dimension scores, and a random ID. Never your usage logs, files, or conversations. Turn it off anytime."
- Check-up tab, under the rank title:
  - sharing on, `total >= 20`: 「击败了全球 X% 的 AI 用户（N 人参与）」/ "You beat X% of AI users (N taking part)"
  - sharing on, small sample: 「早期排名：N 人中第 K 名」/ "Early ranking: #K of N"
  - sharing off: a quiet link-style button「看看你击败了全球多少 AI 用户 →」/ "See how you rank worldwide →" that opens the consent explanation with Allow / Not now.
  - request failed / server down: show nothing (no stale fake numbers older than 7 days).
- Privacy test (`tests/engine/test_privacy.py`): network allowed only in `ContentUpdater.swift` and `ScoreReporter.swift`; for `ScoreReporter.swift` assert exactly one `https://` literal, whose host ends with `.workers.dev`,, `httpMethod = "POST"`, the Payload struct has exactly the four stored properties above, and no `uploadTask`/`multipart`.
- Swift tests with a fake transport: no request when sharing is off; payload JSON keys are exactly `device_token, score, dims, app_version` and `dims` keys exactly the four; once-per-day gating; small-sample vs percentile strings.

Commit `feat: opt-in anonymous global ranking (score + four dimensions only)`.

Also update the onboarding banner text: zh「365 AI Master 每天读你本机的 AI 使用记录（只读，默认不上传任何数据），给你一个提升动作和一个新技能。」, en "365 AI Master reads your local AI usage every day (read-only; nothing is uploaded unless you opt in) and gives you one thing to improve and one new skill."

---

# Phase 3 — Training tab redesign + Free / Pro (Kenichi approved 2026-10-21)

Free keeps the daily habit; Pro ($12/year founding price) sells "see your growth" and "go deeper". Payment: Waffo checkout (Kenichi is opening a personal merchant account) → activation key → the app verifies the key's signature locally. No user accounts. Nothing in Pro may be a promise of an unbuilt feature.

### Task 22: Training tab redesign + card levels

- Content (`agentfit/engine/content_pool.json` and identical `content/daily.json`): set `level` per card — 1 入门/Basics: rules_file, web_search, web_fetch, ask_first, at_mention, paste_image, clear_session, init_cmd; 2 进阶/Intermediate: plan_mode, todo_list, light_model, effort_up, first_skill, compact, resume, review_diff, codex_agents, permissions; 3 高手/Advanced: subagent, mcp, hook, worktree, headless, custom_command. Add a test asserting these exact level sets.
- Engine snapshot `book` gains `groups`: `[{"level":1,"title":"入门|Basics","lit":n,"total":m,"missing":[card ids]}]` for levels 1–3, and `next_badge`: `{"id","title","have":x,"need":y}` for the closest unearned badge (ties → lowest need).
- Swift `TrainingTab` (replace the three tile grids):
  1. Summary row of three stat chips: 新手村 `passed/9`, 技能图鉴 `lit/total`, 连续 `N 天`.
  2. 「新手村之路 / Village path」: 9 dots joined by a line (passed filled with ✓, current outlined with its number, locked grey; dots 4–8 may collapse to `…` only if width requires); under it ONE card for the current quest (title + Copy prompt + Check now, reusing TipCard behaviour). After graduation show a "出师 ✓" card instead.
  3. 「技能图鉴 / Skill book」 header with `入门 a/b · 进阶 c/d · 高手 e/f`; three disclosure rows (one per level) showing "还差：<first two missing titles>…" / "N to go"; expanding a row lists that level's cards (lit ✓ / unlit), tapping a card expands its why + prompt inline (free-tier gating is added in Task 24, not here).
  4. 「下一枚徽章 / Next badge」 card with a progress bar (`have/need`) and one grey line listing earned badge titles.
- Render the tab via RenderPreviewTests; total rendered height of the Training tab must be ≤ 1100 pt at 440 wide with the real-data snapshot (assert in the preview test).
- Commit `feat(macos): training tab as a path — summary, village path, grouped skill book, next badge`.

### Task 23: Activation keys + paywall (no Waffo API yet)

- **Key format** (`docs/license.md` documents it): `AIM1.<base64url(payload JSON)>.<base64url(Ed25519 signature over the payload bytes)>`; payload `{"v":1,"lic":"<random 16-char id>","plan":"pro","iat":"YYYY-MM-DD","exp":"YYYY-MM-DD"}` — no email, no name, no device binding.
- **Worker** (`server/ranking-worker`): D1 migration `0002_licenses.sql` table `licenses(lic TEXT PRIMARY KEY, plan TEXT, iat TEXT, exp TEXT, order_ref TEXT, created_at TEXT)`. `POST /v1/license/issue` — requires header `Authorization: Bearer <ADMIN_TOKEN>` (Worker secret); body `{"order_ref": "<string ≤ 64>", "days": 365}`; signs with secret `LICENSE_PRIVATE_KEY` (Ed25519 PKCS8 base64, WebCrypto `Ed25519`), stores the row, returns `{"key": "AIM1...."}`. No GET listing endpoint. Reserve (but do not implement) `POST /v1/waffo/webhook` → 404 for now. Tests with a test keypair generated in the test (no secrets committed).
- **Scripts**: `server/ranking-worker/scripts/gen_keypair.mjs` (prints a new Ed25519 keypair: private PKCS8 base64 for `wrangler secret put LICENSE_PRIVATE_KEY`, public raw 32-byte base64 for the app) and `scripts/issue_key.sh <order_ref>` (curl with ADMIN_TOKEN from env) — for issuing founding keys by hand until Waffo is wired.
- **App**: `License.swift` verifies keys with `CryptoKit.Curve25519.Signing.PublicKey(rawRepresentation:)` against `static let publicKeyBase64 = "REPLACE_PUBLIC_KEY"` (reviewer fills it in); checks `v==1`, `plan=="pro"`, `exp >= today`. Stored in UserDefaults `licenseKey` (verification re-runs on launch; never trust a cached boolean). `isPro` published on SnapshotStore. URL scheme `aimaster365://activate?key=...` (Info.plist `CFBundleURLTypes`) + Settings field 「输入激活码 / Enter activation key」 with clear errors (格式不对 / 签名无效 / 已过期).
- **Paywall UI**: Settings section 「365 AI Master Pro」: price line 「创始价 $12/年 / Founding price $12/year」, the four Pro items as a list (exact copy from the sketch: 成长曲线：30 天分数走势、本周比上周 · 每周复盘：周一推送一页周报 · 技能图鉴随时选学、完整榜单 Top 20 · 四维分别排名), button 「去付款 / Buy」 opening `static let checkoutURL = "REPLACE_WAFFO_CHECKOUT"` — the button is hidden while it is the placeholder, and a grey line says 「付款通道开通中，可联系作者获取创始激活码 / Checkout opening soon」. When Pro: show 「Pro 已激活，到期 YYYY-MM-DD」.
- Privacy test: allow network in `ContentUpdater.swift`, `ScoreReporter.swift` only (activation is offline; the Buy button only opens the browser via NSWorkspace).
- Commit `feat: offline-verified activation keys and Pro paywall`.

### Task 24: Pro features — growth curve, weekly review, choose-any skill, Top 20

- **Engine history**: `progress.json` gains `history: {"YYYY-MM-DD": {"score": int, "dims": {...}}}` written on every snapshot (same day overwritten), keep 90 days. Snapshot adds `growth`: `{"days": [{"date","score"}...last 30], "week_delta": int|null}` (this week's latest minus last week's latest; null if no data last week) and `weekly`: `{"week_start","score_delta","cards_lit_this_week":[ids],"quests_passed_this_week":[keys],"days_active":n}`.
- **Gating (Swift)**: free users see the existing views; Pro adds:
  1. Check-up tab: a 30-day line chart (Swift Charts) under the dimension rings + 「本周比上周 +N」.
  2. Weekly review: every Monday 09:00 local a `UNUserNotificationCenter` notification (ask permission only when Pro is activated) titled 「本周复盘」 with one line; clicking opens the popover on a Weekly sheet built from `weekly`.
  3. Skill book: tapping any unlit card shows why + prompt + Copy. Free users tapping an unlit card that is not today's card see 「Pro 可随时选学这张卡 / Pro: learn any card anytime」 with a link to the Pro section.
  4. Rankings: free shows Top 5, Pro shows all (up to 20) with a 「展开全部 / Show all」 row.
- Tests: engine history retention and week_delta; Swift gating (free vs pro) for each of the four.
- Commit `feat: Pro growth curve, weekly review, choose-any skill, full rankings`.

### Task 25: Per-dimension ranking (Pro)

- Worker: migration `0003_dim_counts.sql` table `dim_counts(dim TEXT, score INTEGER, n INTEGER, PRIMARY KEY(dim, score))` pre-filled for the 4 dims × 0..100. Maintain it in the same `DB.batch` as `score_counts` (decrement old dim buckets / increment new, same throttle rules). Backfill from existing `devices` rows in the migration. Response adds `dims: {"routing": {"rank","percentile"}, ...}` with the same small-sample rule.
- App: Pro only — under the rings, each dimension label shows 「击败 X%」 (or 「第 K 名」 when small sample). Free users see nothing extra.
- Tests in the worker (bucket moves per dimension, backfill) and Swift (decode + gating).
- Commit `feat: per-dimension global ranking for Pro`.

Reviewer (not Codex) deploys the worker changes, sets secrets, fills the public key, and repackages.

# Phase 4 — habit loop and growth (from research)

Plan only, 2026-10-21. Baseline reviewed on `feat/macos-v1` at `78bd9db`. Input is `365-AI-Master-产品设计调研与方案-2026-10-21.md`, especially §8, §9, §11, and T01–T10. That research did not inspect this repository. The mappings below describe code present at this baseline, not deployed or runtime-verified functionality. Kenichi's final decisions are recorded in spec §12 and override conflicting research recommendations.

## Outcome, boundaries, and execution

Deliver a local loop of one suggested practice, subsequent structured evidence, another day's reuse, and an honest review. Preserve the existing three tabs, nine quest IDs, 24 capability IDs, Free/Pro boundaries, content pipeline, and offline signature format. The lead engineer owns these tasks. Execute one task, prove it, commit it with the Global Constraints trailer, and stop for the existing reviewer gate. This document does not authorize implementation, publication, merchant setup, deployment, purchases, or a new background job.

- Keep all Global Constraints and the Phase 2/3 network amendments. `agentfit/engine/` stays network-free. Only `ContentUpdater.swift` and `ScoreReporter.swift` may make app network requests. Task 35 places license transport in the latter file, with a separate protocol and request type, rather than adding a third allowed file. Tests must keep score, content, and license payloads separate.
- Reuse `~/Library/Application Support/365AIMaster/`. Do not adopt the research's differently spaced directory. Store application progress there, never in AI-tool directories. Preserve history on trial or license expiry.
- Never read AI-tool credentials, browser state, Keychain, or mixed account/config files to recover missing metrics. No private text, tool arguments, project paths, or raw evidence enters snapshots, public content, ranking, payment, renewal, sharing, or diagnostics. Existing local scan cursors necessarily identify source paths. Keep those internal and out of every export.
- Use explicit structured event types and supported metadata. Do not add private-dialogue classification. Remove legacy text-marker dependence where a structured signal is unavailable and report unknown. Inventory proves configuration presence, not successful use.
- Do not redesign scoring weights or silently change existing evaluable score arithmetic. Missing evidence produces unknown, not a bonus, zero, or fabricated baseline. Freeze a score version for each comparable cohort.
- Respect research §11. No auto-edit, installation, terminal execution, telemetry, growth accounts, hardware fingerprint, referral rewards, annual animation, complex efficiency experiment, or new competition system. Two research exclusions are explicitly superseded by spec §12: Pro **does** auto-renew yearly with prior disclosure, and overall ranking **does** retain the worldwide wording at `total >= 20`.
- Existing ranking consent includes a random installation UUID and `app_version`, besides the five scores. Retain this reviewed contract and disclosure. Do not silently remove it, add another identifier, link it to licenses, or claim it deduplicates people. Small-sample wording remains unchanged.
- Waffo details remain unverified. Build an interface and fake first. A fake-backed pass proves our contract only. Real webhook verification, payment states, cancellation portal, recovery, and merchant testing remain a separate release blocker until verified.

Work checkpoint for the future implementer: Tasks 26–29 prove the local practice loop first. Tasks 30–32 add trustworthy review and public context. Tasks 33–35 cover trial and subscription continuity. Tasks 36–37 prove safe sharing and the complete flow. Each task ends with synthetic tests and a visible result. None requires a later task to make its own tests pass.

## Research-to-code disposition

`DROP` means remove the redundant research work item, not delete working code. `SHRINK` means extend the named implementation. `KEEP` means a missing behaviour earns a task.

| Research task | Current code and existing plan coverage | Disposition and Phase 4 destination |
|---|---|---|
| T01, read-only collection and coverage | Tasks 2–7/10; `events.py`, `scan_state.py`, `collectors/*.py`, `inventory.py`, `profile.py`, `snapshot.py`; incremental cursors, usage adapters, dedupe and per-tool error isolation exist | SHRINK. Keep adapters and cursor storage. Add coverage/version semantics and demonstrated dedupe/privacy gaps in 26; unknown-score rendering in 27. Do not rewrite all collectors. |
| T02, explainable scores and one action | Tasks 1/8/9/12; `agentfit/checkup.py`, `profile.dimensions`, `village.today_tip`, `TipCard.swift` already compute scores and choose one tip | SHRINK. Explain existing rules and their limitations, gate missing data, persist skip choices in 27. No new weight formula. |
| T03, first day and village | Tasks 9/10/19/22; `CheckupOnboardingBanner`, `PopoverView`, `village.py`, `TrainingTab.swift` already provide a banner, no-tools notice, and nine-stage path | SHRINK. Add four usable first-run branches, safe first practice and cancellable scanning in 28. DROP the research's replacement nine-quest curriculum. |
| T04, daily practice and review | Tasks 14–16/19/22; `codex_book.detected/update_book/today_skill/mark_tried` and 24-card pool already light cards, select daily cards and record self-report | SHRINK. Add event-level evidence, stable daily assignment, attempt/reuse states and real review exercises in 29. |
| T05, estimates, curve, weekly review | Task 24; `profile.event_cost`, `history.record_history`, `GrowthCurve.swift`, `WeeklyReviewSheet`, `ProFeatures` already exist | SHRINK. Replace tier-price certainty with matched-price coverage, version/gap-aware history and evidence-based templates in 30. DROP a second chart/report implementation. |
| T06, streak, calendar, notifications | Tasks 15/24; `active_dates_30d`, `streak`, `badges`, `WeeklyNotifications.swift` exist; streak currently comes from AI usage, not foreground app visits | SHRINK. Preserve the log-use streak with a precise label. Add a separate practice calendar and explicit notification preferences in 31. DROP a second foreground streak and paid rest protection. |
| T07, sharing and validation panel | No share renderer or local funnel ledger exists; `CopyButton.swift` is clipboard feedback only | KEEP a small local-only export and diagnostic view in 36. Reuse UI copy controls. No analytics backend. |
| T08, public distribution and comparison | Tasks 18/20/25; `scripts/harvest`, `ContentUpdater.swift`, `daily_rankings`, `ScoreReporter.swift`, worker histograms and D1 already exist | SHRINK in 32. Add provenance, freshness, compatibility and score-version isolation. DROP a second Worker content service, a second scheduler and replacing small-sample results with no ranking. |
| T09, trial, payment, license | Tasks 23–25; `License.swift`, `ProSettingsSection`, `ProFeatures`, worker `issueLicense`, `licenses` table exist. Webhook currently 404. No trial or renewal transport exists | SHRINK into 33–35. Reuse Ed25519 and AIM1. KEEP explicit local trial, normalized subscription state and authenticated key refresh. DROP manual annual renewal as the default and all referral settlement. |
| T10, integrated verification | Existing Python, Swift, worker and harvest tests plus preview/package scripts | SHRINK into 37. Extend the existing suites and record evidence. Do not treat test presence as proof of release, merchant integration or user demand. |

All P0/P1 proposals are accounted for individually below. The final two rows describe the bounded P2 pieces explicitly requested by T02/T08, not a new P2 programme.

| Proposal | Existing implementation | Decision and task |
|---|---|---|
| P0-01 coverage before scores | `snapshot.build_snapshot` returns scores even without a coverage object | KEEP coverage and null semantics, 26–27. |
| P0-02 complete action card | `village.today_tip`, `TipCard` already show one action and copy/check | SHRINK to rule evidence, skip/feedback, 27; validate its attempt in 29. |
| P0-03 first-day branches | Banner and `no_tools` notice exist | SHRINK to useful branches and recovery, 28. |
| P0-04 practice daily card | `TodaySkillTab`, `book.today`, copy/try buttons exist | SHRINK to exercise, success signal and attempt states, 29. |
| P0-05 evidence ledger | Permanent `lit[id] = {at, how}` exists | KEEP provenance and repeat-use ledger, 29; preserve legacy records. |
| P0-06 usage, estimates, quota | `event_cost`, `usage_summary`, `latest_rate_limits`, `UsageSummary.caption` exist | SHRINK to exact-price coverage and correct quota window, 30. |
| P1-07 yesterday's result | No action-to-subsequent-event link | KEEP a local follow-up in 29. |
| P1-08 review/challenge | Daily selection rotates all cards once lit | SHRINK to actual bundled review exercises and truthful labels, 29. |
| P1-09 usage versus practice dates | AI-log dates already drive streak | SHRINK to labels and separate practice calendar, 31. Do not replace with app-open scoring. |
| P1-10 relevant official updates | Public rankings and tips exist, no tool-update model | KEEP a bounded optional section in the existing public package, 32. No news feed or installer. |
| P1-11 suitable rankings | Real selection, installation badges and Free Top5/Pro Top20 exist | SHRINK to source/date/category/compatibility and details, 32. |
| P1-12 restrained reminders | Pro weekly Monday notification exists, requested on activation | SHRINK to opt-in preferences, one-shot scheduling and free daily reminders, 31. |
| P1-13 trustworthy curves | 90-day storage, 30-day curve, previous-week latest-point delta exist | SHRINK to gaps, versions and a named comparable window, 30. |
| P1-14 local weekly review | Existing template lists active days, lit cards and quests | SHRINK to observed change, uncertainty and next practice, 30. |
| P1-15 contextual trial/paywall | Contextual Pro links and offline activation exist | SHRINK to explicit trial and subscription disclosure, 33/35; worker lifecycle in 34. |
| P1-16 learning share card | No implementation | KEEP minimal free preview/save/copy, 36. |
| P1-17 course source code | No implementation | SHRINK to optional local allow-listed code and explicit checkout inclusion, 35. No creator outreach, rewards or referral identity. |
| P2-20 ranking semantics | Opt-in UUID, once-daily report, sample gate, overall and dimension buckets exist | SHRINK to cohort correctness and limitations, 32. Kenichi's worldwide and small-sample copy wins. |
| P2-22 stuck feedback | No persisted feedback | SHRINK to enum reasons in action card, 27, and user-reviewed summary in 36. |

## Shared acceptance contract

For every task, first add the named failing behavioural tests, then implement only that task in a later run. Python uses `.venv/bin/python` exclusively. Run targeted Python tests with `.venv/bin/python -m pytest <paths> -q`, Swift tests with `(cd macos && swift test --filter <TestClass>)`, and worker tests with `(cd server/ranking-worker && npm test)`. These commands describe future acceptance, not results from this planning run. A stack marked N/A has no change and no task-specific test requirement.

Each future task also runs the full required regression suites for the touched stacks. Record the two historically documented analytics failures only if reproduced at that task's baseline. Never waive a new failure as pre-existing. Use synthetic homes, temporary state, local D1, fake transports and generated test keys. Do not install dependencies or contact live providers just to pass tests.

Snapshot changes start with schema 3 in Task 26, with additive optional blocks and a migration reader for schema 1/2. Task 27 makes numeric scores nullable in schema 3. Update `EngineRunner.decode`, Swift models and fixtures in the same task as each contract change. Treat legacy scores/progress as legacy observations, not evidence of a newly recommended practice. State writes use the existing atomic write approach and one serialized engine command stream so scan and action commands cannot overwrite each other.

### Task 26: Add source coverage and close proven collection gaps

**Depends on:** None. **Research:** T01, P0-01, P0-06.

**Files:** Modify `agentfit/engine/{events.py,scan_state.py,inventory.py,profile.py,snapshot.py}`, `agentfit/engine/collectors/{base.py,_usage.py,claude_code.py,codex.py,gemini.py,opencode.py,qwen.py}`, `macos/Sources/AIMaster/{Snapshot.swift,EngineRunner.swift}` and existing collector/profile/privacy/decoding tests. Create `agentfit/engine/coverage.py`, `tests/engine/test_coverage.py` and synthetic fixtures under `tests/engine/fixtures/`. No change to legacy `agentfit/collector/`.

- [ ] Reuse collectors and cursors. Add `coverage` per tool with `adapter_version`, safe format/version identifier, `status`, UTC coverage bounds, valid usage count, malformed/skipped counts and per-signal availability. Status is `not_detected`, `no_logs`, `permission_denied`, `unsupported`, `partial`, or `ok`. A directory alone does not prove installation or usable logs. Mixed supported/unsupported records are partial. An unobserved event is false only if its adapter supports and covered that signal.
- [ ] Enforce resolved source-root allowlists, including symlink escapes. Reproduce and fix duplicate streaming tool blocks, copied/forked logs and overlapping usage counters before changing their merge. Dedupe usage and marker identities independently. Support Codex cumulative `token_count` deltas only with verified-format fixtures, per-session/model reset handling and precedence against `token_usage_record`; otherwise report partial rather than invent usage. Preserve already-working Qwen summary reconciliation, Gemini source precedence, read-only SQLite and newline cursors.
- [ ] Do not load `.claude.json` or other mixed credential-bearing configs to count MCP servers. Return unavailable for those counts. Use stat-only presence/size for instruction files; supported safe configuration fields need an explicit allowlist. Do not persist arbitrary skill arguments as names. Keep only bounded validated identifiers or capability counters. Cursor paths stay internal. Raw text/arguments never enter cache, diagnostics or snapshots.
- [ ] Add schema 3 coverage decoding now without changing the score formula in this task. Task 27 immediately uses it to suppress ungrounded scores.

**zh / en copy:** `尚无使用记录 / No usage records yet`; `无法读取日志，可稍后重试 / Logs cannot be read. Try again later`; `此日志格式暂不支持 / This log format is not supported yet`; `部分记录可用 / Some records are available`; `配置存在，尚未验证使用 / Configuration found; use has not been verified`. Put engine text in `content.py` and frame text in both existing localization files when used in later screens.

**Acceptance:** Python `test_coverage.py`, `test_scan_state.py`, `test_claude_code.py`, `test_codex_engine.py`, `test_usage_collectors.py`, `test_inventory.py`, `test_profile.py`, `test_privacy.py` must cover all six statuses, mixed failures, rotation/truncation, counter reset/model switch, duplicate tool block IDs, parent/child overlap, identical second import and one collector failing without losing others. Instrument file opens and SQLite statements to prove no denied file/table or source writes, including symlinks. Assert content sentinels absent from all derived data. Swift `SnapshotDecodingTests` accepts schema 3 coverage and old schema 1/2 fixtures; invalid schema still fails. Worker N/A. Visible proof is a synthetic coverage snapshot with distinct empty/partial/unsupported reasons, not a real-home dump.

**Network:** None. Do not run AI-tool CLIs to discover versions or quotas.

### Task 27: Explain evaluable scores and persist one main action

**Depends on:** 26. **Research:** T02, P0-01/02, bounded P2-22.

**Files:** Modify `agentfit/engine/{profile.py,snapshot.py,village.py,content.py,__main__.py}`, `macos/Sources/AIMaster/{Snapshot.swift,SnapshotStore.swift,EngineRunner.swift,CheckupTab.swift,DimensionRings.swift,RingView.swift,TipCard.swift}` and both `Resources/*/Localizable.strings`. Create `agentfit/engine/action_rules.py`, `tests/engine/test_action_rules.py`, `macos/Tests/AIMasterTests/ActionCardTests.swift`; extend snapshot/village/privacy tests. Read `agentfit/checkup.py` and `agentfit/models/checkup.py` as the existing scoring contract; do not change their legacy consumers.

- [ ] Register the existing engine rules with ID/version, required signals, window, actual numerator/denominator, missing policy, thresholds, explanation and limitations. Keep `DIMENSION_WEIGHTS` and evaluable score arithmetic. No private semantic inference. Label model mix, time-of-day, compaction and cache signals as heuristics, not task difficulty, personal productivity or guaranteed savings. Render no legacy alarming issue/impact text as factual advice.
- [ ] Emit each dimension as `score: int|null`, availability and rule evidence. Zero valid usage yields no score. If any required dimension is unknown, overall score/tier is null with `partial` or `unavailable`; never reweight known dimensions. Guard all ring, graduation, history and ranking callers against null. `graduate` needs four known scores. Store no new numeric history point for unknown overall, and make zero score-report calls for such snapshots. Do not cache-display an old ranking as current evidence after coverage becomes invalid.
- [ ] Reuse `today_tip` and `TipCard` as the single main action. Add `action_id`, stable rule/skill ID, evidence summary, limitation and validation kind. Select the current supported quest first, then an evaluable weakest dimension, then a safe built-in exercise. Persist assignment and feedback in `progress.json`. `later` snoozes to the next local day, `not_suitable` suppresses that action for seven local days, `never` suppresses that rule until reset in Settings. Keep the assignment stable unless explicitly skipped or completed.
- [ ] Add local CLI commands for feedback using enum values only. Reasons are `unclear`, `unsupported_tool`, `no_project`, `not_now`. Surface an alternative safe practice, not a fabricated diagnosis. No command edits configuration or starts a shell.

**zh / en copy:** `尚无可评估记录 / No assessable records yet`; `部分可评估 / Partly assessable`; `未知 / Unknown`; `为什么推荐 / Why this suggestion`; `这是日志指标的启发式判断，不代表任务难度或能力 / This is a heuristic from log metrics, not a measure of task difficulty or ability`; `不适合 / Not suitable`; `稍后 / Later`; `不再推荐 / Do not suggest again`; `看不懂 / I do not understand`; `工具不支持 / My tool does not support this`; `没有项目 / I have no project`; `暂时用不上 / Not useful right now`; `重置推荐偏好 / Reset suggestion preferences`.

**Acceptance:** Python `test_action_rules.py` asserts rule evidence/window/denominators, deterministic selection, each suppression interval and reset, null propagation, no zero-event graduation, and unchanged results for fully evaluable legacy fixtures. `test_snapshot.py`/`test_village.py` assert no null-to-zero fallback or accidental unlock. Swift `ActionCardTests`, `SnapshotDecodingTests`, `ScoreReporterTests` and `ProFeaturesTests` assert unknown rings, readable explanations, exactly one primary card, persistent feedback and zero reporting/cached percentile for unknown scores. Worker N/A. Render zh/en empty, partial and evaluable views and verify keyboard labels.

**Network:** No new requests. Existing opt-in score reporting is suppressed when coverage is insufficient.

### Task 28: Make the first practice available in every onboarding branch

**Depends on:** 26–27. **Research:** T03, P0-03.

**Files:** Modify `agentfit/engine/{content.py,village.py,snapshot.py}`, `macos/Sources/AIMaster/{CheckupTab.swift,PopoverView.swift,EngineRunner.swift,SnapshotStore.swift,TrainingTab.swift,SettingsView.swift}`, both localization files, existing snapshot/village/store tests. Create `macos/Sources/AIMaster/FirstPracticeView.swift`, `macos/Tests/AIMasterTests/FirstPracticeTests.swift`.

- [ ] Replace the banner-only start with resumable local onboarding. Show allowed source categories and read-only/privacy explanation, then a skippable obstacle choice. Separate source switches, public downloads, ranking consent and notification preference. No bundled consent. Preserve existing explicit preferences; absent public-download choice means no content request until chosen. Local practice remains available when everything optional is declined.
- [ ] Handle usable logs, no logs, unsupported format and denied permission separately. Denial offers retry or manual practice, never a forced broad disk-access request. First practice is bundled and asks the user's AI to explain project startup without editing. Without a project, offer a self-reported planning exercise. Never claim that either verifies output correctness.
- [ ] Expose progress/cancel/retry while scanning. Cancel the owned engine subprocess, discard partial output, preserve last good snapshot and progress, and release the running flag. Retry must not create a second concurrent process. Persist onboarding branch/choice only as enums, not free text or paths.
- [ ] Keep all nine existing quest IDs and passed history. Do not transplant the research's new curriculum. Distinguish configuration-based, historical, new-observed, self-reported and unsupported status in the current quest detail; unsupported practice may be tried without granting an automatically verified pass. First-run copying never creates an automatic quest pass. Task 29 adds event-level validation.

**zh / en copy:** `先练一步 / Try one step`; `查看允许读取的来源 / View allowed sources`; `跳过 / Skip`; `取消扫描 / Cancel scan`; `重试 / Retry`; `手动练习 / Practice manually`; `练习已复制，还未验证 / Practice copied; not verified yet`; `已尝试（自报） / Tried (self-reported)`. Prompt `请用简单语言解释当前项目如何启动；先不要修改文件。 / Explain how to start this project in plain language. Do not modify files.` No-project prompt `帮我列出一个想做的小工具的目标和验收清单，先不要执行命令。 / Help me list the goal and acceptance checks for a small tool I want to build. Do not run commands.`

**Acceptance:** Python snapshot/village tests keep nine IDs, preserve passed dates, and do not pass on copy/self-report. Swift `FirstPracticeTests` and `SnapshotStoreTests` cover four branches, all optional choices declined, onboarding restart/resume, cancel during a blocked fake process, retry, and no lost snapshot. No checkout or permission prompt before a user chooses its relevant control. Worker N/A. Manual keyboard/VoiceOver walkthrough must reach copy and return-to-check in all branches without relying on colour.

**Network:** First practice and onboarding need none. Public download consent is passed to the existing updater, ranking keeps its existing separate opt-in, and learning in the user's AI tool may use that tool's own network.

### Task 29: Track practice evidence, stable daily cards, and later reuse

**Depends on:** 26–28. **Research:** T04, P0-04/05, P1-07/08.

**Files:** Modify `agentfit/engine/{codex_book.py,content_pool.py,content_pool.json,events.py,snapshot.py,__main__.py,village.py,content.py}`, identical `content/daily.json`, `macos/Sources/AIMaster/{Snapshot.swift,EngineRunner.swift,SnapshotStore.swift,CopyButton.swift,TipCard.swift,TodaySkillTab.swift,TrainingTab.swift}`. Create `agentfit/engine/practice.py`, `tests/engine/test_practice.py`, `macos/Tests/AIMasterTests/PracticeTests.swift`; extend content/book/snapshot tests and fixtures.

- [ ] Add one local evidence ledger, with skill/action/attempt IDs, adapter/rule/content versions, UTC occurrence and first-seen times, original local date/timezone, hashed event identity, and evidence kind. Store no text, paths or arguments. Keep `seen_at`, `started_at`, `self_reported_at`, `first_observed_at`, and distinct `reuse_dates` as separate facts. Configuration existence gets `configuration`, never `log_observed`.
- [ ] An attempt begins only on explicit start or successful copy, not card display. Its baseline is all already-seen event identities plus start time. Only a new qualifying capability event occurring after start and outside that baseline validates it. Late-imported events predating start remain historical. Attribute a qualifying event once, to the most recent matching open attempt, not to every action with a similar detector. Another distinct local date and distinct capability event after first observation counts as reuse. Unsupported validators allow labelled self-report, never automatic verification.
- [ ] Preserve legacy `lit/how` records and existing badges as legacy achievements. Do not invent their event references or claim a recommendation caused them. Add evidence labels to the existing 24 cards. Keep configuration and self-report counts visible separately. Honour permanent earned achievements without converting missing current data to failure.
- [ ] Persist the daily card ID, content revision and mode on first view. Reopening, scanning, lighting another card or downloading content cannot reshuffle that day. Explicit skip may choose one alternative. If all cards have been seen, select an actual bundled, bilingual review exercise with a stable exercise ID. Add a small reviewed set rather than 365 new lessons. If no compatible exercise exists, say so. Show yesterday's tracked action with observed/not-yet/coverage-missing status and a stop-tracking control.
- [ ] Every changed card carries compatible tool/format range, steps, expected signal, validator ID or `self`, limitations and review ID. Audit the existing blanket savings, correctness and “问题少一半” claims. Replace unsupported promises with instructions and observable signals. Do not infer shell-test success by reading command arguments or output.

**zh / en copy:** `新技能 / New skill`; `待实践 / Ready to practise`; `复习 / Review`; `已开始，等待新记录 / Started; waiting for new records`; `日志已观察 / Observed in logs`; `再次使用 / Used again`; `历史记录 / Historical record`; `配置存在 / Configuration found`; `已尝试（自报） / Tried (self-reported)`; `当前工具暂不支持自动验证 / Automatic verification is not supported for this tool`; `昨天的动作已有后续记录 / A later record was found for yesterday's action`; `尚未观察到 / Not observed yet`; `未获得新数据 / No new data received`; `停止追踪 / Stop tracking`; `暂无适配练习，可复习已有内容 / No compatible exercise is available. Review an existing skill.` Review prompt `在另一个适合的任务中再次使用这项能力，完成后检查新记录。 / Use this capability again in another suitable task, then check the new records.`

**Acceptance:** Python `test_practice.py`, `test_codex_book.py`, `test_content_pool.py`, `test_village.py` cover view/copy/self/configuration/observation/reuse separately, old-event backfill, duplicate replay, one event matching multiple attempts, different-date same-session noise, stable same-day assignment after lighting/download/restart, all-24-seen fallback, incompatible versions, and legacy migration run twice. Swift `PracticeTests` and `TrainingTests` show every evidence label without purchase changing achievements; feedback is scoped to the selected card, not a global stale success. Worker N/A. Render today's and yesterday's states in zh/en with synthetic evidence.

**Network:** None for matching, evidence or bundled review. Optional public content continues through `ContentUpdater.swift` only.

### Task 30: Make estimates, history, and weekly review comparable

**Depends on:** 26–29. **Research:** T05, P0-06, P1-13/14.

**Files:** Modify `agentfit/engine/{profile.py,history.py,snapshot.py,content.py,content_pool.py,content_pool.json}`, identical `content/daily.json`, `macos/Sources/AIMaster/{Snapshot.swift,GrowthCurve.swift,CheckupTab.swift}`, existing history/profile/snapshot/Pro tests. Create `agentfit/engine/prices.py`, `tests/engine/test_prices.py`, `macos/Tests/AIMasterTests/HistoryCoverageTests.swift`. Leave legacy `agentfit/pricing.py` consumers untouched.

- [ ] Stop treating `TIER_PRICES[classify_model(...)]` as an exact engine price for every model. Use a versioned, reviewed model-price table with source URL/date, USD units, input/output/cache-read/cache-write prices and supported pricing conditions. No guessed prices in this planning run. An empty reviewed table is valid and produces unknown estimates. Compute known subtotals only, plus matched token coverage and unknown tokens/models. Unknown cache-write prices make that portion unknown. Do not label a partial subtotal as a complete total.
- [ ] Keep token categories separate and preserve current uncached input+output headline semantics with an explicit label. Quota comes only from the source log. Pass the actual primary/secondary window and reset/freshness through `usage_summary`; current code feeds primary percentage into a caption saying “weekly”. Show weekly only for a recorded weekly window, otherwise name its duration. No inferred remaining allowance or credential fallback.
- [ ] Extend existing 90-day history rows with score/rule version, coverage, nullable score, timezone and price version. Repeated scans overwrite one day's observation, not append a session score. Preserve legacy rows as `legacy_unknown_version`. Emit a 30-date calendar series with null gaps; line segments break on gaps/version changes. Never infer that a carried seven-day profile proves activity on a missing day.
- [ ] Replace latest-point week delta with an explicitly named same-version window. Compare mean valid daily scores for Monday through the latest completed local day against those same weekdays last week only when both have every required valid point and the same score version. Otherwise delta is null with a reason. Display difference in score points, not an invented improvement percentage. No backfilled historical scores unless sufficient retained input can reproduce them.
- [ ] Extend `WeeklyReviewSheet`, not a second report. A local template shows one observed change, one uncertainty and one next practice, with local metric/evidence IDs. Separate configuration/self-report from new observations and reuse. No comparable data means accumulating; no observed change means exactly that. Copy a sanitized text report on request. Free still has today's explanation and practice; existing long-history/review gates remain.

**zh / en copy:** `日志 Token（不含缓存读取） / Logged tokens (excluding cache reads)`; `按公开 API 单价折算，非订阅账单 / API-equivalent at public prices, not a subscription bill`; `已匹配部分折算 USD {amount}，价格覆盖 {pct}% / Matched subtotal USD {amount}, price coverage {pct}%`; `价格未知 / Price unknown`; `价格表日期 {date} / Price table dated {date}`; `Codex {hours} 小时窗口已用 {pct}% / Codex {hours}-hour window: {pct}% used`; `Codex 周窗口已用 {pct}% / Codex weekly window: {pct}% used`; `同星期窗口均分变化 {delta} 分 / Mean score change for matched weekdays: {delta} points`; `可比数据积累中 / Collecting comparable data`; `评分版本变化 / Scoring version changed`; `本周未观察到新的实践变化 / No new practice change was observed this week`; `下周练一步 / One practice for next week`.

**Acceptance:** Python `test_prices.py`, `test_profile.py`, `test_history.py` cover unknown model, unknown pricing condition, cache-write, partial coverage, no-price fallback, zero denominator, same-day overwrite, 90-day retention, null gap, legacy/version break, incomplete weeks, matched weekdays and evidence-linked review statements. Swift `HistoryCoverageTests` and `ProFeaturesTests` assert chart segments do not bridge gaps, no invented deltas, correct quota window captions and no bill/savings claim in either language. Worker N/A. Visible proof is a synthetic chart containing a gap and version break plus an accumulating weekly report.

**Network:** Core is offline. Task 32 may distribute the same reviewed public price table inside `daily.json`; no direct client pricing API.

### Task 31: Separate practice dates from usage streak and make reminders explicit

**Depends on:** 28–30. **Research:** T06, P1-09/12.

**Files:** Modify `agentfit/engine/{profile.py,codex_book.py,snapshot.py,content.py}`, `macos/Sources/AIMaster/{WeeklyNotifications.swift,SnapshotStore.swift,SettingsView.swift,StatusItemController.swift,TrainingTab.swift,Snapshot.swift}`, existing book/Pro/store tests. Create `macos/Sources/AIMaster/PracticeCalendar.swift`, `tests/engine/test_practice_calendar.py`, `macos/Tests/AIMasterTests/ReminderTests.swift`.

- [ ] Retain the existing log-use streak and earned thresholds, label its source accurately, and persist maximum earned badges rather than withdrawing them on a gap. Background app scans or popover opens never create AI-use or practice dates. Do not add another foreground-app streak. Add a free 30-day practice calendar using Task 29 evidence, with separate observed, self-reported, usage-only and unavailable states.
- [ ] Store original occurrence dates/timezones once. New timezone settings change future attribution, not historical achievements. Deduplicate days and ignore future-dated records until time is plausible. Reuse and practice require capability events, not a session merely crossing midnight. SHRINK optional rest/weekly goals to a no-penalty explanatory line in Phase 4; no freeze currency or protected days counted as activity.
- [ ] Replace automatic permission-on-Pro-activation with explicit reminder settings. Defaults are off, including existing installations without an explicit preference. Offer daily practice reminders free and weekly-review reminders only while review entitlement is active. Local report generation does not require notifications. Ask macOS permission only after enabling a setting. Denied stays denied without repeat prompts.
- [ ] Reuse the existing scheduler/delegate with one-shot, nonrepeating requests and a single local-date dedupe ledger. At most one combined reminder per local date, in the user-selected daytime slot; default slot 09:00 and quiet hours 21:00–09:00. Skip completed/no-new-content/no-valid-review dates. Cancel pending work on disable, pause or entitlement loss. Do not backfill missed reminders on wake. Let macOS honour Focus; do not inspect private Focus state or retry delivery. Badge changes remain static, never flashing. A tap opens the exact daily card or review by safe internal ID.

**zh / en copy:** `连续有 AI 使用记录 {n} 天 / AI usage recorded for {n} consecutive days`; `实践历 / Practice calendar`; `日志实践 / Observed practice`; `自报尝试 / Self-reported attempt`; `仅有使用记录 / Usage only`; `数据不可用 / Data unavailable`; `休息不会扣除已获成就 / Rest does not remove earned achievements`; `提醒默认关闭 / Reminders are off by default`; `每日练习提醒 / Daily practice reminder`; `周复盘提醒 / Weekly review reminder`; `暂停提醒 / Pause reminders`; `继续今天的一步 / Continue today's practice`.

**Acceptance:** Python `test_practice_calendar.py` and book tests replay midnight, Asia/Tokyo to America/Los_Angeles travel, DST transition, missing records, rollback and future events without duplicate or retroactively removed achievements. Swift `ReminderTests` uses a fake notification centre and injected clock/calendar to assert no prompt on activation/trial, denial persistence, one combined request, quiet hours, pause/off/expiry cancellation, wake skipping and correct routing. Update old Pro notification tests that expected activation to prompt. Worker N/A. Manually verify macOS denies/permits notifications and keyboard/VoiceOver calendar labels with synthetic state.

**Network:** None. No push server, email collection or remote notification token.

### Task 32: Extend the existing public package and isolate comparable rankings

**Depends on:** 27, 29–30. **Research:** T08, P1-10/11, bounded P2-20.

**Files:** Modify `scripts/harvest/harvest.py`, `agentfit/engine/{content_pool.py,content_pool.json,codex_book.py,snapshot.py}`, identical `content/daily.json`, `macos/Sources/AIMaster/{ContentUpdater.swift,ScoreReporter.swift,SnapshotStore.swift,Snapshot.swift,TodaySkillTab.swift,CheckupTab.swift}`, worker `src/index.js`, worker README, existing harvest/content/privacy/Swift score/content tests. Create `server/ranking-worker/migrations/0004_score_cohorts.sql` and `macos/Tests/AIMasterTests/PublicContentTests.swift`.

- [ ] Keep Task 18's harvest runner, content branch, schedule, Top20 selection and translation fallback. DROP the research's proposed parallel Worker/D1 content service. Add optional validated sections to the existing v1 public envelope for official tool updates and Task 30's reviewed prices. An absent section is valid. Updates contain stable ID, official source URL, fetched/released dates, compatible tool/format range, bilingual short summary and an existing practice ID. Restrict to Claude Code/Codex initially. Fetch only allow-listed official public sources in the operational harvester; fixtures first, no invented releases or inferred compatibility.
- [ ] Carry item source URL/date, source type, task category, compatibility and caution through ranking normalization to Swift. Unknown compatibility says unknown. A matching repository name is only an installation hint; do not promote it to a verified installation/use fact. Show a name match as an installation hint, not the current unconditional Installed claim. Keep Free Top5/Pro at most 20, displaying the actual count. Bundled examples are labelled curated content, not today's live leaderboard.
- [ ] Validate the full package before replacing last-good content in Swift, not just `version` and a nonempty skills array. Keep the one fixed URL, plain GET, no cookies/credentials/query/body/custom tracking headers, redirect rejection and size cap. Observe the public-download choice from Task 28. Persist attempted fetch time separately from successful fetch time to limit failures too. Failure keeps good cache and marks stale; absent cache uses bundled cards with explicit source. No tool update is a valid empty result, not a news feed. Do not execute external content.
- [ ] Preserve ranking opt-in and payload keys `device_token,score,dims,app_version`, with the existing random UUID and no additional identifier. Version comparability belongs in an explicit endpoint such as `/v1/score/<score_version>` and response, not extra local data in the payload. Route known versions to distinct D1 device/count/dimension cohorts. Do not assign old rows a version from `app_version` alone. Retain old endpoint/data as legacy, exclude it from new versioned comparisons, and hide a response whose version differs from the snapshot. Keep score version unchanged for otherwise identical evaluable arithmetic.
- [ ] Regression-test cohort totals and both overall/dimension rankings using the stored accepted score when a within-hour update is throttled. Current overall query binds the submitted score while dimensions use the stored row; fix that inconsistency within this task. Preserve atomic bucket updates, ties, per-hour writes, daily client limit and small-sample behaviour.
- [ ] At `total >= 20`, use Kenichi's exact overall wording below. Below 20 retain the existing early-rank strings, not the research's hidden-rank recommendation. Explain optional/self-selected installation samples and lack of person-level representativeness. Do not claim random UUIDs count unique humans. Keep Pro dimension gating and its existing small-sample captions.

**zh / en copy:** `与你的工具有关的更新 / Updates for your tools`; `暂无与你有关的更新 / No relevant updates`; `兼容性未知 / Compatibility unknown`; `发现同名安装项，未验证 / Matching installation name found; unverified`; `安装前请核对权限与来源 / Check permissions and source before installing`; `内置精选，非实时榜单 / Bundled selection, not a live leaderboard`; `缓存内容，更新于 {date} / Cached content, updated {date}`; `击败全球 {X}% 的 AI 用户 / You beat {X}% of AI users worldwide`. Keep the participation count separately. Small sample remains `早期排名：{N} 人中第 {K} 名 / Early ranking: #{K} of {N}`. Limitation `基于自愿参与的安装样本，不代表所有 AI 用户；同一人可能有多个安装 / Based on opt-in installations, not all AI users. One person may have multiple installations`. Version mismatch `评分版本不同，暂不比较 / Scoring versions differ; comparison unavailable`.

**Acceptance:** Python harvest tests use fake sources for limits, missing metadata, fewer than 20 real entries and no fabricated fields; content tests cover optional sections, unsafe URLs, invalid version/ranges and bundled fallback. Privacy tests keep exactly the two allowed network files and pin public endpoint/method/payload. Swift `PublicContentTests`, `ContentUpdaterTests`, `ScoreReporterTests`, `ScoreConsentTests` cover full validation before replacement, off means zero requests, failed-attempt daily limit, stale labels, incompatible update hiding, five/twenty/short list and version mismatch. Worker tests cover two isolated cohorts, legacy exclusion, wrong version, 19/20 boundary, ties, duplicate UUID, unchanged overall but changed dimensions, concurrent requests and throttled changed overall using the accepted row. Render exact zh/en large- and small-sample copy.

**Network:** Optional public download in `ContentUpdater.swift`; opt-in versioned score POST in `ScoreReporter.swift`; worker local D1 for tests. Operational harvest may fetch approved public metadata, as it already does, but no live harvest, schedule install, content push, remote migration or deployment is part of task acceptance without the existing reviewer authorization. No new Worker outbound fetch is needed here.

### Task 33: Add an explicit fourteen-day local Pro trial

**Depends on:** 31. **Research:** local part of T09, P1-15; spec §12 decision 2.

**Files:** Create `macos/Sources/AIMaster/ProTrial.swift`, `macos/Tests/AIMasterTests/ProTrialTests.swift`. Modify `macos/Sources/AIMaster/{License.swift,ProFeatures.swift,SnapshotStore.swift,SettingsView.swift,PopoverView.swift}`, existing license/Pro tests and `docs/license.md`.

- [ ] Model entitlement as `free`, `trial(until)`, or `licensed(payload)`, with licensed taking precedence. Reuse `ProFeatures` for all existing feature gates, including dimension comparison only when ranking separately opted in. Do not modify engine scores or achievements based on entitlement.
- [ ] Start exactly once when the user presses Start trial, never on installation, opening an advanced view or pressing Buy. Persist a consumed flag, UTC start, UTC end = start + 14 × 86400 seconds, maximum observed UTC time and terminal-expired flag in app-owned state. End is exclusive. Inject clock/storage for tests. Repeated start requests are idempotent. No card, checkout, account or network is involved.
- [ ] Evaluate on launch, refresh, foreground/wake and expiry timer so an open app drops to Free at the deadline. Persist expiry permanently before returning Free. Clock rollback below persisted maximum ends the trial rather than extends it; time-zone changes do not alter UTC expiry. Corrupt existing trial state fails closed and cannot start another trial. Deliberate app-state reset/reinstallation abuse is accepted and documented. Do not add Keychain, hardware IDs or tool credential reads to prevent it.
- [ ] At expiry keep all local records and today's free practice accessible. Gate only the existing advanced views and cancel Pro-only reminders without prompting. Starting a trial must not request notification permission. Use contextual advanced-feature entry and Settings, not a first-run purchase modal.

**zh / en copy:** `免费体验 Pro 14 天 / Try Pro free for 14 days`; `无需银行卡，不自动扣款。体验到期后回到免费版，历史记录保留。 / No card required and no automatic charge. After the trial, return to Free and keep your history.`; `开始体验 / Start trial`; `体验至 {date} / Trial until {date}`; `体验已结束，历史记录已保留 / Trial ended. Your history is preserved.`; `设备时间发生回拨，体验已结束 / The device clock moved backwards. The trial has ended.` The purchase area's separate auto-renewal terms must not imply that the trial auto-converts.

**Acceptance:** Swift `ProTrialTests`, `LicenseTests`, `ProFeaturesTests` cover unopened/eligible, explicit start, 13d23h59m, exact 14-day boundary, open-app expiry, restart/wake, timezone and clock rollback/forward/back, corrupt state, idempotent start, expired no-retrial, valid license superseding trial and all feature gates. Assert persisted history byte-for-byte unchanged on expiry and zero transport/permission calls. Python/worker N/A. Render eligible, active and expired states in both languages.

**Network:** None. A trial does not enable score sharing or public downloads.

### Task 34: Define subscription lifecycle and accountless renewal behind a payment interface

**Depends on:** 33 for shared entitlement terminology; no client transport dependency. **Research:** server part of T09, P1-15; spec §12 decision 1.

**Files:** Create `server/ranking-worker/src/{subscriptions.js,payment-provider.js}`, `server/ranking-worker/migrations/0005_subscriptions.sql`, `server/ranking-worker/test/subscriptions.test.js`, `server/ranking-worker/test/fakes/payment-provider.js`. Modify worker `src/index.js`, `test/license.test.js`, worker README and `docs/license.md`. Retain existing key generation/admin tooling, without running it against real accounts.

- [ ] Define `PaymentProvider.verifyWebhook(rawBytes, headers)` and `getSubscription(providerRef)` at the provider boundary. Return normalized provider event ID, subscription/order refs, event ordering/revision, paid-through period, renewal/cancel-at-period-end status, refund/revocation status, and verified management URL. Domain logic must not invent Waffo headers, event names or authentication algorithms. The default Waffo adapter returns unavailable and keeps the real webhook fail-closed with `TODO(WAFFO_VERIFIED_INTEGRATION)` naming official docs, sandbox fixtures and cancellation/recovery checks still required. A fake is injected only in tests, never selected by a public request or production flag.
- [ ] Extend D1 with unique verified provider event IDs, unique order/period identity, stable `lic` to provider subscription mapping, paid-through entitlement, terminal revocation/revision and issued key per paid period. Keep billing rows isolated from ranking UUIDs. Do not store raw webhooks, card data, email or usage events. Redact authorization and key data from responses/logs except the explicit no-store key response.
- [ ] Apply verified initial payment/renewal/cancel-at-period-end/refund events idempotently and atomically. Only a verified paid period can extend entitlement. Pending/failed renewal never extends it. Duplicate or concurrent delivery returns the same persisted key, not another year. Out-of-order older active events cannot undo a newer refund/revocation. Cancellation preserves the already-paid period; refund/revocation prevents future refresh but does not pretend to revoke an offline key instantly. Use normalized provider ordering; if order cannot be established, reconcile via `getSubscription` or fail closed.
- [ ] Preserve AIM1/Ed25519 and stable license ID across renewal. Sign through the verified paid-through boundary, never `now + 365` on every refresh. Define UTC calendar-date conversion for existing inclusive `exp` so it does not exceed the provider entitlement period; do not assume a billing year is always 365 days. Legacy/manual licenses remain valid through their signed expiration and do not become subscriptions automatically. Make legacy admin issuance idempotent by order reference as well.
- [ ] Add `POST /v1/license/refresh` with exact bounded body `{lic, key}`. The key is this app's own signed activation proof, not an AI-tool credential. Verify signature, format, `lic` match and known issuance even if that key expired, then resolve its subscription. License ID alone is not authorization. Reissue the same stable license with the latest verified paid-through expiry only while entitlement is valid. An expired key can recover after a genuine paid renewal, but a guessed ID, tampered key, unknown issuance, pending payment or revoked subscription cannot.
- [ ] Responses use `Cache-Control: no-store`; no keys in URL/query/normal logs, no listing endpoint, no app admin token. Bound/rate-limit per-license refresh attempts and return safe unavailable/expired status. A provider outage yields retryable unavailable rather than granting more time. Recovery without the old key requires the verified merchant receipt/support flow; no account or license enumeration is added.

**zh / en copy:** Worker returns enum codes, translated by the client in 35. Document support copy `订阅仍有效，可重新获取激活码 / Your subscription is still active. You can refresh your activation key`; `付款仍在确认中 / Payment is still being confirmed`; `请使用购买收据联系支持恢复授权 / Use your purchase receipt to contact support for license recovery`. Do not invent a working Waffo recovery or cancellation URL.

**Acceptance:** Worker `subscriptions.test.js` and `license.test.js` use local D1 and generated test keys for initial payment, renewal before/after key expiry, cancellation preserving period, expired paid period, failed/pending renewal, duplicate/concurrent callback and refresh, idempotent admin order, forged/missing proof, revoked key, refund followed by stale active event, reconciliation failure and unavailable provider. Verify stable `lic`, no expiry inflation, signature validity, date boundary, exact bounded fields and no sensitive logs. Default real webhook remains unavailable and cannot be driven by a fake from HTTP. Python/Swift N/A for this server unit. A fake-backed lifecycle transcript is acceptable evidence; real Waffo integration stays explicitly unverified.

**Network:** Tests need none beyond the local worker runtime. Only the worker provider adapter may later call verified Waffo APIs or receive its webhook. No credentials/private signing keys in source or app; existing worker secrets remain operator-managed. No real webhook is implemented from guessed details, no secrets configured and no production migration/deploy in this task.

### Task 35: Connect renewal and disclose yearly purchase terms before checkout

**Depends on:** 32–34. **Research:** client part of T09, P1-15/17; spec §12 decision 1.

**Files:** Modify `macos/Sources/AIMaster/{License.swift,ScoreReporter.swift,SnapshotStore.swift,SettingsView.swift,PopoverView.swift,ProFeatures.swift,EngineRunner.swift}`, `agentfit/engine/{content_pool.py,content_pool.json}`, identical `content/daily.json`, `server/ranking-worker/src/payment-provider.js`, both localization files, `docs/license.md`, `tests/engine/test_privacy.py` and existing license/score tests. Create `macos/Sources/AIMaster/CourseSource.swift`, `macos/Tests/AIMasterTests/{SubscriptionTests.swift,CourseSourceTests.swift}`. No third network-capable Swift file.

- [ ] Define a transport protocol and pure renewal result/state in `License.swift`. Implement requests only in `ScoreReporter.swift`, in a separate license transport type. Keep `ScoreReporter.Payload` exactly unchanged. Derive an allow-listed `/v1/license/refresh` URL from the same fixed worker origin. Ephemeral HTTPS POST, no cookies/URL credentials/redirects, bounded response and timeout. Renewal body is only Task 34's `lic,key`; never score UUID, app history or telemetry. Update privacy assertions to check both precise request contracts and the unchanged two-file allowlist, not to broadly exempt all network code.
- [ ] Separate local signature validation from expiry entitlement checking. Keep the expired signed proof for refresh without treating it as current Pro. On launch/wake/foreground, check when within seven days of signed expiry or expired; attempt at most once per 24 hours, with one explicit user retry available. Auto-refresh preference is explained when importing/activating a subscription key and can be disabled. No trial/free user requests. Coalesce concurrent triggers. Local analysis never waits for the network.
- [ ] If the worker returns a same-`lic`, correctly signed current key, atomically replace and revalidate it. Preserve last valid key on tamper, timeout or wrong-lic response. Already-signed Pro works offline through its expiry. At expiry without a fresh key, fall back to Free, keep history and show retry; do not grant unlimited offline renewal. Refresh failure is not proof cancellation succeeded. Existing manual keys work through expiry and show manual-authorization status if not linked to a subscription.
- [ ] Before opening checkout, show founding price USD $12 per year, yearly automatic renewal, cancellation method, entitlement period/expiry, support/refund entry and that the local trial never charges automatically. Put the same terms at each contextual Buy entry, not only in Settings. No lifetime price guarantee. Checkout and manage/cancel buttons remain unavailable while URLs, verified terms or real provider integration are missing. Browser return means pending confirmation; only an authentic signed key activates Pro.
- [ ] Do not add a cancellation API based on guessed Waffo semantics. A verified provider management link or the receipt's documented cancellation instructions must exist before real checkout is enabled. Open management explicitly in the browser; never cancel or charge on a background app action. Signed period and billing next-renewal date are distinct labels. Claim “cancelled” only from verified provider status, not a button click.
- [ ] Add an optional bounded course source code field, matching reviewed entries in public/bundled content with stable practice IDs. Store locally, offer that practice without blocking free daily learning, and include the code in checkout only after a separate user selection. Blank/unknown/invalid codes do not enter a checkout URL. Do not append device ID, license proof or learning records. No confirmed creator codes are invented; an empty catalogue is supported. Tests use synthetic codes. No rewards, commission accounting or outbound creator contact.

**zh / en copy:** `Pro 创始价 USD $12/年，每年自动续费 / Pro founding price: USD $12/year, renews automatically every year`; `取消方式：通过购买收据中的已验证订阅管理入口，在下次续费前取消 / To cancel, use the verified subscription-management link in your purchase receipt before the next renewal`; `取消后可使用至已付费期限结束 / After cancellation, access continues until the paid period ends`; `14 天本地体验无需银行卡，不会自动转为付费 / The 14-day local trial needs no card and never automatically becomes paid`; `自动刷新激活码会向授权服务发送授权编号及签名激活码，不发送使用记录 / Automatic key refresh sends your license ID and signed activation key to the license service, never usage records`; `自动刷新授权 / Refresh license automatically`; `本地激活码有效至 {date} / Local activation key valid through {date}`; `重新获取激活码 / Refresh activation key`; `连接后可检查订阅续期；当前历史已保留 / Connect to check subscription renewal. Your history is preserved`; `管理或取消订阅 / Manage or cancel subscription`; `支付接入待验证，暂不可购买 / Payment integration is not verified. Checkout is unavailable`; `课程来源码（可选） / Course source code (optional)`; `付款时附带此来源码 / Include this source code at checkout`.

**Acceptance:** Swift `SubscriptionTests`, `LicenseTests`, `ProFeaturesTests`, `CourseSourceTests` use fake transport/clock to cover renewal extending a still-active subscription across local key expiry, expired-proof recovery, no-account/no-admin-token requests, off/no-license/no-trial requests, attempt throttling, one coalesced request, explicit retry, tamper/wrong-lic/outage handling, manual-key compatibility and offline fallback without lost history. Test checkout placeholder disabled, terms visible before any browser-open call, cancellation link only from verified allow-listed config and no activation on browser return. Assert source code absent unless selected, never mixed with renewal/ranking. Python privacy/content tests assert exact endpoint/method/body allowlists and empty course catalogue. Worker Task 34 contract tests must still pass. Render full paywall and pending/offline/cancel-at-period-end states in zh/en. Real merchant checkout/cancellation/recovery cannot be marked passed from fakes.

**Network:** License renewal only through `ScoreReporter.swift` to the worker. Checkout/management are explicit browser opens to verified configured Waffo destinations. Public course metadata rides the existing optional download. No engine networking, new accounts, content upload or automatic payment action.

### Task 36: Add a free sanitized share card and local validation view

**Depends on:** 29–31, 33–35 for local entitlement events. **Research:** T07, P1-16, bounded P2-22 and §10 metrics.

**Files:** Create `agentfit/engine/local_metrics.py`, `tests/engine/test_local_metrics.py`, `macos/Sources/AIMaster/{ShareCard.swift,LocalValidationView.swift}`, `macos/Tests/AIMasterTests/{ShareCardTests.swift,LocalValidationTests.swift}`. Modify `agentfit/engine/{__main__.py,snapshot.py,content.py}`, `macos/Sources/AIMaster/{EngineRunner.swift,SnapshotStore.swift,StatusItemController.swift,SettingsView.swift,TrainingTab.swift,CopyButton.swift}` and both localization files.

- [ ] Add a bounded local event ledger of enum names, internal object IDs, UTC time/local date and result only. Record foreground-open explicitly from the status-item user action, not from startup/refresh timers. Reuse practice ledger evidence instead of fabricating “completed” click events. Retain a rolling 90 days with small aggregate counters; expose window/truncation. Record first launch only when observed on a new installation. For existing installations, keep installation date unknown and record a separate measurement start; do not invent an earlier install date or D1/D7 cohort. Serialize all engine mutations, including trial/activation events, to avoid lost updates.
- [ ] Provide a Settings diagnostic view, not another main tab. Show local first-practice funnel, D1/D7 foreground return and practice separately, new-observation/attempt rate, distinct-day reuse, unsupported coverage, trial starts and local activation/renewal status. Always label the denominator and observation window. This is one installation; do not present a population retention rate or causal lift. Unknown installation date or not-yet day-seven remains unknown. Label post-upgrade measurement cohorts separately from new installations. Distinguish imported key verification from a new purchase; browser-open never counts paid. No raw payment/license values enter the event ledger.
- [ ] Make a free static growth card with preview, copy image and user-chosen save via macOS save panel. Its renderer accepts only a typed whitelist of date range, reviewed capability titles, evidence labels and optionally user-selected known score/coverage. No user name, paths, event hashes, conversation text, course source code, license, remote asset or tracking URL. Strip image metadata. Default is no score. Record preview/save/copy only, never off-platform publication or download attribution.
- [ ] Provide an optional feedback summary assembled from coverage enums, selected stuck reason, app/schema versions and counts. Preview it before copying; no automatic send, attachment, network upload or support form submission. Closing without copying has no external side effect.

**zh / en copy:** `分享我的练习 / Share my practice`; `预览 / Preview`; `复制图片 / Copy image`; `保存图片 / Save image`; `包含分数与覆盖期 / Include score and coverage period`; `仅本机验证记录，不代表能力认证 / Local practice record, not a certification of ability`; `本机验证面板 / Local validation`; `仅代表本次安装，不会上报 / This installation only. Nothing is reported`; `已复制，尚未发布 / Copied, not published`; `复制脱敏反馈 / Copy sanitized feedback`; `尚未到观察日期 / Observation date has not arrived`.

**Acceptance:** Python `test_local_metrics.py` replays install/start/copy/self-report/new-event/next-day-reuse/D1/D7, unavailable coverage, late import, duplicate commands and 90-day expiry with exact denominators. Copy/checkout/browser return must not count observed/paid. Swift `ShareCardTests` asserts only whitelist input, deterministic synthetic rendering, no forbidden fields or metadata, no remote image load, save cancellation and no publish calls; `LocalValidationTests` assert foreground versus background counting and preview-before-copy feedback. Verify all remains available on Free after trial/license expiry. Worker N/A. Render and inspect both-language exported images for clipping and privacy.

**Network:** None. No analytics, referral beacon, social API or send action. The user may publish a saved image outside this product.

### Task 37: Prove the integrated loop and document release blockers

**Depends on:** 26–36. **Research:** T10 and research §11 exclusions.

**Files:** Extend `tests/engine/{test_snapshot.py,test_privacy.py,test_build_engine.py,test_package_app.py}`, `tests/harvest/test_harvest.py`, `macos/Tests/AIMasterTests/{RenderPreviewTests.swift,SnapshotStoreTests.swift}`, worker `test/{index.test.js,license.test.js,subscriptions.test.js}` and synthetic fixtures. Create `tests/engine/test_phase4_flow.py`, `docs/testing/phase4-acceptance.md`. Modify `scripts/build_engine.sh` and `scripts/package_app.sh` only if new bundled data needs inclusion. Record limitations in `docs/license.md`; update spec only to reconcile delivered behaviour in a later implementation run.

- [ ] Replay with injected dates and synthetic homes: first run, safe-source choice, copy/start, no validation from old evidence, new observation, different-date reuse, gap/version-aware weekly review, explicit trial, trial expiry retaining history, fake verified annual payment, cancellation retaining paid access, verified renewal reissuing the same license, and offline verification through signed expiry. Include empty, unsupported, denied-permission, corrupted-state and provider-outage paths. Repeat the replay to prove no duplicate achievements, purchases, periods or trial starts.
- [ ] Run `.venv/bin/python -m pytest -q`, `(cd macos && swift build && swift test)`, and `(cd server/ranking-worker && npm test)` with installed dependencies and local D1. Record actual baseline exceptions and exact results. Rebuild/package without publishing and run the bundled engine against synthetic fixtures. Ensure new data is present without a developer Python install; use `.venv/bin/python` only to inspect JSON outside the bundled process.
- [ ] Capture requests through fake transports/local test worker and a controlled macOS run with synthetic state. Enumerate public GET, opted-in versioned score POST, consented license-refresh POST and explicit browser opens. Prove public-download off + rank off + license-refresh off yields no product network request while local practice still works. Reject prompt/path/argument/token sentinels from outgoing bodies, URLs, exports and logs. This covers application payloads, not an impossible promise that network infrastructure processes no IP metadata.
- [ ] On macOS, drive all three tabs, cancel/retry, exact notification destination, keyboard/VoiceOver, light/dark and reduced motion. Save synthetic zh/en screenshots and a short review video. Verify 440×720 popover scrolling and click-outside/Esc behaviour remain intact. Benchmark fixture cold scan, incremental scan and UI-open latency at baseline and task head with the same fixture and interleaved runs; record measurements and an agreed budget before declaring a regression pass. No invented performance claim.
- [ ] Audit every user-facing money/ranking/trial string and each research §11 exclusion. Mark Waffo real signature verification, merchant sandbox renewal/refund/cancellation/receipt recovery, real public-source compatibility, app signing/notarization and external usability evidence as passed only when actually exercised. The fake integration may be complete while merchant release remains blocked. Never enable live checkout from fake-backed success.
- [ ] Prepare a reviewable local trial build, known limitations, request inventory and a short observer checklist for one target user's first-practice/return-to-check flow. No invitations, external sends, public release, schedule installation, real transactions or production data changes without specific authorization.

**zh / en copy:** Reuse Tasks 26–36; no new marketing promises. Acceptance report status labels are `已验证 / Verified`, `未运行 / Not run`, `未验证 / Unverified`, and `受阻 / Blocked`. Keep `支付接入待验证，暂不可购买 / Payment integration is not verified. Checkout is unavailable` while the real-provider gate is open.

**Acceptance:** Python `test_phase4_flow.py` verifies the local sequence and privacy/packaging regressions; Swift store/preview/trial/subscription/reminder suites verify user-visible states and entitlement transitions; worker score/license/subscription suites verify isolated cohorts and idempotent renewal. `docs/testing/phase4-acceptance.md` records command results, synthetic artefact paths, request allowlist and each unverified release item separately. A local build or a full fake-backed test pass is not evidence of a live payment integration, adoption, retention or paid demand.

**Network:** Automated acceptance uses fake transports and local worker/D1. Actual public downloads and merchant sandbox tests need network and the corresponding test access; record unavailable access rather than substituting real payments. Production deploy/publish remains reviewer-controlled and outside this plan.
