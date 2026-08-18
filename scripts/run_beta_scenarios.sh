#!/usr/bin/env bash
# Automated beta-scenario pre-flight (review §8).
#
# Before handing the app to human beta testers, this script runs the beta
# "happy path" — the core job a tester is asked to do — headlessly and measures
# each step's wall-clock + success. It is NOT the beta itself (usability,
# willingness-to-pay, etc. are human metrics captured in docs/BETA_GUIDE.md).
# Its job is to guarantee the beta tasks actually complete on the current build,
# so a tester is never blocked by a regression we could have caught.
#
# Beta steps covered (automatable subset):
#   1. Import → first cut → export            (the core "finish a clip" job)
#   2. Color correction → export              (the differentiator axis)
#   3. Portrait/platform-preset export        (9:16, the social format)
#   4. Autosave save + reload recovery        (durability)
#
# Each step is a separate app launch with wall-clock timing + ffprobe metadata
# validation. One step failing exits 1 (the beta is NOT ready to ship).
#
# Usage: bash scripts/run_beta_scenarios.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

FIXTURE="$ROOT/Tests/Fixtures/bars_320x240_3s_30fps.mp4"
[ -s "$FIXTURE" ] || { echo "missing fixture; run scripts/make_fixtures.sh" >&2; exit 1; }

echo "Building MovieCutMac (Debug)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null

PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found at $APP_BIN" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

# wait_for_export <pid> <iters> <sleep_s> <out_file>: poll until the artifact
# appears or the watchdog fires. Reuses the proven e2e pattern.
wait_for_export() {
  local pid="$1" iters="$2" sleep_s="$3" out="$4"
  for _ in $(seq 1 "$iters"); do
    [ -s "$out" ] && return 0
    sleep "$sleep_s"
  done
  return 1
}

# run_step <step_name> <out_file> <extra env...>: launches the harness, times
# the run, validates the artifact with ffprobe. Appends a result row.
BETA_FAIL=0
run_step() {
  local name="$1" out="$2"; shift 2
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 2
  rm -f "$out"
  local start; start="$(python3 -c 'import time; print(time.time())')"
  env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" \
    MOVIECUT_UITEST_EXPORT="$out" MOVIECUT_UITEST_QUIT=1 \
    "$@" "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!
  if wait_for_export "$pid" 480 0.5 "$out"; then
    wait "$pid" 2>/dev/null || true
    local end; end="$(python3 -c 'import time; print(time.time())')"
    local secs; secs="$(python3 -c "print(round($end-$start,2))")"
    local dur; dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" 2>/dev/null || echo '?')"
    local dim; dim="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$out" 2>/dev/null || echo '?')"
    printf "  %-32s %7ss   PASS   dur=%ss  %s\n" "$name" "$secs" "$dur" "$dim"
    echo "$secs" > "$WORK/${name}.secs"
  else
    wait "$pid" 2>/dev/null || true
    printf "  %-32s    —      FAIL   (no artifact / crashed)\n" "$name"
    BETA_FAIL=1
  fi
}

echo "" && echo "=== beta scenarios (pre-flight: do the beta tasks complete on this build?) ==="
run_step "1_first_cut_import_export"      "$WORK/first_cut.mp4"
run_step "2_color_correction_export"      "$WORK/color.mp4"     MOVIECUT_UITEST_COLOR=1
run_step "3_portrait_9x16_export"         "$WORK/portrait.mp4"  MOVIECUT_UITEST_PLATFORM_PRESET=tikTok

# Step 4: autosave durability. Drive the recovery harness path (write autosave,
# then re-read it in the same process — the established recovery-gate pattern).
RECOVERY_RESULT="$WORK/recovery.txt"
rm -f "$RECOVERY_RESULT"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  MOVIECUT_UITEST_RECOVERY=1 MOVIECUT_UITEST_RECOVERY_RESPONSE=recover \
  MOVIECUT_UITEST_RESULT="$RECOVERY_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
RP=$!
for _ in $(seq 1 480); do [ -s "$RECOVERY_RESULT" ] && break; sleep 0.5; done
wait "$RP" 2>/dev/null || true
RECOVERY_STATUS="$(cat "$RECOVERY_RESULT" 2>/dev/null || echo MISSING)"
# Assert the harness's recovery contract (the same one
# run_recovery_gate.sh locks): the recovery_done line with an autosave
# present, at least one recovered clip, and the adoption status. The old
# `status=PASS` grep matched a string the harness never emits — scenario 4
# could not pass as written.
RECOVERY_AUTOSAVE="$(echo "$RECOVERY_STATUS" | grep -oE 'autosave_present=[01]' | cut -d= -f2)"
RECOVERY_CLIPS="$(echo "$RECOVERY_STATUS" | grep -oE 'recovered_clips=[0-9]+' | cut -d= -f2)"
if echo "$RECOVERY_STATUS" | grep -q "recovery_done" \
   && [ "${RECOVERY_AUTOSAVE:-0}" = "1" ] \
   && [ "${RECOVERY_CLIPS:-0}" -ge 1 ] \
   && echo "$RECOVERY_STATUS" | grep -q "Recovered unsaved work"; then
  printf "  %-32s    —      PASS   recovery=%s\n" "4_autosave_save_reload" "recovered_clips=${RECOVERY_CLIPS}"
else
  printf "  %-32s    —      FAIL   recovery=%s\n" "4_autosave_save_reload" "$RECOVERY_STATUS"
  BETA_FAIL=1
fi

echo ""
if [ "$BETA_FAIL" -ne 0 ]; then
  echo "=> BETA PRE-FLIGHT FAILED — a beta task does not complete on this build; fix before handing to testers." >&2
  exit 1
fi
echo "=> BETA PRE-FLIGHT PASSED — the beta happy path completes on this build."
echo "   (Usability/willingness-to-pay are human metrics — see docs/BETA_GUIDE.md.)"
