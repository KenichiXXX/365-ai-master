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
    assert rows["codex"]["usage_7d"] == {"tokens": 0, "cost_usd": 0.0}
    assert "private content" not in json.dumps(s)


def test_cli_error_is_sanitized(tmp_path):
    state = tmp_path / "not_a_directory"
    state.write_text("occupied")
    out = subprocess.run([sys.executable, "-m", "agentfit.engine", "snapshot", "--json",
                          "--home", str(tmp_path / "empty"), "--state-dir", str(state)],
                         capture_output=True, text=True)
    assert out.returncode == 2
    assert json.loads(out.stdout) == {"schema": 1, "error": "FileExistsError"}
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
