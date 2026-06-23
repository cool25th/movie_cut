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

# Kill any lingering harness instance so sequential launches don't interfere.
pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true
sleep 1

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

# Freeze frame must be reflected in export: a 2s freeze grows the output by ~2s.
FREEZE_OUT="$(mktemp -d)/freeze.mp4"
MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" MOVIECUT_UITEST_FREEZE=1 \
  MOVIECUT_UITEST_EXPORT="$FREEZE_OUT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
FP=$!
for _ in $(seq 1 120); do [ -s "$FREEZE_OUT" ] && break; sleep 0.5; done
wait "$FP" 2>/dev/null || true
FREEZE_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FREEZE_OUT" 2>/dev/null || echo 0)"
echo "PASS: freeze export duration ${FREEZE_DURATION}s (baseline ${DURATION}s)"
awk -v base="$DURATION" -v frz="$FREEZE_DURATION" 'BEGIN { d = frz - base; exit !(d > 1.7 && d < 2.3) }' \
  || { echo "FAIL: freeze not reflected in export (delta $(awk -v b="$DURATION" -v f="$FREEZE_DURATION" 'BEGIN{printf "%.2f", f-b}')s, expected ~2.0)" >&2; rm -rf "$(dirname "$FREEZE_OUT")"; exit 1; }
rm -rf "$(dirname "$FREEZE_OUT")"

# Noise reduction must run the real AVAudioEngine DSP in the app context without
# crashing (the offline-render path aborts under `swift test`).
TONE="$ROOT/Tests/Fixtures/tone_440hz_2s_mono.wav"
NR_RESULT="$(mktemp -d)/nr.txt"
MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$TONE" MOVIECUT_UITEST_DENOISE=1 \
  MOVIECUT_UITEST_RESULT="$NR_RESULT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
NP=$!
for _ in $(seq 1 120); do [ -s "$NR_RESULT" ] && break; sleep 0.5; done
wait "$NP" 2>/dev/null || true
NR_STATUS="$(cat "$NR_RESULT" 2>/dev/null || echo MISSING)"
rm -rf "$(dirname "$NR_RESULT")"
case "$NR_STATUS" in
  *"error=none"*) echo "PASS: noise reduction ran in app context ($NR_STATUS)" ;;
  *) echo "FAIL: noise reduction did not complete cleanly (status: $NR_STATUS)" >&2; exit 1 ;;
esac

# Crash-recovery autosave must be written off the edit path (isolated dir).
AS_DIR="$(mktemp -d)"
env MOVIECUT_UITEST=1 MOVIECUT_AUTOSAVE_DIR="$AS_DIR" MOVIECUT_UITEST_IMPORT="$TONE" \
  MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
AP=$!
for _ in $(seq 1 60); do [ -s "$AS_DIR/recovery.moviecut" ] && break; sleep 0.5; done
wait "$AP" 2>/dev/null || true
if [ -s "$AS_DIR/recovery.moviecut" ]; then
  echo "PASS: crash-recovery autosave written ($(stat -f%z "$AS_DIR/recovery.moviecut") bytes)"
else
  echo "FAIL: no crash-recovery autosave after edit" >&2; rm -rf "$AS_DIR"; exit 1
fi
rm -rf "$AS_DIR"

echo "E2E check OK (import->export + freeze + noise reduction + autosave)"
