#!/usr/bin/env bash
set -euo pipefail

SCRIPT="${1:-Packaging/build-app.sh}"

require() {
  local pattern="$1"
  local message="$2"
  if ! grep -Fq "$pattern" "$SCRIPT"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

refute() {
  local pattern="$1"
  local message="$2"
  if grep -Fq "$pattern" "$SCRIPT"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

line_of() {
  local pattern="$1"
  awk -v pattern="$pattern" 'index($0, pattern) { print NR; exit }' "$SCRIPT"
}

require 'APP="build/Togi.app"' "app bundle path must be user-facing Togi.app"
require 'ln -s /Applications "$DMG_STAGE/Applications"' "DMG must include /Applications symlink"
require 'hdiutil create -volname Togi -srcfolder "$DMG_STAGE"' "DMG volume must be named Togi and built from a staged folder"
require 'xcrun notarytool submit "$APP_ZIP"' "app must be notarized before it is copied into the DMG"
require 'xcrun stapler staple "$APP"' "app must be stapled before it is copied into the DMG"
require 'codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"' "DMG must be Developer ID signed before DMG notarization"
require 'xcrun notarytool submit "$DMG"' "DMG must be notarized"
require 'xcrun stapler staple "$DMG"' "DMG must be stapled"

# Resource bundles must live in Contents/Resources ONLY. A nested bundle in Contents/MacOS
# makes `codesign --deep` reject the app, and the runtime no longer needs it there.
refute 'cp -R "$bundle" "$APP/Contents/MacOS/"' "resource bundles must NOT be copied into Contents/MacOS"
require 'cp -R "$bundle" "$APP/Contents/Resources/"' "resource bundles must be copied into Contents/Resources"

# DMG must offer a real drag-to-install layout: a writable image arranged in icon view,
# then converted to a compressed read-only image.
require 'UDRW -ov' "DMG must be staged as a read-write image so a window layout can be saved"
require 'set current view of container window to icon view' "DMG window must use icon view with positioned icons"
require 'hdiutil convert' "read-write DMG must be converted to a compressed distributable DMG"

app_staple_line="$(line_of 'xcrun stapler staple "$APP"')"
dmg_create_call_line="$(line_of '  create_dmg')"
dmg_sign_line="$(line_of 'codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"')"
dmg_notary_line="$(line_of 'xcrun notarytool submit "$DMG"')"

if [ "$app_staple_line" -ge "$dmg_create_call_line" ]; then
  echo "FAIL: app must be stapled before creating the signed-release DMG" >&2
  exit 1
fi

if [ "$dmg_sign_line" -ge "$dmg_notary_line" ]; then
  echo "FAIL: DMG must be signed before notarization" >&2
  exit 1
fi

echo "ok: build-app.sh release packaging checks passed"
