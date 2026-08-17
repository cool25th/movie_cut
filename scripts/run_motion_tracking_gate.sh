#!/bin/bash
# Motion-tracking harness gate (T2-R1 prerequisite) — end-to-end driver.
#
# Runs the real app through the real tracking command path
# (MOVIECUT_UITEST_MOTION_TRACKING=1: trackMotion → MotionTrackingProvider →
# SetClipPropertyCommand(.keyframes)) on the deterministic moving-subject
# fixture, then asserts the harness status reports the keyframes landed on
# the clip model AND survived a ProjectStore save/load round-trip.
#
# Determinism controls (validation doc §4.5): fixture bytes are hash-verified
# before launch; the initial rect / time range / sampling policy are fixed in
# the app-side scenario; the JSON behavior dump is written for comparison.
#
# IoU-vs-ground-truth of the provider itself lives in
# Tests/MovieCutCoreTests/MotionTrackingProviderTests.swift; this script
# proves the COMMAND path end to end.
#
# Usage: bash scripts/run_motion_tracking_gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXTURE="$ROOT/Tests/Fixtures/moving_subject_320x240_2s_30fps.mp4"
EXPECTED_SHA256="b7a9cb2e4209256ad43b3fbe7e704af447bdc6ca9e5224d988b4a0ce28fc2a63"

# --- 0. Fixture integrity (deterministic input bytes) ----------------------
if [[ ! -s "$FIXTURE" ]]; then
  echo "missing fixture; run scripts/make_fixtures.sh" >&2
  exit 1
fi
actual_sha="$(shasum -a 256 "$FIXTURE" | awk '{print $1}')"
if [[ "$actual_sha" != "$EXPECTED_SHA256" ]]; then
  echo "fixture hash mismatch: expected=$EXPECTED_SHA256 actual=$actual_sha" >&2
  exit 1
fi

# --- 1. Build (sandbox OFF, same rationale as run_e2e_export.sh) -----------
echo "Building MovieCutMac (Debug, sandbox OFF)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' \
  ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO \
  build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' \
  ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
APP="$PRODUCTS_DIR/MovieCutMac.app"
[[ -d "$APP" ]] || { echo "app not found at $APP" >&2; exit 1; }

# --- 2. Run the gate --------------------------------------------------------
WORK_DIR="$(mktemp -d /tmp/moviecut-motion-tracking.XXXXXX)"
RESULT="$WORK_DIR/result.txt"
DUMP="$WORK_DIR/motion_tracking_dump.json"

echo "Launching motion-tracking gate…"
open -n -W \
  --env MOVIECUT_UITEST=1 \
  --env MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  --env MOVIECUT_UITEST_MOTION_TRACKING=1 \
  --env MOVIECUT_UITEST_MOTION_TRACKING_DUMP="$DUMP" \
  --env MOVIECUT_UITEST_RESULT="$RESULT" \
  --env MOVIECUT_UITEST_QUIT=1 \
  "$APP" &
OPEN_PID=$!

# Watchdog: tracking ~60 Vision frames on a 320x240 fixture takes seconds;
# 180s covers cold starts. On timeout, kill the open waiter and the app.
( sleep 180; kill "$OPEN_PID" >/dev/null 2>&1; pkill -f "$APP/Contents/MacOS/MovieCutMac" >/dev/null 2>&1; true ) &
WATCHDOG_PID=$!

set +e
wait "$OPEN_PID"
OPEN_RC=$?
set -e
kill "$WATCHDOG_PID" >/dev/null 2>&1 || true
# Reap the watchdog so bash doesn't print a job-control "Terminated" notice.
wait "$WATCHDOG_PID" 2>/dev/null || true

# --- 3. Assert --------------------------------------------------------------
if [[ ! -s "$RESULT" ]]; then
  echo "FAIL: no harness result written (watchdog timeout? see $WORK_DIR)" >&2
  exit 1
fi
STATUS="$(cat "$RESULT")"
echo "status: $STATUS"

fail=0
if [[ "$OPEN_RC" -ne 0 ]]; then
  echo "FAIL: open exited with $OPEN_RC" >&2
  fail=1
fi
if ! grep -q "motion_tracking=ok" <<<"$STATUS"; then
  echo "FAIL: motion_tracking=ok missing from status" >&2
  fail=1
fi
if ! grep -q "error=none" <<<"$STATUS"; then
  echo "FAIL: error=none missing from status" >&2
  fail=1
fi
if [[ -s "$DUMP" ]]; then
  echo "behavior dump: $DUMP"
  # Sanity-print the key counters for the run log.
  /usr/bin/python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print("dump: samples=%d keyframes=%d roundtrip=%d midX %.3f→%.3f elapsed=%.2fs" % (
    d["sampleCount"], d["generatedKeyframes"], d["roundTripKeyframeCount"],
    d["firstResultMidX"], d["lastResultMidX"], d["elapsedSeconds"]))
' "$DUMP" 2>/dev/null || true
else
  echo "FAIL: behavior dump missing: $DUMP" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "MOTION TRACKING GATE FAIL (artifacts preserved in $WORK_DIR)" >&2
  exit 1
fi

rm -rf "$WORK_DIR"
echo "MOTION TRACKING GATE PASS"
