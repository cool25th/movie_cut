#!/bin/bash
# G-27 simulator E2E (development plan §3-11 ①) — the iOS counterpart of the
# Mac headless gates, on a real iOS Simulator:
#
#   phase 1 (launch #1, MOVIECUT_UITEST=1):   import staged fixtures → build
#             the app's real preview composition (+ one generated frame) →
#             export through IOSExportEngine → configure the AVAudioSession
#             playback category + report the route → save via ProjectStore
#   phase 2 (launch #2, +MOVIECUT_UITEST_REOPEN=1): reopen the saved project
#             in a FRESH process and verify the clips survived
#
# The harness appends structured lines to Documents/g27-result.txt inside the
# app container (host-readable); this script asserts them and ffprobes the
# exported file. The app is uninstalled first so every run starts from a
# clean container (deterministic).
#
# Usage: bash scripts/run_g27_simulator_e2e.sh [device_udid]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.moviecut.ios"
FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
TONE="$ROOT/Tests/Fixtures/tone_440hz_2s_mono.wav"
for f in "$FIXTURE" "$TONE"; do
  [ -s "$f" ] || { echo "missing fixture $f; run scripts/make_fixtures.sh" >&2; exit 1; }
done

# --- 1. Device ---------------------------------------------------------------
if [ $# -ge 1 ]; then
  UDID="$1"
else
  UDID="$(xcrun simctl list devices available | grep -E 'iPhone' | head -1 | grep -oE '[0-9A-F-]{36}')"
fi
[ -n "$UDID" ] || { echo "no available iPhone simulator" >&2; exit 1; }
DEVICE_NAME="$(xcrun simctl list devices available | grep "$UDID" | sed 's/(.*//;s/^ *//' | head -1)"
echo "Device: $DEVICE_NAME ($UDID)"

# --- 2. Build ----------------------------------------------------------------
echo "Building MovieCutiOS (Debug, simulator)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutiOS -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutiOS -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
APP="$PRODUCTS_DIR/MovieCutiOS.app"
[[ -d "$APP" ]] || { echo "app not found at $APP" >&2; exit 1; }

# --- 3. Clean install + stage fixtures ----------------------------------------
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
mkdir -p "$CONTAINER/Documents/in"
cp "$FIXTURE" "$CONTAINER/Documents/in/fixture.mp4"
cp "$TONE" "$CONTAINER/Documents/in/tone.wav"
rm -f "$CONTAINER/Documents/g27-result.txt"
RESULT="$CONTAINER/Documents/g27-result.txt"

wait_for_result() {
  local pattern="$1" timeout="${2:-240}"
  for _ in $(seq 1 "$((timeout * 2))"); do
    grep -q "$pattern" "$RESULT" 2>/dev/null && return 0
    sleep 0.5
  done
  return 1
}

# --- 4. Phase 1 ---------------------------------------------------------------
echo "Phase 1: import → preview → export → audio routing → save…"
SIMCTL_CHILD_MOVIECUT_UITEST=1 xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
if ! wait_for_result "g27_done"; then
  echo "FAIL: phase 1 harness did not finish (result below)" >&2
  cat "$RESULT" 2>/dev/null >&2
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  exit 1
fi
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
echo "--- phase 1 result ---"
cat "$RESULT"

# --- 5. Phase 2 (fresh process: reopen) ---------------------------------------
echo "Phase 2: reopen saved project in a fresh process…"
SIMCTL_CHILD_MOVIECUT_UITEST=1 SIMCTL_CHILD_MOVIECUT_UITEST_REOPEN=1 \
  xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
if ! wait_for_result "g27_reopen"; then
  echo "FAIL: phase 2 harness did not finish" >&2
  cat "$RESULT" 2>/dev/null >&2
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  exit 1
fi
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
echo "--- phase 2 result ---"
tail -3 "$RESULT"

# --- 6. Assertions ------------------------------------------------------------
fail=0
assert_line() {
  local pattern="$1"
  grep -qE "$pattern" "$RESULT" || { echo "FAIL: missing $pattern" >&2; fail=1; }
}
assert_line "g27_import imported_clips=[1-9]"
assert_line "g27_preview playable=1 duration=[0-9]+\\.[0-9]+ frame=1"
assert_line "g27_export file=.+ bytes=[1-9][0-9]*"
assert_line "g27_audio category=AVAudioSessionCategoryPlayback route=.+"
assert_line "g27_save saved=1"
assert_line "g27_reopen reopened_clips=[1-9]"
[ "$(grep -c "error=none" "$RESULT")" -eq 2 ] || { echo "FAIL: expected 2 clean g27_done lines" >&2; fail=1; }

# Host-side probe of the actual exported file (codec + duration).
EXPORT_FILE="$(find "$CONTAINER/tmp/MovieCutiOSExports" -name '*.mov' -newer "$CONTAINER/Documents/in/fixture.mp4" 2>/dev/null | head -1)"
if [ -z "$EXPORT_FILE" ]; then
  EXPORT_FILE="$(find "$CONTAINER/tmp/MovieCutiOSExports" -name '*.mov' 2>/dev/null | head -1)"
fi
if [ -n "$EXPORT_FILE" ]; then
  CODEC="$(ffprobe -v error -select_streams v -show_entries stream=codec_name -of csv=p=0 "$EXPORT_FILE" 2>/dev/null)"
  DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$EXPORT_FILE" 2>/dev/null)"
  echo "export probe: codec=$CODEC duration=${DURATION}s"
  [ "$CODEC" = "h264" ] || { echo "FAIL: unexpected export codec $CODEC" >&2; fail=1; }
else
  echo "FAIL: no exported .mov found in container" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "G-27 SIMULATOR E2E FAIL (container: $CONTAINER)" >&2
  exit 1
fi

echo "G-27 SIMULATOR E2E PASS ($DEVICE_NAME)"
