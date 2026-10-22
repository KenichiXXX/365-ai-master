import re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
BANNED = re.compile(r"\b(import (urllib|http\.client|requests|httpx|socket)|from (urllib|http|requests|httpx|socket)\b|URLSession|NWConnection)")

def _files():
    yield from (ROOT / "agentfit" / "engine").rglob("*.py")
    yield from (ROOT / "macos").rglob("*.swift")

def test_no_network_code():
    hits = [str(p) for p in _files() if p not in {ROOT / "macos/Sources/AIMaster/ContentUpdater.swift",
                                      ROOT / "macos/Sources/AIMaster/ScoreReporter.swift"}
            and BANNED.search(p.read_text(encoding="utf-8"))]
    assert hits == []

def test_no_credential_paths():
    for p in (ROOT / "agentfit" / "engine").rglob("*.py"):
        t = p.read_text(encoding="utf-8")
        assert "auth.json" not in t and ".credentials" not in t and "Keychain" not in t, p


def test_content_updater_only_fetches_fixed_public_content():
    text = (ROOT / "macos/Sources/AIMaster/ContentUpdater.swift").read_text(encoding="utf-8")
    assert BANNED.search(text.replace("URLSession", "")) is None
    urls = re.findall(r'https://[^"\s]+', text)
    assert urls == ["https://raw.githubusercontent.com/KenichiXXX/365-ai-master/content/daily.json"]
    assert 'httpMethod = "GET"' in text
    assert 'httpShouldHandleCookies = false' in text
    assert 'URLSessionConfiguration.ephemeral' in text
    assert 'httpCookieStorage = nil' in text
    assert 'urlCredentialStorage = nil' in text
    for banned in ("httpBody", "setValue(", "addValue(", "uploadTask", "NWConnection"):
        assert banned not in text


def test_score_reporter_only_posts_anonymous_scores():
    text = (ROOT / "macos/Sources/AIMaster/ScoreReporter.swift").read_text(encoding="utf-8")
    urls = re.findall(r'https://[^"\s]+', text)
    assert len(urls) == 1
    assert re.fullmatch(r"https://[A-Za-z0-9.-]+\.workers\.dev/v1/score", urls[0])
    assert 'httpMethod = "POST"' in text
    assert 'appendingPathComponent(scoreVersion)' in text
    assert 'result.score_version == scoreVersion' in text
    payload = re.search(r"struct Payload: Encodable\s*\{([^}]+)\}", text).group(1)
    assert re.findall(r"(?:let|var) (\w+):", payload) == ["device_token", "score", "dims", "app_version"]
    for banned in ("uploadTask", "multipart", "NWConnection"):
        assert banned not in text


def test_action_evidence_and_feedback_do_not_export_tool_arguments_or_paths(tmp_path):
    from datetime import datetime, timezone
    import json
    from agentfit.engine.action_rules import action_feedback
    from agentfit.engine.snapshot import build_snapshot
    now = datetime(2026, 10, 21, 12, tzinfo=timezone.utc)
    home = tmp_path / "home"
    log = home / ".codex/sessions/a.jsonl"
    log.parent.mkdir(parents=True)
    rows = [
        {"type": "turn_context", "payload": {"model": "gpt-6.1-sol", "cwd": "/private/project-sentinel"}},
        {"type": "event_msg", "payload": {"type": "task_started"}},
        {"type": "response_item", "payload": {"type": "function_call", "name": "shell", "call_id": "a1",
            "arguments": "private-argument-sentinel"}},
        {"type": "token_usage_record", "payload": {"response_id": "r1", "turn_id": "t1",
            "usage": {"input_tokens": 500, "cached_input_tokens": 400, "output_tokens": 20}}},
    ]
    log.write_text("".join(json.dumps({**row, "timestamp": now.isoformat()}) + "\n" for row in rows))
    state = tmp_path / "state"
    first = build_snapshot(home, state, "en", now=now)
    assert first["overall"]["score"] is not None
    assert first["dimensions"][0]["evidence"]
    assert action_feedback(state / "progress.json", first["today_tip"]["action_id"], "not_suitable", "no_project", now.date())
    second = build_snapshot(home, state, "en", now=now)
    for raw in (json.dumps(first), json.dumps(second), (state / "progress.json").read_text()):
        for forbidden in ("private-argument-sentinel", "/private/project-sentinel", str(home)):
            assert forbidden not in raw


