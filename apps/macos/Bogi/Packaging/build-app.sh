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
# Copy SwiftPM resource bundles (e.g. Bogi_BogiApp.bundle holding the mascot image) so
# Bundle.module resolves at runtime inside the .app.
for bundle in "$(dirname "$BIN")"/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$APP/Contents/MacOS/"
  cp -R "$bundle" "$APP/Contents/Resources/"
done
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
  # No Developer ID: make sure the main executable is ad-hoc signed so it launches on Apple
  # Silicon (a fully unsigned binary is killed as "damaged"). The linker already ad-hoc signs
  # it; we re-sign explicitly via a temp copy. Signing it in place is impossible because
  # codesign, pointed at a bundle's main executable, redirects to sign the whole bundle, and
  # the flat SwiftPM resource bundle (Bogi_BogiApp.bundle, no Info.plist) can't be signed.
  # TCC permissions ride this ad-hoc identity, so they may need re-granting after a rebuild.
  echo "== ad-hoc sign main executable (local testing; DEVELOPER_ID unset) =="
  tmp="$(mktemp -d)"
  cp "$APP/Contents/MacOS/Bogi" "$tmp/Bogi"
  codesign --force --sign - --entitlements "$PKG/Bogi.entitlements" "$tmp/Bogi"
  cp "$tmp/Bogi" "$APP/Contents/MacOS/Bogi"
  rm -rf "$tmp"
  codesign --verify --verbose=2 "$APP/Contents/MacOS/Bogi" && echo "executable signature OK"
  echo "open $APP directly (right-click → Open the first time if Finder warns about the developer)."
fi
echo "done: $APP"
