"""App metadata and opt-in verification of the real, signed bundle."""
import os
from pathlib import Path
import plistlib
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[2]
EXPECTED = {
    "CFBundleName": "365 AI Master",
    "CFBundleIdentifier": "com.tonyzhao.365aimaster",
    "CFBundleExecutable": "AIMaster",
    "CFBundleShortVersionString": "2.0.0",
    "CFBundleVersion": "2",
    "LSMinimumSystemVersion": "13.0",
    "LSUIElement": True,
    "CFBundleDevelopmentRegion": "en",
    "CFBundleLocalizations": ["en", "zh-Hans"],
}


def test_app_metadata():
    with (ROOT / "macos/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    for key, value in EXPECTED.items():
        assert info[key] == value


def test_packager_is_executable():
    script = ROOT / "scripts/package_app.sh"
    assert script.is_file() and os.access(script, os.X_OK)


@pytest.mark.skipif(os.environ.get("RUN_PACKAGE_TESTS") != "1", reason="slow: builds and signs app; set RUN_PACKAGE_TESTS=1")
def test_real_app_bundle(tmp_path):
    result = subprocess.run([str(ROOT / "scripts/package_app.sh")], cwd=tmp_path,
                            capture_output=True, text=True, timeout=300)
    assert result.returncode == 0, result.stdout + result.stderr
    app = ROOT / "dist/365 AI Master.app"
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    for key, value in EXPECTED.items():
        assert info[key] == value
    for relative in ["MacOS/AIMaster", "Resources/365engine"]:
        binary = app / "Contents" / relative
        assert binary.is_file() and os.access(binary, os.X_OK)
    bundles = list((app / "Contents/Resources").glob("*.bundle"))
    assert bundles, "SwiftPM localization bundle must be shipped"
    for locale in ["en", "zh-Hans"]:
        assert any(p.parent.name.lower() == f"{locale}.lproj".lower()
                   for bundle in bundles for p in bundle.rglob("Localizable.strings"))
    verify = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)],
                            capture_output=True, text=True)
    assert verify.returncode == 0, verify.stderr


def test_phase4_packager_keeps_one_offline_engine_and_localizations():
    # Source inspection only: Task 37's execution constraints prohibit packaging.
    source = (ROOT / "scripts/package_app.sh").read_text()
    assert 'cp dist/365engine "$APP/Contents/Resources/365engine"' in source
    assert 'cp -R "$BIN_DIR/AIMaster_AIMaster.bundle"' in source
    build = (ROOT / "scripts/build_engine.sh").read_text()
    assert "--add-data agentfit/engine/content_pool.json:agentfit/engine" in build
    assert "--onefile" in build and ".venv/bin/python -m PyInstaller" in build
