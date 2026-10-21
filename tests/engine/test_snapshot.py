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
    assert s["schema"] == 3 and s["locale"] == "zh"
    assert {t["tool"] for t in s["tools"] if t["detected"]} == {"claude_code", "codex"}
    assert [d["key"] for d in s["dimensions"]] == ["routing", "timing", "context", "leverage"]
    assert s["dimensions"][0]["label"] == "模型路由"
    assert len(s["village"]["quests"]) == 9 and s["village"]["rank_title"].startswith("AI")
    assert s["today_tip"]["prompt_for_claude"]
    assert s["quota"]["codex"]["primary_pct"] == 42.5
    assert s["overall"]["tier"] is None
    assert s["overall"]["availability"] == "unavailable"
    assert s["dimensions"][2]["score"] is None

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
    assert json.loads(out.stdout)["schema"] == 3


def test_inventory_import_in_fresh_process():
    out = subprocess.run([sys.executable, "-c", "import agentfit.engine.inventory"],
                         capture_output=True, text=True)
    assert out.returncode == 0, out.stderr


def test_enabled_tools_and_repeat_scan(tmp_path):
    home, state = _home(tmp_path), tmp_path / "state"
    first = build_snapshot(home, state, "en", now=NOW, enabled={"claude_code"})
    second = build_snapshot(home, state, "en", now=NOW, enabled={"claude_code"})
    assert first == second
    assert [t["tool"] for t in first["tools"]] == ["claude_code"]
    assert first["quota"]["codex"] is None
    assert set(first["inventory"]) == {"claude_code"}
    empty = build_snapshot(home, state, "en", now=NOW, enabled=set())
    assert empty["tools"] == [] and empty["inventory"] == {}
    assert empty["notices"][0] == "no_tools"


def test_collector_failure_is_sanitized(tmp_path, monkeypatch):
    from agentfit.engine.collectors.base import REGISTRY
    collector = next(c for c in REGISTRY if c.tool == "codex")
    def fail(*args):
        raise OSError("private content /secret/path")
    monkeypatch.setattr(collector, "scan", fail)
    s = build_snapshot(_home(tmp_path), tmp_path / "state", "en", now=NOW)
    rows = {t["tool"]: t for t in s["tools"]}
    assert rows["codex"]["error"] == "unavailable"
    assert rows["claude_code"]["error"] is None
    assert rows["codex"]["usage_7d"] == {"tokens": 0, "cost_usd": None}
    assert "private content" not in json.dumps(s)


def test_cli_error_is_sanitized(tmp_path):
    state = tmp_path / "not_a_directory"
    state.write_text("occupied")
    out = subprocess.run([sys.executable, "-m", "agentfit.engine", "snapshot", "--json",
                          "--home", str(tmp_path / "empty"), "--state-dir", str(state)],
                         capture_output=True, text=True)
    assert out.returncode == 2
    assert json.loads(out.stdout) == {"schema": 3, "error": "FileExistsError"}
    assert out.stderr == ""


def test_old_state_events_are_pruned(tmp_path):
    from datetime import timedelta
    home, state = _home(tmp_path), tmp_path / "state"
    build_snapshot(home, state, "en", now=NOW)
    snapshot = build_snapshot(home, state, "en", now=NOW + timedelta(days=31))
    assert all(t["usage_7d"]["tokens"] == 0 for t in snapshot["tools"])
    saved = json.loads((state / "scan.json").read_text())
    assert all(not cursor["events"] for files in saved["tools"].values() for cursor in files.values())


def test_snapshot_includes_localized_notice_labels(tmp_path):
    from agentfit.engine.content import label
    for locale in ("zh", "en"):
        snapshot = build_snapshot(tmp_path / "empty", tmp_path / locale, locale, now=NOW)
        assert snapshot["labels"] == {
            key: label(key, locale) for key in ("no_tools", "tool_unavailable")
        }


def test_snapshot_v2_blocks(tmp_path):
    s = build_snapshot(_home(tmp_path), tmp_path / "state", "en", now=NOW)
    assert s["book"]["total"] == 24
    assert isinstance(s["book"]["today"]["title"], str)
    assert set(s["rankings"]) == {"skill", "agent"}
    assert isinstance(s["daily_tip"]["detail"], str)
    assert s["streak"]["days"] == 1
    assert len(s["badges"]) == 9
    usage = s["usage_summary"]
    assert usage["tokens_7d"] == sum(t["usage_7d"]["tokens"] for t in s["tools"])
    assert usage["cost_usd_7d"] is None
    assert usage["price_estimate"]["unknown_tokens"] > 0
    assert usage["codex_quota"]["primary_pct"] == 42.5
    assert usage["codex_quota"]["primary_window_min"] == 300
    assert usage["codex_quota"]["secondary_window_min"] == 10080
    assert usage["codex_quota"]["recorded_at"]
    assert usage["codex_quota"]["freshness"] == "stale"
    empty = build_snapshot(tmp_path / "empty", tmp_path / "empty-state", "zh", now=NOW)
    assert empty["usage_summary"]["tokens_7d"] == 0
    assert empty["usage_summary"]["cost_usd_7d"] is None
    assert empty["usage_summary"]["codex_quota"] is None
    assert empty["streak"] == {"days": 0, "label": "连续有 AI 使用记录 0 天"}


def test_content_override_and_mark_tried_cli(tmp_path):
    from agentfit.engine.content_pool import load_content
    content = load_content(None)
    content["skills"] = [{**content["skills"][-1], "id": "custom_self"}]
    content["skills"][0]["title"]["en"] = "Custom title"
    path = tmp_path / "content.json"
    path.write_text(json.dumps(content))
    state = tmp_path / "state"
    command = [sys.executable, "-m", "agentfit.engine"]
    snapshot = ["snapshot", "--json", "--home", str(tmp_path / "empty"),
                "--state-dir", str(state), "--locale", "en", "--content", str(path)]
    def run(args):
        out = subprocess.run(command + args, capture_output=True, text=True)
        assert out.returncode == 0, out.stderr
        return json.loads(out.stdout)
    assert run(snapshot)["book"]["today"]["title"] == "Custom title"
    assert run(["mark-tried", "custom_self", "--state-dir", str(state)]) == {"ok": True}
    assert run(snapshot)["book"]["today"]["how"] == "self"
    assert run(["mark-tried", "web_search", "--state-dir", str(state)]) == {"ok": False}
    assert run(["mark-tried", "missing", "--state-dir", str(state)]) == {"ok": False}


def test_first_practice_is_bundled_even_with_all_sources_declined(tmp_path):
    for locale in ("zh", "en"):
        s = build_snapshot(tmp_path / "empty", tmp_path / locale, locale, now=NOW, enabled=set())
        practice = s["first_practice"]
        assert practice["prompt"] and practice["no_project_prompt"]
        assert practice["validation_kind"] == "self_reported"
        assert s["village"]["quests"][0]["status"] == "current"
        assert all(q["evidence_kind"] == "unsupported" for q in s["village"]["quests"])
        assert json.loads((tmp_path / locale / "progress.json").read_text())["passed"] == {}
