#!/bin/bash
# G-27 ③ physical-device E2E (development plan §3-11) — the SAME two-phase
# harness the simulator gate runs (import → preview → export → audio
# routing → save → reopen), on real hardware via `devicectl`.
#
# Prerequisites (docs/G27_DEVICE_VERIFICATION_GUIDE.md):
#   - a paired, connected, Developer-Mode iPhone (check: xcrun devicectl list devices)
#   - your signing team: pass TEAM_ID=<...> (once, also settable in Xcode)
#
# Usage: TEAM_ID=XXXXXXXXXX bash scripts/run_g27_device_e2e.sh [device_identifier]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.moviecut.ios"
FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
TONE="$ROOT/Tests/Fixtures/tone_440hz_2s_mono.wav"
for f in "$FIXTURE" "$TONE"; do
  [ -s "$f" ] || { echo "missing fixture $f" >&2; exit 1; }
done

# --- 1. Device ---------------------------------------------------------------
if [ $# -ge 1 ]; then
  UDID="$1"
else
  # Extract the Identifier COLUMN by its UUID shape, NOT the last field:
  # newer devicectl output ends rows with the Model column —
  # "iPhone 13 Pro (iPhone14,2)" — so `$NF` grabbed "(iPhone14,2)" and
  # xcodebuild rejected the destination ("unreadable input '2)'").
  UDID="$(xcrun devicectl list devices 2>/dev/null | grep -i available | grep -iE 'iphone|ipad' | head -1 | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}')"
fi
if [ -z "${UDID:-}" ] || [ "$UDID" = "DEVICE" ]; then
  echo "ERROR: no CONNECTED device found." >&2
  echo "Connect + unlock the iPhone (Developer Mode on, trusted), then:" >&2
  echo "  xcrun devicectl list devices   # State must be 'available'" >&2
  echo "  TEAM_ID=<your team> bash scripts/run_g27_device_e2e.sh <identifier>" >&2
  exit 1
fi
echo "Device: $UDID"

# --- 2. Build (signed for the device) ----------------------------------------
if [ -z "${TEAM_ID:-}" ]; then
  echo "ERROR: set TEAM_ID=<your Apple Development team id> (Xcode → Settings → Accounts)." >&2
  exit 1
fi
echo "Building MovieCutiOS (Debug, device-signed)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutiOS -configuration Debug \
  -destination "platform=iOS,id=$UDID" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates \
  build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutiOS -configuration Debug \
  -destination "platform=iOS,id=$UDID" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
APP="$PRODUCTS_DIR/MovieCutiOS.app"
[[ -d "$APP" ]] || { echo "app not found at $APP" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Run scoping ---------------------------------------------------------------
# Every execution gets a unique run ID that BOTH phases share. The harness
# tags each result row `run=<id> …`, and every wait/assert below filters on
# it, so rows left over in g27-result.txt by earlier executions can never
# satisfy this run's waits (a pre-placed file with g27_done/g27_reopen used
# to make a broken run "PASS" instantly).
RUN_ID="g27-$(date +%Y%m%d%H%M%S)-$$-RANDOM$RANDOM"

xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null

# Robust launch: the phone's auto-lock fires during the ~2-minute build
# phase and iOS denies launches with reason "Locked" (runs 6 and 7 died
# this way seconds after a manual unlock). Retry until the launch is
# accepted — the user just needs to keep the screen unlocked.
launch_app() {
  local env_json="${1:-}"
  local deadline=$((SECONDS + 180))
  while true; do
    if [ -n "$env_json" ]; then
      xcrun devicectl device process launch --device "$UDID" --terminate-existing \
        -e "$env_json" "$BUNDLE_ID" >/dev/null 2>&1 && return 0
    else
      xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 && return 0
    fi
    [ $SECONDS -ge $deadline ] && return 1
    echo "…device locked or busy — keep the phone unlocked; retrying" >&2
    sleep 5
  done
}

# --- 3. Create the container (first launch), then stage fixtures -------------
echo "Preparing app container…"
launch_app || { echo "ERROR: could not launch app (device locked >3min?)" >&2; exit 1; }
sleep 3
xcrun devicectl device process terminate --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 1
# Stage fixtures at the EXPLICIT file paths the harness reads
# (Documents/in/fixture.mp4 · Documents/in/tone.wav). The first device
# run failed with "missing staged fixture": the old code's first variant
# copied to destination "Documents/in" WITHOUT a filename, which
# devicectl accepts (creating a file named "in") — so the correct
# fallback variant never ran and the harness found nothing. Explicit
# destinations only; failures are loud, and the staged listing is
# printed so the run log carries the evidence.
stage() {
  xcrun devicectl device copy to --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --destination "$1" --source "$2" >/dev/null \
    || { echo "ERROR: failed to stage $1" >&2; exit 1; }
}
stage "Documents/in/fixture.mp4" "$FIXTURE"
stage "Documents/in/tone.wav" "$TONE"
echo "--- staged in Documents/in ---"
xcrun devicectl device copy from --device "$UDID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --source Documents/in/ --destination "$WORK/" >/dev/null 2>&1 || true
# set -euo pipefail + this pipeline: a missing dir makes ls fail and
# would kill the script SILENTLY right after successful staging (run 4
# exited 1 here with no message). The listing is diagnostic only.
ls -l "$WORK/in" 2>/dev/null | tail -3 || true

pull_result() {
  rm -f "$WORK/g27-result.txt"
  # Destination must be the exact FILE path: a directory destination
  # ("$WORK/") fails silently on this devicectl, and with `|| true`
  # swallowing it the wait loop polled forever while the device already
  # held g27_done (the run-2 hang and run-6 "did not finish" were both
  # this, not app failures — the result file was on device each time).
  xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Documents/g27-result.txt" \
    --destination "$WORK/g27-result.txt" >/dev/null 2>&1 || true
}

# Only THIS run's rows: the harness prefixes every line with `run=$RUN_ID `.
run_result() {
  grep "run=$RUN_ID " "$WORK/g27-result.txt" 2>/dev/null || true
}

wait_for() {
  # WALL-CLOCK budget: a devicectl file copy costs seconds per roundtrip,
  # so an iteration-count loop stretched its nominal 300s timeout to
  # 40+ minutes of real time (the first device run hung this way with
  # the result file already sitting on the device). Poll gently and
  # honor the actual seconds. Waits match ONLY rows tagged with this
  # run's ID — stale rows from previous executions never satisfy them.
  local pattern="$1" timeout="${2:-300}"
  local deadline=$((SECONDS + timeout))
  while [ $SECONDS -lt $deadline ]; do
    pull_result
    run_result | grep -q "$pattern" && return 0
    sleep 2
  done
  return 1
}

ENV_JSON_PHASE1="{\"MOVIECUT_UITEST\":\"1\",\"MOVIECUT_G27_RUN_ID\":\"$RUN_ID\"}"
ENV_JSON_PHASE2="{\"MOVIECUT_UITEST\":\"1\",\"MOVIECUT_UITEST_REOPEN\":\"1\",\"MOVIECUT_G27_RUN_ID\":\"$RUN_ID\"}"

# --- 4. Phase 1 ---------------------------------------------------------------
# Reset the on-device result file BEFORE phase 1 so past executions' rows
# cannot bleed into this run's log (belt-and-suspenders on top of the
# run-ID scoping above): stage an empty file over Documents/g27-result.txt.
echo "Run ID: $RUN_ID"
echo "Resetting on-device g27-result.txt…"
: > "$WORK/g27-result-reset.txt"
xcrun devicectl device copy to --device "$UDID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --destination "Documents/g27-result.txt" \
  --source "$WORK/g27-result-reset.txt" >/dev/null \
  || { echo "ERROR: could not reset g27-result.txt on device" >&2; exit 1; }

echo "Phase 1: import → preview → export → audio routing → save…"
launch_app "$ENV_JSON_PHASE1" \
  || { echo "ERROR: could not launch app for phase 1 (device locked >3min?)" >&2; exit 1; }
if ! wait_for "g27_done"; then
  echo "FAIL: phase 1 did not finish (run $RUN_ID)" >&2
  cat "$WORK/g27-result.txt" 2>/dev/null >&2
  exit 1
fi
xcrun devicectl device process terminate --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "--- phase 1 result (run $RUN_ID) ---"
run_result

# --- 5. Phase 2 (fresh process: reopen) ---------------------------------------
# Same run ID as phase 1; the harness APPENDS to the reset file, so the
# run-scoped view below carries exactly phase 1 + phase 2 of THIS execution.
echo "Phase 2: reopen…"
launch_app "$ENV_JSON_PHASE2" \
  || { echo "ERROR: could not launch app for phase 2 (device locked >3min?)" >&2; exit 1; }
if ! wait_for "g27_reopen"; then
  echo "FAIL: phase 2 did not finish (run $RUN_ID)" >&2
  cat "$WORK/g27-result.txt" 2>/dev/null >&2
  exit 1
fi
xcrun devicectl device process terminate --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "--- phase 2 result (run $RUN_ID) ---"
run_result | tail -3

# --- 6. Assertions (same contract as the simulator gate, run-scoped) ----------
fail=0
assert_line() {
  run_result | grep -qE "$1" || { echo "FAIL: missing $1 (run $RUN_ID)" >&2; fail=1; }
}
assert_line "g27_import imported_clips=[1-9]"
assert_line "g27_preview playable=1 duration=[0-9]+\\.[0-9]+ frame=1"
assert_line "g27_export file=.+ bytes=[1-9][0-9]*"
assert_line "g27_audio category=AVAudioSessionCategoryPlayback route=.+"
assert_line "g27_save saved=1"
assert_line "g27_reopen reopened_clips=[1-9]"
# error=none is counted ONLY within this run's rows: older executions'
# clean finishes must not mask this run's errors (nor its errors mask
# the expected count of exactly 2 clean g27_done rows: phase 1 + phase 2).
[ "$(run_result | grep -c "error=none")" -eq 2 ] \
  || { echo "FAIL: expected 2 clean g27_done rows in run $RUN_ID" >&2; fail=1; }

if [ "$fail" -ne 0 ]; then
  echo "G-27 DEVICE E2E FAIL ($UDID, run $RUN_ID)" >&2
  exit 1
fi
echo "G-27 DEVICE E2E PASS ($UDID, run $RUN_ID)"
