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
  UDID="$(xcrun devicectl list devices 2>/dev/null | grep -i available | grep -iE 'iphone|ipad' | head -1 | awk '{print $NF}')"
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

xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null

# --- 3. Create the container (first launch), then stage fixtures -------------
echo "Preparing app container…"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null || true
sleep 3
xcrun devicectl device process terminate --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
sleep 1
xcrun devicectl device copy to --device "$UDID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --destination "Documents/in" --source "$FIXTURE" >/dev/null 2>&1 \
  || xcrun devicectl device copy to --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --destination "Documents/in/fixture.mp4" --source "$FIXTURE" >/dev/null
xcrun devicectl device copy to --device "$UDID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
  --destination "Documents/in/tone.wav" --source "$TONE" >/dev/null

pull_result() {
  rm -f "$WORK/g27-result.txt"
  xcrun devicectl device copy from --device "$UDID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Documents/g27-result.txt" --destination "$WORK/" >/dev/null 2>&1 || true
}

wait_for() {
  local pattern="$1" timeout="${2:-300}"
  for _ in $(seq 1 $((timeout * 2))); do
    pull_result
    grep -q "$pattern" "$WORK/g27-result.txt" 2>/dev/null && return 0
    sleep 0.5
  done
  return 1
}

ENV_JSON_PHASE1='{"MOVIECUT_UITEST":"1"}'
ENV_JSON_PHASE2='{"MOVIECUT_UITEST":"1","MOVIECUT_UITEST_REOPEN":"1"}'

# --- 4. Phase 1 ---------------------------------------------------------------
echo "Phase 1: import → preview → export → audio routing → save…"
xcrun devicectl device process launch --device "$UDID" \
  --terminate-existing -e "$ENV_JSON_PHASE1" "$BUNDLE_ID" >/dev/null
if ! wait_for "g27_done"; then
  echo "FAIL: phase 1 did not finish" >&2
  cat "$WORK/g27-result.txt" 2>/dev/null >&2
  exit 1
fi
xcrun devicectl device process terminate --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "--- phase 1 result ---"
cat "$WORK/g27-result.txt"

# --- 5. Phase 2 (fresh process: reopen) ---------------------------------------
echo "Phase 2: reopen…"
xcrun devicectl device process launch --device "$UDID" \
  --terminate-existing -e "$ENV_JSON_PHASE2" "$BUNDLE_ID" >/dev/null
if ! wait_for "g27_reopen"; then
  echo "FAIL: phase 2 did not finish" >&2
  cat "$WORK/g27-result.txt" 2>/dev/null >&2
  exit 1
fi
xcrun devicectl device process terminate --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "--- phase 2 result ---"
tail -3 "$WORK/g27-result.txt"

# --- 6. Assertions (same contract as the simulator gate) ----------------------
fail=0
assert_line() {
  grep -qE "$1" "$WORK/g27-result.txt" || { echo "FAIL: missing $1" >&2; fail=1; }
}
assert_line "g27_import imported_clips=[1-9]"
assert_line "g27_preview playable=1 duration=[0-9]+\\.[0-9]+ frame=1"
assert_line "g27_export file=.+ bytes=[1-9][0-9]*"
assert_line "g27_audio category=AVAudioSessionCategoryPlayback route=.+"
assert_line "g27_save saved=1"
assert_line "g27_reopen reopened_clips=[1-9]"
[ "$(grep -c "error=none" "$WORK/g27-result.txt")" -eq 2 ] || { echo "FAIL: expected 2 clean g27_done lines" >&2; fail=1; }

if [ "$fail" -ne 0 ]; then
  echo "G-27 DEVICE E2E FAIL ($UDID)" >&2
  exit 1
fi
echo "G-27 DEVICE E2E PASS ($UDID)"
