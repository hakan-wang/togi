#!/usr/bin/env bash
# Assemble, sign, notarize, and package Bogi.app into a DMG.
#
# GATED on an Apple Developer ID: set DEVELOPER_ID (e.g. "Developer ID Application: Name (TEAMID)")
# and notarization creds (NOTARY_PROFILE from `xcrun notarytool store-credentials`).
# Without them, the script still builds + assembles the unsigned .app for local testing.
set -euo pipefail
cd "$(dirname "$0")/.."          # apps/macos/Bogi
APP="build/Togi.app"             # bundle ships as Togi.app (executable inside stays Bogi)
PKG="Packaging"

echo "== build release =="
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Bogi"

echo "== assemble $APP =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bogi"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
# Copy any remaining SwiftPM resource bundles (e.g. GRDB's privacy-manifest bundle).
# NOTE: the mascot is no longer an SPM resource — see below.
for bundle in "$(dirname "$BIN")"/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$APP/Contents/MacOS/"
  cp -R "$bundle" "$APP/Contents/Resources/"
done
# The mascot is loaded via Bundle.main (see BogiTheme.swift), so it must live directly in
# Contents/Resources — NOT inside an SPM resource bundle (whose Bundle.module accessor only
# resolves on the build machine and crashed the app everywhere else).
cp "Sources/BogiApp/Resources/mascot.png" "$APP/Contents/Resources/mascot.png"
# App icon (referenced by CFBundleIconFile=Togi in Info.plist).
cp "$PKG/Togi.icns" "$APP/Contents/Resources/Togi.icns"

# Flat SwiftPM resource bundles (no Info.plist) can't be codesigned. Inject a minimal
# Info.plist so the hardened-runtime sign pass accepts them.
for b in "$APP/Contents/MacOS"/*.bundle "$APP/Contents/Resources"/*.bundle; do
  [ -e "$b" ] || continue
  [ -f "$b/Info.plist" ] && continue
  cat > "$b/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>
PLIST
done

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "== codesign nested bundles =="
  find "$APP" -name '*.bundle' -print0 | while IFS= read -r -d '' b; do
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$b"
  done

  echo "== codesign (hardened runtime) =="
  codesign --force --options runtime --timestamp \
    --entitlements "$PKG/Bogi.entitlements" \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  echo "== dmg (styled: background + Applications drop-link) =="
  DMG="build/Togi.dmg"
  rm -f "$DMG"
  # create-dmg styles the Finder window via AppleScript; --hdiutil-quiet keeps output tidy.
  create-dmg \
    --volname "Togi" \
    --volicon "$PKG/Togi.icns" \
    --background "$PKG/dmg-bg.png" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 120 \
    --icon "Togi.app" 165 190 \
    --hide-extension "Togi.app" \
    --app-drop-link 495 190 \
    --no-internet-enable \
    "$DMG" "$APP"

  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "== notarize + staple =="
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
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
  echo "== sign main executable (local; DEVELOPER_ID unset) =="
  # Prefer a real identity so the signature is STABLE across rebuilds — that keeps macOS
  # permission grants (Accessibility etc.) from resetting every build. Falls back to ad-hoc.
  SIGN_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')"
  [ -z "$SIGN_ID" ] && SIGN_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')"
  [ -z "$SIGN_ID" ] && SIGN_ID="-"
  echo "signing identity: $SIGN_ID"
  tmp="$(mktemp -d)"
  cp "$APP/Contents/MacOS/Bogi" "$tmp/Bogi"
  codesign --force --sign "$SIGN_ID" --identifier sh.bogi.app --entitlements "$PKG/Bogi.entitlements" "$tmp/Bogi"
  cp "$tmp/Bogi" "$APP/Contents/MacOS/Bogi"
  rm -rf "$tmp"
  codesign --verify --verbose=2 "$APP/Contents/MacOS/Bogi" && echo "executable signature OK"
  echo "open $APP directly (right-click → Open the first time if Finder warns about the developer)."
fi
echo "done: $APP"
