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
    for banned in ("httpBody", "setValue(", "addValue(", "uploadTask", "NWConnection"):
        assert banned not in text


def test_score_reporter_only_posts_anonymous_scores():
    text = (ROOT / "macos/Sources/AIMaster/ScoreReporter.swift").read_text(encoding="utf-8")
    urls = re.findall(r'https://[^"\s]+', text)
    assert len(urls) == 1
    assert re.fullmatch(r"https://[A-Za-z0-9.-]+\.workers\.dev/v1/score", urls[0])
    assert 'httpMethod = "POST"' in text
    payload = re.search(r"struct Payload: Encodable\s*\{([^}]+)\}", text).group(1)
    assert re.findall(r"(?:let|var) (\w+):", payload) == ["device_token", "score", "dims", "app_version"]
    for banned in ("uploadTask", "multipart", "NWConnection"):
        assert banned not in text
