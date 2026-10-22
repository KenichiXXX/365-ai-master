"""Opt-in only. Source logs stay read-only and the snapshot is never saved."""
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

from agentfit.engine.collectors.claude_code import ClaudeCodeCollector
from agentfit.engine.scan_state import ScanState


@pytest.mark.skipif(os.environ.get("RUN_REAL_HOME_SMOKE") != "1", reason="real HOME requires explicit opt-in")
def test_real_home_scores_when_claude_has_usage(tmp_path):
    home = Path.home()
    events = ClaudeCodeCollector().scan(home, ScanState(tmp_path / "count.json"))
    if sum(bool(event.model) for event in events) < 100:
        pytest.skip("fewer than 100 valid Claude usage records")
    result = subprocess.run(
        [sys.executable, "-m", "agentfit.engine", "snapshot", "--json", "--home", str(home),
         "--state-dir", str(tmp_path / "state")], capture_output=True, text=True, check=True,
    )
    assert json.loads(result.stdout)["overall"]["score"] is not None
