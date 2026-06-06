#!/usr/bin/env bash
#
# sign.sh — Developer ID code-signing for Bogi with the Hardened Runtime.
#
# Signs every nested executable / framework / dylib inside the .app bundle
# (inside-out, as codesign requires) and then the outer app bundle itself with
# the hardened-runtime flag, a secure timestamp, and Bogi's entitlements.
#
# Nothing secret is hardcoded: the signing identity is passed as an argument or
# the SIGN_IDENTITY env var. The private key lives only in your login keychain.
#
# Usage:
#   scripts/macos/sign.sh <path-to-.app> [signing-identity]
#
# Environment variables (alternatives to positional args):
#   APP_PATH       Path to the .app bundle to sign.
#   SIGN_IDENTITY  Codesign identity, e.g. "Developer ID Application: Acme (TEAMID)".
#   ENTITLEMENTS   Path to the entitlements plist (defaults to Resources/Bogi.entitlements).
#
# Example:
#   SIGN_IDENTITY="Developer ID Application: Acme Inc (AB12CD34EF)" \
#     scripts/macos/sign.sh build/Bogi.app
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENTITLEMENTS_DEFAULT="$REPO_ROOT/apps/macos/Bogi/Resources/Bogi.entitlements"

APP_PATH="${1:-${APP_PATH:-}}"
SIGN_IDENTITY="${2:-${SIGN_IDENTITY:-}}"
ENTITLEMENTS="${ENTITLEMENTS:-$ENTITLEMENTS_DEFAULT}"

die() { echo "error: $*" >&2; exit 1; }

[ -n "$APP_PATH" ]      || die "no app bundle given (arg 1 or APP_PATH)"
[ -d "$APP_PATH" ]      || die "app bundle not found: $APP_PATH"
[ -n "$SIGN_IDENTITY" ] || die "no signing identity given (arg 2 or SIGN_IDENTITY)"
[ -f "$ENTITLEMENTS" ]  || die "entitlements not found: $ENTITLEMENTS"
command -v codesign >/dev/null 2>&1 || die "codesign not found (run on macOS)"

echo "Signing identity : $SIGN_IDENTITY"
echo "App bundle       : $APP_PATH"
echo "Entitlements     : $ENTITLEMENTS"

# 1) Sign nested code first (frameworks, dylibs, XPC services, helper tools).
#    Deepest paths first so containers are signed after their contents.
echo "==> Signing nested code (frameworks, dylibs, helpers)…"
while IFS= read -r -d '' item; do
    echo "    sign: ${item#"$APP_PATH"/}"
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "$item"
done < <(
    find "$APP_PATH/Contents" \
        \( -name "*.framework" -o -name "*.dylib" -o -name "*.xpc" -o -name "*.app" \) \
        -depth -print0 2>/dev/null || true
)

# 2) Sign the outer app bundle with the hardened runtime + entitlements.
echo "==> Signing app bundle…"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP_PATH"

# 3) Verify.
echo "==> Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Signed and verified: $APP_PATH"
