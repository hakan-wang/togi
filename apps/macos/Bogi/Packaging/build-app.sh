#!/usr/bin/env bash
# Assemble, sign, notarize, and package Bogi.app into a DMG.
#
# GATED on an Apple Developer ID: set DEVELOPER_ID (e.g. "Developer ID Application: Name (TEAMID)")
# and notarization creds (NOTARY_PROFILE from `xcrun notarytool store-credentials`).
# Without DEVELOPER_ID the script refuses to build unless you pass ALLOW_UNSIGNED=1, which
# produces an unsigned .app for LOCAL testing only — never distribute it (see the keychain
# note at the unsigned branch below).
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
# Copy the mascot image straight into Contents/Resources so it loads via Bundle.main
# on every Mac. (SwiftPM resource bundles are NOT copied: their generated Bundle.module
# accessor only resolves at the .app root or the build machine's .build path — neither
# exists in a shipped app, so it crashes off-machine; and a .bundle under Contents/MacOS
# is unsigned nested code that breaks codesign. See BogiTheme.swift / Package.swift.)
cp "Sources/BogiApp/Resources/mascot.png" "$APP/Contents/Resources/mascot.png"
# App icon. CFBundleIconFile=Togi in Info.plist points here; macOS loads it for the
# Finder/Dock/About icon. Must live directly in Contents/Resources.
cp "$PKG/Togi.icns" "$APP/Contents/Resources/Togi.icns"

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

  # Build a read-WRITE DMG first so Finder can record a window layout (icon positions,
  # window size, icon view), then convert to a compressed read-only DMG for distribution.
  # A bare `hdiutil create … -format UDZO` (read-only) can't hold a layout, which is why
  # the old DMG showed an unstyled, unarranged window.
  RW_DMG="build/Togi-rw.dmg"
  rm -f "$RW_DMG"
  hdiutil create -volname Togi -srcfolder "$DMG_STAGE" -fs HFS+ \
    -format UDRW -ov "$RW_DMG"

  # Mount at the default /Volumes/Togi (NOT a custom mountpoint) so Finder can address the
  # volume as `disk "Togi"` to save the layout. Capture the device node for a clean detach.
  DEVICE="$(hdiutil attach "$RW_DMG" -noverify -noautoopen | grep -E '^/dev/' | head -1 | awk '{print $1}')"

  # Arrange the window via Finder. Best-effort: if Finder scripting is unavailable (headless
  # CI), the layout step is skipped but the DMG still ships with the app + Applications symlink.
  osascript <<'APPLESCRIPT' || echo "(Finder layout skipped — DMG still valid)"
on run
  tell application "Finder"
    tell disk "Togi"
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 120, 740, 480}
      set theViewOptions to the icon view options of container window
      set arrangement of theViewOptions to not arranged
      set icon size of theViewOptions to 112
      set position of item "Togi.app" of container window to {150, 180}
      set position of item "Applications" of container window to {410, 180}
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
APPLESCRIPT

  sync
  hdiutil detach "$DEVICE" -force || hdiutil detach "/Volumes/Togi" -force || true

  hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"
  rm -f "$RW_DMG"
  rm -rf "$DMG_STAGE"
}

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
  # An UNSIGNED build is dangerous to distribute: because each unsigned binary has a
  # different (ad-hoc) code-signing identity, macOS can't match it to the identity that
  # created the app's Keychain items, so end users get the recurring "Togi wants to use
  # confidential information stored in your keychain" prompt (plus Gatekeeper warnings).
  # A signed+notarized build creates and reads its own items under one stable Developer ID
  # identity and never prompts. So refuse to build unsigned unless explicitly opted in for
  # local testing — this makes an accidental unsigned RELEASE impossible.
  if [ "${ALLOW_UNSIGNED:-}" != "1" ]; then
    echo "ERROR: DEVELOPER_ID is unset." >&2
    echo "  For a RELEASE: export DEVELOPER_ID (and NOTARY_PROFILE) and re-run." >&2
    echo "  For LOCAL testing only: re-run with ALLOW_UNSIGNED=1 (do NOT distribute the result)." >&2
    exit 1
  fi
  create_dmg
  echo "DEVELOPER_ID unset — built UNSIGNED $APP and $DMG for local testing only (ALLOW_UNSIGNED=1)."
fi
echo "done: $APP"
echo "done: $DMG"