def test_license_transport_is_separate_exact_and_bounded():
    source = (ROOT / "macos/Sources/AIMaster/ScoreReporter.swift").read_text()
    license = (ROOT / "macos/Sources/AIMaster/License.swift").read_text()
    payload = re.search(r"struct LicenseRefreshRequest: Encodable\s*\{([^}]+)\}", license).group(1)
    assert re.findall(r"(?:let|var) (\w+):", payload) == ["lic", "key"]
    transport = source.split("struct LicenseServiceTransport:", 1)[1]
    assert 'appendingPathComponent("license/refresh")' in transport
    assert 'request.httpMethod = "POST"' in transport
    assert 'JSONEncoder().encode(proof)' in transport
    assert 'URLSessionConfiguration.ephemeral' in transport
    assert 'session.bytes(for: request)' in transport
    assert 'data.count < 8192' in transport
    assert 'request.url == endpoint' in transport
    assert 'httpCookieStorage = nil' in transport and 'urlCredentialStorage = nil' in transport
    assert 'ScoreRedirectPolicy()' in transport
    for forbidden in ('device_token', 'anonDeviceToken', 'app_version', 'scoreVersion', 'Authorization', 'courseSource'):
        assert forbidden not in transport
    assert 'completionHandler(nil)' in source


def test_phase4_cli_exports_and_logs_reject_all_private_sentinels(tmp_path, capsys):
    import json
    from agentfit.engine.__main__ import main
    from tests.engine.test_phase4_flow import NOW, SENTINELS, append_event
    home, state = tmp_path / "home", tmp_path / "state"
    append_event(home, "synthetic", NOW)
    for locale in ("zh", "en"):
        assert main(["snapshot", "--json", "--home", str(home), "--state-dir", str(state),
                     "--locale", locale]) == 0
        output = capsys.readouterr()
        snapshot = json.loads(output.out)
        assert snapshot["schema"] == 3
        assert output.err == ""
        for sentinel in (*SENTINELS, str(home)):
            assert sentinel not in output.out + output.err
            assert sentinel not in snapshot["weekly"]["report_text"]
    # Internal scan cursors contain source paths by design; they are not an export.
    for name in ("progress.json", "local_metrics.json"):
        saved = (state / name).read_text()
        for sentinel in (*SENTINELS, str(home)):
            assert sentinel not in saved


def test_engine_has_no_model_clients_or_process_escape_hatches():
    """Keep scoring unable to acquire an SDK, network client or external CLI."""
    import ast
    forbidden = {"urllib", "http", "requests", "httpx", "socket", "aiohttp", "openai",
                 "anthropic", "google", "litellm", "transformers", "torch", "ollama",
                 "jev", "subprocess", "importlib", "ctypes", "multiprocessing"}
    for path in (ROOT / "agentfit/engine").rglob("*.py"):
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                assert not {n.name.split('.')[0] for n in node.names} & forbidden, path
            elif isinstance(node, ast.ImportFrom):
                assert (node.module or "").split('.')[0] not in forbidden, path
            elif isinstance(node, ast.Call):
                if isinstance(node.func, ast.Name):
                    assert node.func.id not in {"__import__", "eval", "exec"}, path
                elif isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name):
                    assert not (node.func.value.id == "os" and node.func.attr in {
                        "system", "popen", "posix_spawn", "posix_spawnp", "execv", "execve",
                        "execl", "execlp", "execvp", "execvpe", "spawnl", "spawnv"}), path


def test_snapshot_runs_with_network_and_external_processes_disabled(tmp_path, monkeypatch):
    import socket
    import subprocess
    from datetime import datetime, timezone
    from agentfit.engine.snapshot import build_snapshot
    def denied(*args, **kwargs):
        raise AssertionError("Local analysis must not use network or external models")
    monkeypatch.setattr(socket, "socket", denied)
    monkeypatch.setattr(subprocess, "Popen", denied)
    result = build_snapshot(tmp_path / "empty-home", tmp_path / "state", "en",
                            now=datetime(2026, 10, 22, tzinfo=timezone.utc))
    assert result["schema"] == 3
