#!/usr/bin/env bash
# One-command macOS release: build, sign with the hardened runtime, make a DMG, then optionally notarize and publish.
#
#   scripts/release_mac.sh                      ad-hoc signed DMG for testers (no Apple account needed)
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/release_mac.sh --notarize
#   SIGN_IDENTITY="…" scripts/release_mac.sh --publish          notarize, then create the GitHub release (asks first)
#   SIGN_IDENTITY="…" scripts/release_mac.sh --publish --yes    same, without the prompt
#
# Notarization reads the keychain profile created once with:
#   xcrun notarytool store-credentials 365AIMaster --apple-id <Apple ID> --team-id <Team ID>
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-365AIMaster}"
REPO="${RELEASE_REPO:-KenichiXXX/365-ai-master}"
NOTARIZE=0 PUBLISH=0 ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=1 ;;
    --publish) NOTARIZE=1; PUBLISH=1 ;;
    --yes) ASSUME_YES=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" macos/Info.plist)
APP="dist/365 AI Master.app"
OUT="dist/release"
DMG="$OUT/365-AI-Master-$VERSION.dmg"
TIMESTAMP=()
if [ "$IDENTITY" = "-" ]; then
  [ "$NOTARIZE" = 0 ] || { echo "Notarizing needs a Developer ID: set SIGN_IDENTITY (see security find-identity -v -p codesigning)" >&2; exit 1; }
else
  security find-identity -v -p codesigning | grep -qF "$IDENTITY" || { echo "Signing identity not found in the keychain: $IDENTITY" >&2; exit 1; }
  TIMESTAMP=(--timestamp)
fi
if [ "$NOTARIZE" = 1 ] && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notary profile '$NOTARY_PROFILE' is missing: run xcrun notarytool store-credentials first" >&2; exit 1
fi
[ -z "$(git status --porcelain -- macos agentfit scripts)" ] || echo "warning: uncommitted changes in macos/, agentfit/ or scripts/ will ship in this build"
echo "365 AI Master $VERSION · signing: $([ "$IDENTITY" = "-" ] && echo "ad-hoc (testers only)" || echo "Developer ID")"

echo "1/6 engine"
SIGN_IDENTITY="$IDENTITY" scripts/build_engine.sh

echo "2/6 app bundle"
scripts/package_app.sh

echo "3/6 sign (hardened runtime, inside out)"
codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --entitlements macos/engine.entitlements \
  --sign "$IDENTITY" "$APP/Contents/Resources/365engine"
codesign --force --options runtime ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"
"$APP/Contents/Resources/365engine" --help >/dev/null

echo "4/6 dmg"
rm -rf "$OUT" && mkdir -p "$OUT/stage"
ditto "$APP" "$OUT/stage/365 AI Master.app"
ln -s /Applications "$OUT/stage/Applications"
hdiutil create -quiet -volname "365 AI Master" -srcfolder "$OUT/stage" -ov -format UDZO "$DMG"
rm -rf "$OUT/stage"
[ "$IDENTITY" = "-" ] || codesign --force --timestamp --sign "$IDENTITY" "$DMG"
hdiutil verify -quiet "$DMG"

echo "5/6 notarize"
if [ "$NOTARIZE" = 1 ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
else
  echo "skipped: needs SIGN_IDENTITY and --notarize"
fi
(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo "6/6 publish"
if [ "$PUBLISH" = 1 ]; then
  cp "$DMG" "$OUT/365-AI-Master.dmg"
  (cd "$OUT" && shasum -a 256 365-AI-Master.dmg > 365-AI-Master.dmg.sha256)
  if [ "$ASSUME_YES" = 0 ]; then
    read -r -p "Publish v$VERSION publicly on github.com/$REPO? [y/N] " answer
    [ "$answer" = "y" ] || { echo "not published; the DMG is in $OUT"; exit 0; }
  fi
  gh release create "v$VERSION" "$OUT/365-AI-Master.dmg" "$OUT/365-AI-Master.dmg.sha256" \
    --repo "$REPO" --title "365 AI Master $VERSION" --notes-file docs/v2/release-notes.md
  echo "download: https://github.com/$REPO/releases/latest/download/365-AI-Master.dmg"
else
  echo "skipped: run with --publish after notarizing"
fi
ls -lh "$OUT"
