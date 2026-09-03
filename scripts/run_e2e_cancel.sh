#!/usr/bin/env bash
# STAB-02 cancel E2E (the ledger's remaining leg): cancel a REAL
# explicit-bitrate (ProRes) export mid-flight through the app harness and
# assert the writer-path cancellation contract on measured evidence:
#   1. the harness reports the export FAILED (a cancelled export must not
#      half-succeed),
#   2. the destination file is ABSENT (the catch path deleted the partial),
#   3. the sanity leg — the same fixture/export WITHOUT the cancel knob —
#      completes, so the cancellation leg is meaningful (not dying before
#      the pumps for an unrelated reason).
#
# Usage: bash scripts/run_e2e_cancel.sh
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

WORK="$(mktemp -d /tmp/moviecut-cancel.XXXXXX)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT
pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 1

run_leg() {
  local leg="$1"; local extra_env="$2"; local out="$WORK/${leg}.mov" result="$WORK/${leg}.txt"
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_IMPORT="$FIX" \
    MOVIECUT_UITEST_EXPORT="$out" \
    MOVIECUT_UITEST_EXPORT_PROFILE="proRes422" \
    $extra_env \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >"$WORK/${leg}.app.log" 2>&1 &
  local pid=$!
  ( sleep 120; kill "$pid" 2>/dev/null; true ) & local wd=$!
  for _ in $(seq 1 240); do
    grep -q "UITEST_DONE" "$result" 2>/dev/null && break
    sleep 0.5
  done
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true
  echo "$out"
}

fail=0

echo "Leg 1: sanity — the same export WITHOUT cancel completes"
SANITY_OUT="$(run_leg sanity "")"
if [ -s "$SANITY_OUT" ] && grep -q "error=none" "$WORK/sanity.txt"; then
  echo "  sanity: PASS ($(stat -f%z "$SANITY_OUT") bytes)"
else
  echo "  sanity: FAIL — no export or harness error: $(tail -1 "$WORK/sanity.txt" 2>/dev/null)" >&2
  fail=1
fi

echo "Leg 2: cancel mid-flight (repeated firing from 200ms — a single early"
echo "shot lands in the audio-graph phase BEFORE writer registration and is"
echo "a measured no-op)"
CANCEL_OUT="$(run_leg cancel "MOVIECUT_UITEST_EXPORT_CANCEL_MS=200")"
# The contract is THREE measured facts: the harness COMPLETED (UITEST_DONE —
# a parked/killed app trivially leaves no file and would fake-pass this
# gate: measured 2026-09-03, the pre-fix cancel parked both pumps and the
# watchdog SIGTERM'd the process), the export FAILED (a cancelled export
# must not report error=none), and the destination is ABSENT (the catch
# path deleted the partial).
CANCEL_STATUS="$(tail -1 "$WORK/cancel.txt" 2>/dev/null || true)"
if [ ! -e "$CANCEL_OUT" ] \
   && grep -q "UITEST_DONE" "$WORK/cancel.txt" 2>/dev/null \
   && ! grep -q "error=none" "$WORK/cancel.txt" 2>/dev/null; then
  echo "  cancel: PASS — export failed, no partial output: $CANCEL_STATUS"
else
  echo "  cancel: FAIL — file: $([ -e "$CANCEL_OUT" ] && stat -f%z "$CANCEL_OUT" || echo absent), status: ${CANCEL_STATUS:-<none — app parked/killed before reporting>}" >&2
  # Evidence preservation: keep the failed leg's artifacts (result line,
  # app log) for diagnosis instead of letting the trap wipe them.
  KEEP="/tmp/moviecut-cancel-fail-$(date +%H%M%S)"
  cp -r "$WORK" "$KEEP" 2>/dev/null || true
  echo "  evidence kept at: $KEEP" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "STAB-02 CANCEL E2E PASS"
else
  echo "STAB-02 CANCEL E2E FAIL" >&2
fi
exit "$fail"
