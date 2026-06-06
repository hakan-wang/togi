#!/usr/bin/env bash
# Assemble, sign, notarize, and package Bogi.app into a DMG.
#
# GATED on an Apple Developer ID: set DEVELOPER_ID (e.g. "Developer ID Application: Name (TEAMID)")
# and notarization creds (NOTARY_PROFILE from `xcrun notarytool store-credentials`).
# Without them, the script still builds + assembles the unsigned .app for local testing.
set -euo pipefail
cd "$(dirname "$0")/.."          # apps/macos/Bogi
APP="build/Bogi.app"
PKG="Packaging"

echo "== build release =="
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Bogi"

echo "== assemble $APP =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bogi"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
# cp -R "$PKG/Assets/"* "$APP/Contents/Resources/" 2>/dev/null || true   # mascot art later

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "== codesign (hardened runtime) =="
  codesign --force --options runtime --timestamp \
    --entitlements "$PKG/Bogi.entitlements" \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  echo "== dmg =="
  rm -f build/Bogi.dmg
  hdiutil create -volname Bogi -srcfolder "$APP" -ov -format UDZO build/Bogi.dmg

  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "== notarize + staple =="
    xcrun notarytool submit build/Bogi.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple build/Bogi.dmg
    xcrun stapler staple "$APP"
  else
    echo "NOTARY_PROFILE unset — skipping notarization (DMG is signed but not notarized)."
  fi
else
  echo "DEVELOPER_ID unset — built UNSIGNED $APP for local testing only."
fi
echo "done: $APP"
