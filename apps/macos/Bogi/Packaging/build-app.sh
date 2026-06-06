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
PKG="Packaging"

echo "== build release =="
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Bogi"

echo "== assemble $APP =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bogi"
cp "$PKG/Info.plist" "$APP/Contents/Info.plist"
# Copy the mascot image straight into Contents/Resources so it loads via Bundle.main
# on every Mac. (SwiftPM resource bundles are NOT copied: their generated Bundle.module
# accessor only resolves at the .app root or the build machine's .build path — neither
# exists in a shipped app, so it crashes off-machine; and a .bundle under Contents/MacOS
# is unsigned nested code that breaks codesign. See BogiTheme.swift / Package.swift.)
cp "Sources/BogiApp/Resources/mascot.png" "$APP/Contents/Resources/mascot.png"

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

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "== codesign sidecar (hardened runtime) =="
  # Sign EVERY Mach-O binary nested in the sidecar BEFORE the outer .app, so the deep
  # signature is valid and notarization passes. This must cover not just the Node runtime
  # and native .node addons, but also plain executables shipped inside node_modules
  # (e.g. esbuild's bin/esbuild, @esbuild/darwin-arm64/bin/esbuild) which have no .node
  # extension — notarization rejects ANY unsigned Mach-O, hardened-runtime-less binary.
  find "$SIDECAR_DST" -type f -print0 | \
    while IFS= read -r -d '' f; do
      if file -b "$f" | grep -q "Mach-O"; then
        codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$f"
      fi
    done

  echo "== codesign (hardened runtime) =="
  codesign --force --options runtime --timestamp \
    --entitlements "$PKG/Bogi.entitlements" \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"

  echo "== dmg =="
  rm -f build/Togi.dmg
  # Stage the DMG contents so the mounted window offers a drag-to-install layout:
  # the app next to an /Applications symlink. Without the symlink users just see a
  # lone icon and don't know to drag it into Applications.
  DMG_STAGE="build/dmg-stage"
  rm -rf "$DMG_STAGE"
  mkdir -p "$DMG_STAGE"
  cp -R "$APP" "$DMG_STAGE/"
  ln -s /Applications "$DMG_STAGE/Applications"
  hdiutil create -volname Togi -srcfolder "$DMG_STAGE" -ov -format UDZO build/Togi.dmg
  rm -rf "$DMG_STAGE"

  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "== notarize + staple =="
    xcrun notarytool submit build/Togi.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple build/Togi.dmg
    xcrun stapler staple "$APP"
  else
    echo "NOTARY_PROFILE unset — skipping notarization (DMG is signed but not notarized)."
  fi
else
  echo "DEVELOPER_ID unset — built UNSIGNED $APP for local testing only."
fi
echo "done: $APP"
