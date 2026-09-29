#!/usr/bin/env bash
# Post-export packaging for the web build:
#   1. copy web/coi-serviceworker.js next to index.html (COOP/COEP shim
#      that unlocks SharedArrayBuffer on GitHub Pages / itch)
#   2. drop version.json + a tiny build badge in index.html so any release
#      is identifiable from the browser
#
# Usage: scripts/pack_web.sh BUILD_DIR VERSION [COMMIT] [BRANCH]
set -euo pipefail

BUILD_DIR="${1:-build/web}"
VERSION="${2:-0.0.0-dev}"
COMMIT="${3:-local}"
BRANCH="${4:-local}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$BUILD_DIR/index.html" ]; then
  echo "ERROR: no web export at $BUILD_DIR/index.html" >&2
  exit 1
fi

cp -f "$ROOT/web/coi-serviceworker.js" "$BUILD_DIR/coi-serviceworker.js"
python3 "$ROOT/scripts/stamp_release.py" "$BUILD_DIR" "$VERSION" "$COMMIT" "$BRANCH"

# Sanity: index.html must reference the shim (head_include from the preset).
if ! grep -q "coi-serviceworker.js" "$BUILD_DIR/index.html"; then
  echo "ERROR: index.html does not include coi-serviceworker.js — preset head_include lost" >&2
  exit 1
fi

echo "packed: $BUILD_DIR (version $VERSION)"
ls -lh "$BUILD_DIR"
