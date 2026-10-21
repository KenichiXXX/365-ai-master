import re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
BANNED = re.compile(r"\b(import (urllib|http\.client|requests|httpx|socket)|from (urllib|http|requests|httpx|socket)\b|URLSession|NWConnection)")

def _files():
    yield from (ROOT / "agentfit" / "engine").rglob("*.py")
    yield from (ROOT / "macos").rglob("*.swift")

def test_no_network_code():
    hits = [str(p) for p in _files() if p != ROOT / "macos/Sources/AIMaster/ContentUpdater.swift"
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
    assert urls == ["https://raw.githubusercontent.com/19800104zhao-svg/365-ai-master/content/daily.json"]
    assert 'httpMethod = "GET"' in text
    for banned in ("httpBody", "setValue(", "addValue(", "uploadTask", "NWConnection"):
        assert banned not in text
