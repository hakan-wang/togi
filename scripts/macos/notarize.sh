#!/usr/bin/env bash
#
# notarize.sh — submit a signed Bogi.app to the Apple notary service and staple.
#
# Zips the (already Developer ID-signed, hardened-runtime) .app, submits it to
# Apple's notary service with `notarytool`, waits for the result, and staples the
# ticket to the app so it validates offline.
#
# Credentials are read from the environment only — never hardcoded. Two auth
# methods are supported (checked in this order):
#
#   A) Keychain notary profile (recommended):
#        AC_NOTARY_PROFILE   Name of a profile stored via
#                            `xcrun notarytool store-credentials`.
#
#   B) App Store Connect API key:
#        AC_API_KEY_ID       Key ID (the "-d" value).
#        AC_API_ISSUER_ID    Issuer UUID.
#        AC_API_KEY_PATH     Path to the .p8 private key file.
#
#   C) Apple ID + app-specific password:
#        AC_APPLE_ID         Apple ID email.
#        AC_PASSWORD         App-specific password (NOT your Apple ID password).
#        AC_TEAM_ID          Developer Team ID.
#
# Usage:
#   scripts/macos/notarize.sh <path-to-.app>
#   AC_NOTARY_PROFILE=bogi scripts/macos/notarize.sh build/Bogi.app
#
set -euo pipefail

APP_PATH="${1:-${APP_PATH:-}}"

die() { echo "error: $*" >&2; exit 1; }

[ -n "$APP_PATH" ] || die "no app bundle given (arg 1 or APP_PATH)"
[ -d "$APP_PATH" ] || die "app bundle not found: $APP_PATH"
command -v xcrun >/dev/null 2>&1  || die "xcrun not found (run on macOS)"
command -v ditto >/dev/null 2>&1  || die "ditto not found (run on macOS)"

# Assemble notarytool auth args from whichever credentials are present.
auth_args=()
if [ -n "${AC_NOTARY_PROFILE:-}" ]; then
    echo "Auth: keychain notary profile ($AC_NOTARY_PROFILE)"
    auth_args=(--keychain-profile "$AC_NOTARY_PROFILE")
elif [ -n "${AC_API_KEY_ID:-}" ] && [ -n "${AC_API_ISSUER_ID:-}" ] && [ -n "${AC_API_KEY_PATH:-}" ]; then
    echo "Auth: App Store Connect API key ($AC_API_KEY_ID)"
    [ -f "$AC_API_KEY_PATH" ] || die "API key file not found: $AC_API_KEY_PATH"
    auth_args=(--key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID")
elif [ -n "${AC_APPLE_ID:-}" ] && [ -n "${AC_PASSWORD:-}" ] && [ -n "${AC_TEAM_ID:-}" ]; then
    echo "Auth: Apple ID app-specific password ($AC_APPLE_ID)"
    auth_args=(--apple-id "$AC_APPLE_ID" --password "$AC_PASSWORD" --team-id "$AC_TEAM_ID")
else
    die "no notary credentials in environment (set AC_NOTARY_PROFILE, or AC_API_* , or AC_APPLE_ID/AC_PASSWORD/AC_TEAM_ID)"
fi

ZIP_PATH="${APP_PATH%.app}.zip"

echo "==> Zipping app for submission…"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting to the notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP_PATH" "${auth_args[@]}" --wait

echo "==> Stapling the notarization ticket…"
xcrun stapler staple "$APP_PATH"

echo "==> Validating staple…"
xcrun stapler validate "$APP_PATH"

rm -f "$ZIP_PATH"
echo "Notarized and stapled: $APP_PATH"
