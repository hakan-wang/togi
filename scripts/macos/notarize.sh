#!/usr/bin/env bash
set -euo pipefail

DMG_PATH="${1:?Usage: notarize.sh /path/to/Bogi.dmg}"

xcrun notarytool submit "$DMG_PATH" \
  --apple-id "${APPLE_ID:?APPLE_ID is required}" \
  --team-id "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}" \
  --password "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required}" \
  --wait

xcrun stapler staple "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
