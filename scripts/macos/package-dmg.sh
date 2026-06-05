#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: package-dmg.sh /path/to/Bogi.app}"
OUTPUT_PATH="${2:?Usage: package-dmg.sh /path/to/Bogi.app /path/to/Bogi.dmg}"

hdiutil create \
  -volname "Bogi" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$OUTPUT_PATH"
