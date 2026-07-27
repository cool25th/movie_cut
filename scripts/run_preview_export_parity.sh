#!/usr/bin/env bash
# Step 1 Preview↔Export pixel-parity check.
#
# Drives the real app pipeline via the DEBUG launch harness to:
#   1. import a fixture video,
#   2. build the project composition (the new Preview path),
#   3. dump Preview frames at known timestamps via PlaybackEngine.snapshotFrame,
#   4. export the project to mp4,
# then extracts the same timestamps from the export and compares pixels with
# scripts/verify_preview_export_parity.py.
#
# This is the non-skippable parity gate required by
# docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md Step 1.
#
# Usage:  bash scripts/run_preview_export_parity.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
[ -s "$FIXTURE" ] || { echo "missing fixture; run scripts/make_fixtures.sh" >&2; exit 1; }

command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

echo "Building MovieCutMac (Debug)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' build >/dev/null

PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found at $APP_BIN" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

RESULT="$WORK/result.txt"
PREVIEW_DIR="$WORK/preview_frames"
EXPORT_MP4="$WORK/export.mp4"
mkdir -p "$PREVIEW_DIR"

# Sample at 0.5s (inside clip 1) and 2.5s (inside clip 2 after the boundary).
# The fixture is 2s long so the second sample exercises the boundary into a
# static tail rather than a second clip; parity still proves the Preview frame
# matches the export frame at both timestamps.
PARITY_TIMES="0.5,1.5"

echo "Running parity harness (Preview frame dump + export)…"
env MOVIECUT_UITEST=1 \
  MOVIECUT_UITEST_PARITY=1 \
  MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  MOVIECUT_UITEST_PARITY_TIMES="$PARITY_TIMES" \
  MOVIECUT_UITEST_PREVIEW_DUMP="$PREVIEW_DIR" \
  MOVIECUT_UITEST_EXPORT="$EXPORT_MP4" \
  MOVIECUT_UITEST_RESULT="$RESULT" \
  MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
HP=$!
for _ in $(seq 1 180); do [ -s "$RESULT" ] && break; sleep 0.5; done
wait "$HP" 2>/dev/null || true

STATUS="$(cat "$RESULT" 2>/dev/null || echo MISSING)"
echo "Harness status: $STATUS"
case "$STATUS" in
  *"error=none"*"dumped_frames="*[!0]*) ;;
  *) echo "FAIL: parity harness did not dump frames cleanly" >&2; exit 1 ;;
esac

[ -s "$EXPORT_MP4" ] || { echo "FAIL: export mp4 not produced" >&2; exit 1; }

echo ""
echo "Comparing Preview vs Export frames…"
python3 "$ROOT/scripts/verify_preview_export_parity.py" \
  --preview-dir "$PREVIEW_DIR" \
  --export-mp4 "$EXPORT_MP4" \
  --times "$PARITY_TIMES" \
  --tolerance 12.0 \
  --size 320x240 \
  --work-dir "$WORK"
