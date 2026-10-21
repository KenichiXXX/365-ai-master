import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def test_keypair_script_exports_matching_ed25519_keys():
    generated = subprocess.run(["node", "server/ranking-worker/scripts/gen_keypair.mjs"],
                               cwd=ROOT, capture_output=True, text=True, check=True)
    keys = json.loads(generated.stdout)
    code = """
const { privateKey, publicKey } = JSON.parse(process.argv[1]);
const priv = await crypto.subtle.importKey('pkcs8', Buffer.from(privateKey, 'base64'), 'Ed25519', false, ['sign']);
const pub = await crypto.subtle.importKey('raw', Buffer.from(publicKey, 'base64'), 'Ed25519', false, ['verify']);
if (Buffer.from(publicKey, 'base64').length !== 32) process.exit(1);
const data = new TextEncoder().encode('offline license');
const signature = await crypto.subtle.sign('Ed25519', priv, data);
if (!await crypto.subtle.verify('Ed25519', pub, signature, data)) process.exit(1);
"""
    verified = subprocess.run(["node", "--input-type=module", "-e", code, json.dumps(keys)],
                              capture_output=True, text=True)
    assert verified.returncode == 0


def test_issue_script_requires_env_and_sends_json_without_shell_interpolation(tmp_path):
    script = ROOT / "scripts/issue_key.sh"
    clean_env = {k: v for k, v in os.environ.items() if k not in {"ADMIN_TOKEN", "LICENSE_ISSUE_URL"}}
    missing = subprocess.run(["bash", str(script), "order-1"], env=clean_env, capture_output=True)
    assert missing.returncode != 0
    capture = tmp_path / "args.json"
    fake_curl = tmp_path / "curl"
    fake_curl.write_text("#!/bin/sh\nexec \"$TEST_PYTHON\" -c 'import json,os,sys; open(os.environ[\"CAPTURE\"], \"w\").write(json.dumps(sys.argv[1:]))' \"$@\"\n")
    fake_curl.chmod(0o755)
    environment = {**clean_env, "PATH": str(tmp_path) + os.pathsep + os.environ["PATH"],
                   "TEST_PYTHON": sys.executable, "CAPTURE": str(capture), "ADMIN_TOKEN": "test-token",
                   "LICENSE_ISSUE_URL": "https://example.workers.dev/v1/license/issue"}
    order = 'order-"quoted"-$(never-run)'
    result = subprocess.run(["bash", str(script), order], env=environment, capture_output=True)
    assert result.returncode == 0, result.stderr.decode()
    args = json.loads(capture.read_text())
    assert "Authorization: Bearer test-token" in args
    assert "https://example.workers.dev/v1/license/issue" in args
    assert json.loads(args[args.index("--data") + 1]) == {"order_ref": order, "days": 365}
    assert "--fail-with-body" in args
