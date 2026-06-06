#!/usr/bin/env bash
#
# package-dmg.sh — build a distributable DMG from a signed Bogi.app.
#
# Stages the .app next to an /Applications symlink (so the DMG window offers the
# familiar drag-to-install layout) and builds a compressed DMG with hdiutil.
# Optionally signs the DMG itself when a signing identity is provided (a signed,
# stapled DMG passes Gatekeeper even before first launch).
#
# Usage:
#   scripts/macos/package-dmg.sh <path-to-.app> <version> [output.dmg]
#
# Environment variables (alternatives / extras):
#   APP_PATH       Path to the signed .app bundle.
#   VERSION        Marketing version string, e.g. 0.1.0 (used in the DMG name).
#   OUTPUT         Output DMG path (defaults to dist/Bogi-<version>.dmg).
#   VOLUME_NAME    Mounted volume name (defaults to "Bogi <version>").
#   SIGN_IDENTITY  Optional Developer ID identity to sign the finished DMG.
#
# Example:
#   scripts/macos/package-dmg.sh build/Bogi.app 0.1.0
#
set -euo pipefail

APP_PATH="${1:-${APP_PATH:-}}"
VERSION="${2:-${VERSION:-}}"
OUTPUT="${3:-${OUTPUT:-}}"

die() { echo "error: $*" >&2; exit 1; }

[ -n "$APP_PATH" ] || die "no app bundle given (arg 1 or APP_PATH)"
[ -d "$APP_PATH" ] || die "app bundle not found: $APP_PATH"
[ -n "$VERSION" ]  || die "no version given (arg 2 or VERSION)"
command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found (run on macOS)"

APP_NAME="$(basename "$APP_PATH")"          # e.g. Bogi.app
VOLUME_NAME="${VOLUME_NAME:-Bogi $VERSION}"
OUTPUT="${OUTPUT:-dist/Bogi-$VERSION.dmg}"

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"

# Stage the bundle + an /Applications shortcut in a temp dir.
STAGING="$(mktemp -d)"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

echo "==> Staging $APP_NAME…"
cp -R "$APP_PATH" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"

echo "==> Building DMG: $OUTPUT (volume: $VOLUME_NAME)…"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$OUTPUT"

# Optionally sign the DMG so Gatekeeper trusts it on first download.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    command -v codesign >/dev/null 2>&1 || die "codesign not found (run on macOS)"
    echo "==> Signing DMG with: $SIGN_IDENTITY"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUTPUT"
    codesign --verify --verbose=2 "$OUTPUT"
fi

echo "DMG ready: $OUTPUT"
