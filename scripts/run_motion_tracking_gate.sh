#!/bin/bash
# Motion-tracking harness gate (T2-R1 prerequisite) — end-to-end driver.
#
# Phase 1: runs the real app through the real tracking command path
# (MOVIECUT_UITEST_MOTION_TRACKING=1: trackMotion → MotionTrackingProvider →
# SetClipPropertyCommand(.keyframes)) on the deterministic moving-subject
# fixture, verifies the keyframes landed on the clip model and survived a
# ProjectStore save/load round-trip, then SAVES the project through the real
# manual-save path.
#
# Phase 2: relaunches a FRESH app process with MOVIECUT_BOOTSTRAP_PROJECT →
# openProject (the real reopen path) and verifies the tracked position
# keyframes survived the save → reopen boundary in the same count.
#
# Determinism controls (validation doc §4.5): fixture bytes are hash-verified
# before launch; the initial rect / time range / sampling policy are fixed in
# the app-side scenario; the JSON behavior dump is written for comparison.
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
WATCHDOG_SECONDS=180

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

WORK_DIR="$(mktemp -d /tmp/moviecut-motion-tracking.XXXXXX)"
RESULT="$WORK_DIR/result-phase1.txt"
DUMP="$WORK_DIR/motion_tracking_dump.json"
SAVED_PROJECT="$WORK_DIR/tracked.moviecut"

# run_harness <result_path> <extra --env args...>
# Launches the harness app and waits (with watchdog) for it to quit.
run_harness() {
  local result_path="$1"; shift
  open -n -W \
    --env MOVIECUT_UITEST=1 \
    --env MOVIECUT_UITEST_RESULT="$result_path" \
    --env MOVIECUT_UITEST_QUIT=1 \
    "$@" \
    "$APP" &
  OPEN_PID=$!
  ( sleep "$WATCHDOG_SECONDS"; kill "$OPEN_PID" >/dev/null 2>&1; \
    pkill -f "$APP/Contents/MacOS/MovieCutMac" >/dev/null 2>&1; true ) &
  WATCHDOG_PID=$!
  set +e
  wait "$OPEN_PID"
  OPEN_RC=$?
  set -e
  kill "$WATCHDOG_PID" >/dev/null 2>&1 || true
  # Reap the watchdog so bash doesn't print a job-control "Terminated" notice.
  wait "$WATCHDOG_PID" 2>/dev/null || true
  return $OPEN_RC
}

fail=0

# --- 2. Phase 1: track + apply + round-trip + manual save -------------------
echo "Phase 1: motion tracking (track → keyframes → round-trip → save)…"
run_harness "$RESULT" \
  --env MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  --env MOVIECUT_UITEST_MOTION_TRACKING=1 \
  --env MOVIECUT_UITEST_MOTION_TRACKING_DUMP="$DUMP" \
  --env MOVIECUT_UITEST_MOTION_TRACKING_SAVE="$SAVED_PROJECT" || fail=1

if [[ ! -s "$RESULT" ]]; then
  echo "FAIL: no phase-1 result written (watchdog timeout? see $WORK_DIR)" >&2
  exit 1
fi
STATUS1="$(cat "$RESULT")"
echo "phase1: $STATUS1"

if ! grep -q "motion_tracking=ok" <<<"$STATUS1"; then
  echo "FAIL: motion_tracking=ok missing from phase-1 status" >&2
  fail=1
fi
if ! grep -q "saved=1" <<<"$STATUS1"; then
  echo "FAIL: saved=1 missing from phase-1 status (manual save failed?)" >&2
  fail=1
fi
if ! grep -q "error=none" <<<"$STATUS1"; then
  echo "FAIL: error=none missing from phase-1 status" >&2
  fail=1
fi
if [[ -s "$DUMP" ]]; then
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
if [[ ! -s "$SAVED_PROJECT" ]]; then
  echo "FAIL: saved project file missing: $SAVED_PROJECT" >&2
  fail=1
fi
[[ "$fail" -eq 0 ]] || { echo "MOTION TRACKING GATE FAIL (artifacts preserved in $WORK_DIR)" >&2; exit 1; }

# --- 3. Phase 2: fresh process reopen ---------------------------------------
PHASE1_KEYFRAMES="$(/usr/bin/python3 -c '
import json,sys
print(json.load(open(sys.argv[1]))["generatedKeyframes"])
' "$DUMP" 2>/dev/null || echo 0)"
RESULT2="$WORK_DIR/result-phase2.txt"

echo "Phase 2: reopen in a fresh process (bootstrap → verify keyframes)…"
run_harness "$RESULT2" \
  --env MOVIECUT_BOOTSTRAP_PROJECT="$SAVED_PROJECT" \
  --env MOVIECUT_UITEST_MOTION_TRACKING_REOPEN=1 || fail=1

if [[ ! -s "$RESULT2" ]]; then
  echo "FAIL: no phase-2 result written (watchdog timeout? see $WORK_DIR)" >&2
  exit 1
fi
STATUS2="$(cat "$RESULT2")"
echo "phase2: $STATUS2"

if ! grep -q "motion_tracking_reopen=ok" <<<"$STATUS2"; then
  echo "FAIL: motion_tracking_reopen=ok missing from phase-2 status" >&2
  fail=1
fi
if ! grep -q "error=none" <<<"$STATUS2"; then
  echo "FAIL: error=none missing from phase-2 status" >&2
  fail=1
fi
PHASE2_KEYFRAMES="$(sed -n 's/.*motion_tracking_reopen=ok keyframes=\([0-9]*\).*/\1/p' <<<"$STATUS2")"
if [[ -z "$PHASE2_KEYFRAMES" ]]; then
  PHASE2_KEYFRAMES=0
fi
if [[ "$PHASE2_KEYFRAMES" != "$PHASE1_KEYFRAMES" ]]; then
  echo "FAIL: keyframe count changed across reopen: phase1=$PHASE1_KEYFRAMES phase2=$PHASE2_KEYFRAMES" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "MOTION TRACKING GATE FAIL (artifacts preserved in $WORK_DIR)" >&2
  exit 1
fi

rm -rf "$WORK_DIR"
echo "MOTION TRACKING GATE PASS (reopen: keyframes=$PHASE2_KEYFRAMES preserved)"
