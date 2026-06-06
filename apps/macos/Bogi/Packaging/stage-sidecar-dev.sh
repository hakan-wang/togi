#!/usr/bin/env bash
# Stage the Node sidecar into the SwiftPM bin dir for local `swift build` dev runs.
#
# The Bogi binary loads its sidecar from Bundle.main.resourceURL/sidecar — which, for a
# raw debug binary, is the SwiftPM bin dir itself. But `swift build` never assembles the
# sidecar; only Packaging/build-app.sh does, and only into a packaged .app. Without this
# step the sidecar can't launch ("The file node doesn't exist") and every chat message
# hangs on "togi is thinking…". Run this once after `swift build` (re-run after sidecar
# source changes).
#
#   Packaging/stage-sidecar-dev.sh [debug|release]   (default: debug)
set -euo pipefail
cd "$(dirname "$0")/.."          # apps/macos/Bogi

CONFIG="${1:-debug}"
NODE_VERSION="v22.11.0"
NODE_PKG="node-${NODE_VERSION}-darwin-arm64"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
SIDECAR_DST="$BIN_DIR/sidecar"

echo "== build sidecar (esbuild -> dist/main.cjs) =="
( cd sidecar && npm ci && npm run build )

echo "== stage into $SIDECAR_DST =="
mkdir -p "$SIDECAR_DST"
cp sidecar/dist/main.cjs "$SIDECAR_DST/main.cjs"
rm -rf "$SIDECAR_DST/node_modules"
cp -R sidecar/node_modules "$SIDECAR_DST/node_modules"

echo "== embed Node runtime ($NODE_VERSION) =="
if [ ! -x "$SIDECAR_DST/node" ]; then
  if [ ! -x "/tmp/${NODE_PKG}/bin/node" ]; then
    curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_PKG}.tar.gz" -o "/tmp/${NODE_PKG}.tar.gz"
    tar xzf "/tmp/${NODE_PKG}.tar.gz" -C /tmp
  fi
  cp "/tmp/${NODE_PKG}/bin/node" "$SIDECAR_DST/node"
fi

echo "done: staged sidecar -> $SIDECAR_DST"
