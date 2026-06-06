#!/usr/bin/env bash
# Assemble, sign, notarize, and package Bogi.app into a DMG.
#
# GATED on an Apple Developer ID: set DEVELOPER_ID (e.g. "Developer ID Application: Name (TEAMID)")
# and notarization creds (NOTARY_PROFILE from `xcrun notarytool store-credentials`).
# Without them, the script still builds + assembles the unsigned .app for local testing.
set -euo pipefail
cd "$(dirname "$0")/.."          # apps/macos/Bogi
# User-facing product name. The on-disk bundle name and DMG volume name are what
# Finder shows, so these MUST be "Togi" (the executable inside stays "Bogi" to match
# CFBundleExecutable). Anything named Bogi here leaks the internal name to users.
APP="build/Togi.app"
APP_ZIP="build/Togi.app.zip"
DMG="build/Togi.dmg"
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
# Ship the sidecar's node_modules so native deps (better-sqlite3 -> bindings ->
# file-uri-to-path) resolve. main.cjs lives in Resources/sidecar/, so Node resolves
# Resources/sidecar/node_modules automatically — no explicit NODE_PATH needed.
cp -R "$SIDECAR_SRC/node_modules" "$SIDECAR_DST/node_modules"

# Embed the pinned Node runtime.
if [ ! -x "$SIDECAR_DST/node" ]; then
  curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_PKG}.tar.gz" -o "/tmp/${NODE_PKG}.tar.gz"
  tar xzf "/tmp/${NODE_PKG}.tar.gz" -C /tmp
  cp "/tmp/${NODE_PKG}/bin/node" "$SIDECAR_DST/node"
fi

create_dmg() {
  echo "== dmg =="
  rm -f "$DMG"
  # Stage the DMG contents so the mounted window offers a drag-to-install layout:
  # the app next to an /Applications symlink. Without the symlink users just see a
  # lone icon and don't know to drag it into Applications.
  DMG_STAGE="build/dmg-stage"
  rm -rf "$DMG_STAGE"
  mkdir -p "$DMG_STAGE"
  cp -R "$APP" "$DMG_STAGE/"
  ln -s /Applications "$DMG_STAGE/Applications"
  hdiutil create -volname Togi -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG"
  rm -rf "$DMG_STAGE"
}

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "== codesign sidecar (hardened runtime) =="
  # Sign nested executables BEFORE the outer .app so the deep signature is valid.
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$SIDECAR_DST/node"
  find "$SIDECAR_DST/node_modules" -name "*.node" -print0 | \
    while IFS= read -r -d '' f; do
      codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$f"
    done

  echo "== codesign (hardened runtime) =="
  codesign --force --options runtime --timestamp \
    --entitlements "$PKG/Bogi.entitlements" \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"

  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "== notarize + staple app =="
    rm -f "$APP_ZIP"
    ditto -c -k --keepParent "$APP" "$APP_ZIP"
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
  else
    echo "NOTARY_PROFILE unset — skipping app notarization."
  fi

  create_dmg

  echo "== codesign dmg =="
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
  codesign --verify --strict --verbose=2 "$DMG"

  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "== notarize + staple dmg =="
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
  else
    echo "NOTARY_PROFILE unset — skipping DMG notarization."
  fi
else
  create_dmg
  echo "DEVELOPER_ID unset — built UNSIGNED $APP and $DMG for local testing only."
fi
echo "done: $APP"
echo "done: $DMG"
