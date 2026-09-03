#!/usr/bin/env bash
# STABILIZATION_PLAN §3 Phase 3-A residual axis — DISK-FULL (ENOSPC)
# export, measured for real (not paper-audited).
#
# CA05 row 11 asserted the export catch path handles disk-full with a
# classified message and partial-output removal — but that was a code
# audit, and the cancel row's identical paper claim turned out FALSE when
# STAB-02 finally measured it (pump continuation leak). This gate upgrades
# the disk-full axis to a measured E2E: the harness exports a ProRes file
# (measured ~1.6MB for the 2s fixture) onto a 1MB scratch volume mounted
# from a tiny DMG, so the writer hits ENOSPC MID-FLIGHT.
#
# The contract, judged on three measured facts (the parked-app fake-pass
# lesson from run_e2e_cancel.sh):
#   1. the harness COMPLETED (UITEST_DONE in the result line),
#   2. the export FAILED with a surfaced error (error != none — a silent
#      hang or a crash kills the result line instead),
#   3. no half-written artifact is left CLAIMING to be the export at the
#      destination (a truncated .mov a user could share is UX-REC-01's
#      class; on a full volume the unlink may itself fail, so the gate
#      accepts absence OR a file smaller than the known-complete size).
#
# The DMG is scratch: created, mounted, detached, and deleted by this
# script. Nothing touches the repo or the user's volumes.
#
# Usage: bash scripts/run_diskfull_gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIX="$ROOT/Tests/Fixtures/moving_subject_1440x1080_2s_30fps.mp4,$ROOT/Tests/Fixtures/tone_440hz_2s_mono.wav"
for f in ${FIX//,/ }; do
  [ -s "$f" ] || { echo "missing fixture $f" >&2; exit 1; }
done

echo "Building MovieCutMac (Debug, sandbox OFF)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
APP_BIN="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

# A complete export of this fixture/profile measures 1,680,649 bytes — a
# 1MB volume cannot hold it, so the writer fails mid-flight, not at open.
COMPLETE_SIZE=1680649
DMG="$(mktemp -d /tmp/moviecut-diskfull.XXXXXX)/vol.dmg"
MOUNT="/Volumes/MovieCutENOSPC"
cleanup() {
  hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
  rm -rf "$(dirname "$DMG")"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil create -size 1m -fs "HFS+" -volname MovieCutENOSPC -attach "$DMG" >/dev/null
[ -d "$MOUNT" ] || { echo "scratch volume did not mount" >&2; exit 1; }

WORK="$(dirname "$DMG")"
RESULT="$WORK/result.txt"
echo "Exporting ProRes (~$((COMPLETE_SIZE / 1024))KB) onto a 1MB scratch volume…"
env MOVIECUT_UITEST=1 \
  MOVIECUT_UITEST_IMPORT="$FIX" \
  MOVIECUT_UITEST_EXPORT="$MOUNT/out.mov" \
  MOVIECUT_UITEST_EXPORT_PROFILE="proRes422" \
  MOVIECUT_UITEST_RESULT="$RESULT" \
  MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >"$WORK/app.log" 2>&1 &
PID=$!
( sleep 120; kill "$PID" 2>/dev/null; true ) & WD=$!
for _ in $(seq 1 240); do
  grep -q "UITEST_DONE" "$RESULT" 2>/dev/null && break
  sleep 0.5
done
wait "$PID" 2>/dev/null || true
kill "$WD" 2>/dev/null || true

STATUS="$(tail -1 "$RESULT" 2>/dev/null || true)"
fail=0
if ! grep -q "UITEST_DONE" "$RESULT" 2>/dev/null; then
  echo "  FAIL — app did not complete (parked or crashed): ${STATUS:-<no result line>}" >&2
  cp "$WORK/app.log" "/tmp/moviecut-diskfull-fail-$(date +%H%M%S).log" 2>/dev/null || true
  fail=1
elif grep -q "error=none" "$RESULT" 2>/dev/null; then
  echo "  FAIL — export claimed success on a full volume: $STATUS" >&2
  fail=1
else
  echo "  surfaced failure: $STATUS"
fi

if [ -e "$MOUNT/out.mov" ]; then
  SIZE="$(stat -f%z "$MOUNT/out.mov")"
  if [ "$SIZE" -lt "$COMPLETE_SIZE" ]; then
    echo "  truncated artifact removed-or-incomplete at destination: $SIZE bytes < complete $COMPLETE_SIZE (partial not shareable as the export)"
  else
    echo "  FAIL — a complete-sized artifact survived on the full volume: $SIZE bytes" >&2
    fail=1
  fi
else
  echo "  destination clean: no artifact at the destination"
fi

if grep -q "CONTINUATION MISUSE" "$WORK/app.log" 2>/dev/null; then
  echo "  FAIL — pump continuation leak under ENOSPC (the cancel-park class)" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "DISK-FULL EXPORT GATE PASS"
else
  echo "DISK-FULL EXPORT GATE FAIL" >&2
fi
exit "$fail"
