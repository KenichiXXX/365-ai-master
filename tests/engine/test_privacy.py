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
