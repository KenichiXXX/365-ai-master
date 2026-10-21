"""Exercise the packaging entry point and the standalone offline executable."""
import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest

from agentfit.engine.__main__ import main

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).parent / "fixtures"


def test_main_accepts_argv(tmp_path, capsys):
    assert main([
        "snapshot", "--json", "--home", str(tmp_path / "empty"),
        "--state-dir", str(tmp_path / "state"), "--locale", "en",
    ]) == 0
    snapshot = json.loads(capsys.readouterr().out)
    assert snapshot["schema"] == 3
    assert len(snapshot["tools"]) == 5


@pytest.mark.skipif(os.environ.get('RUN_BUILD_TESTS') != '1', reason='slow: rebuilds the binary; set RUN_BUILD_TESTS=1')
def test_standalone_engine_without_python_on_path(tmp_path):
    build = subprocess.run(
        [str(ROOT / "scripts/build_engine.sh")], cwd=tmp_path,
        env={**os.environ, "TMPDIR": str(tmp_path)},
        capture_output=True, text=True, timeout=300,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    binary = ROOT / "dist/365engine"
    assert binary.is_file() and os.access(binary, os.X_OK)

    home = tmp_path / "home"
    shutil.copytree(FIXTURES / "claude", home / ".claude")
    shutil.copytree(FIXTURES / "codex", home / ".codex")
    run = subprocess.run(
        [str(binary), "snapshot", "--json", "--state-dir", str(tmp_path / "state"),
         "--locale", "en", "--home", str(home)],
        cwd=tmp_path,
        env={"PATH": "/usr/bin:/bin", "TMPDIR": str(tmp_path)},
        capture_output=True, text=True, timeout=60,
    )
    assert run.returncode == 0, run.stderr
    snapshot = json.loads(run.stdout)
    assert snapshot["schema"] == 3
    assert len(snapshot["tools"]) == 5
    assert {t["tool"] for t in snapshot["tools"] if t["detected"]} == {"claude_code", "codex"}
    assert all(t["error"] is None for t in snapshot["tools"])
    assert len(snapshot["village"]["quests"]) == 9
    assert snapshot["quota"]["codex"]["primary_pct"] == 42.5
    assert str(tmp_path) not in run.stdout

    assert snapshot["book"]["total"] == 24
    assert snapshot["first_practice"]["no_project_prompt"]
    assert snapshot["growth"]["comparison"]["window"] == "matched_completed_weekdays"
    assert snapshot["local_validation"]["paid_purchases"] is None
    for command in (["practice", "init_cmd", "copy"], ["practice", "init_cmd", "self"],
                    ["local-event", "trial_start"], ["local-event", "trial_start"]):
        mutation = subprocess.run([str(binary), *command, "--state-dir", str(tmp_path / "state")],
            cwd=tmp_path, env={"PATH": "/usr/bin:/bin", "TMPDIR": str(tmp_path)},
            capture_output=True, text=True, timeout=60)
        assert mutation.returncode == 0 and mutation.stderr == ""
        assert json.loads(mutation.stdout) == {"ok": True}
    replay = subprocess.run([str(binary), "snapshot", "--json", "--home", str(home),
        "--state-dir", str(tmp_path / "state"), "--locale", "zh"], cwd=tmp_path,
        env={"PATH": "/usr/bin:/bin", "TMPDIR": str(tmp_path)}, capture_output=True, text=True, timeout=60)
    assert replay.returncode == 0 and replay.stderr == ""
    result = json.loads(replay.stdout)
    assert result["local_validation"]["trial_starts"] == 1
    assert next(c for c in result["book"]["cards"] if c["id"] == "init_cmd")["evidence_kind"] == "self_reported"
    assert str(tmp_path) not in replay.stdout
