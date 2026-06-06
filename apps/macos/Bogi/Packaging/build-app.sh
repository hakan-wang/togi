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

echo "== sidecar (Node + LangChain.js agent) =="
SIDECAR_SRC="sidecar"
RESOURCES="$APP/Contents/Resources"
SIDECAR_DST="$RESOURCES/sidecar"
NODE_VERSION="v22.11.0"
NODE_PKG="node-${NODE_VERSION}-darwin-arm64"

( cd "$SIDECAR_SRC" && npm ci && npm run build )

mkdir -p "$SIDECAR_DST"
cp "$SIDECAR_SRC/dist/main.cjs" "$SIDECAR_DST/main.cjs"
# Ship the native better-sqlite3 module next to the bundle so require() resolves it.
cp -R "$SIDECAR_SRC/node_modules/better-sqlite3" "$SIDECAR_DST/better-sqlite3"

# Embed the pinned Node runtime.
if [ ! -x "$SIDECAR_DST/node" ]; then
  curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_PKG}.tar.gz" -o "/tmp/${NODE_PKG}.tar.gz"
  tar xzf "/tmp/${NODE_PKG}.tar.gz" -C /tmp
  cp "/tmp/${NODE_PKG}/bin/node" "$SIDECAR_DST/node"
fi

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "== codesign sidecar (hardened runtime) =="
  # Sign nested executables BEFORE the outer .app so the deep signature is valid.
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$SIDECAR_DST/node"
  find "$SIDECAR_DST/better-sqlite3" -name "*.node" -print0 | \
    while IFS= read -r -d '' f; do
      codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$f"
    done

  echo "== codesign (hardened runtime) =="
  codesign --force --options runtime --timestamp \
    --entitlements "$PKG/Bogi.entitlements" \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"

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
