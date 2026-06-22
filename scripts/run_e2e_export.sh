#!/usr/bin/env bash
# Headless import → timeline → export end-to-end check (Phase 0.1c).
#
# Drives the real app pipeline via the DEBUG launch harness (env vars), without
# needing XCUITest's Accessibility/Automation permission. Asserts a genuine
# movie file is produced with the expected duration. Complements
# App/MovieCutMacUITests (which needs an interactive Accessibility grant).
#
# Usage:  bash scripts/run_e2e_export.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
[ -s "$FIXTURE" ] || { echo "missing fixture; run scripts/make_fixtures.sh" >&2; exit 1; }

echo "Building MovieCutMac (Debug)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' build >/dev/null

PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found at $APP_BIN" >&2; exit 1; }

OUT="$(mktemp -d)/e2e_export.mp4"
echo "Running headless harness → $OUT"
MOVIECUT_UITEST=1 \
  MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  MOVIECUT_UITEST_EXPORT="$OUT" \
  MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!

for _ in $(seq 1 120); do
  [ -s "$OUT" ] && break
  sleep 0.5
done
wait "$APP_PID" 2>/dev/null || true

if [ ! -s "$OUT" ]; then
  echo "FAIL: no export artifact — import or export regressed at runtime" >&2
  exit 1
fi

DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" || echo 0)"
SIZE="$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT")"
echo "PASS: export ${SIZE} bytes, duration ${DURATION}s"

# Duration must be ~2.0s (the fixture length), tolerance 0.2s.
awk -v d="$DURATION" 'BEGIN { exit !(d > 1.8 && d < 2.2) }' \
  || { echo "FAIL: unexpected duration ${DURATION}s (expected ~2.0)" >&2; rm -rf "$(dirname "$OUT")"; exit 1; }

rm -rf "$(dirname "$OUT")"
echo "E2E export check OK"
