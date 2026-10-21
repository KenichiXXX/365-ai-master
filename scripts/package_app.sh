#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep compiler caches and temporary build files inside the worktree.
mkdir -p "$PWD/build/swift-cache/tmp"
export CLANG_MODULE_CACHE_PATH="$PWD/build/swift-cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/swift-cache/modules"
export TMPDIR="$PWD/build/swift-cache/tmp"
[ -x dist/365engine ] || scripts/build_engine.sh
swift build --package-path macos --disable-sandbox --cache-path "$PWD/build/swift-cache" -c release
BIN_DIR="$(swift build --package-path macos --disable-sandbox --cache-path "$PWD/build/swift-cache" -c release --show-bin-path)"
# SwiftPM's build layout varies by toolchain; never silently omit UI resources.
[ -x "$BIN_DIR/AIMaster" ]
[ -d "$BIN_DIR/AIMaster_AIMaster.bundle" ]
APP="dist/365 AI Master.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp macos/Info.plist "$APP/Contents/Info.plist"
cp "$BIN_DIR/AIMaster" "$APP/Contents/MacOS/AIMaster"
cp -R "$BIN_DIR/AIMaster_AIMaster.bundle" "$APP/Contents/Resources/"
cp dist/365engine "$APP/Contents/Resources/365engine"
codesign --force --deep --sign - "$APP"
echo "built: $APP"
