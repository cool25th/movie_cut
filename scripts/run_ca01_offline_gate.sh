#!/usr/bin/env bash
# CA-01 — offline/network-denied operation test + traffic capture (MC-02 ②③).
#
# The product promises fully offline operation (no telemetry, no remote
# calls). This gate proves it MEASURED, in two legs:
#
#   Leg 1 (Mac, 차단테스트): the representative workload (parity harness:
#            import → composition → preview dump → export) runs under a
#            sandbox-exec profile that DENIES every network operation. The
#            workload must complete; the sandboxd log must show ZERO network
#            violations from the process (캡처 0 — the app never even TRIES).
#            A loopback probe proves the profile genuinely blocks (a broken
#            profile would make the leg vacuously pass).
#
#   Leg 2 (iOS, 캡처): the G-27 simulator harness (import → preview →
#            export → audio routing → persistence) runs on a real simulator
#            while this script polls lsof for the app process's network
#            sockets. Max observed sockets must be 0.
#
# Evidence numbers from this script land in COMPETITIVE_ANALYSIS Part 9
# (MC-02) and the CA-01 backlog row.
#
# Usage: bash scripts/run_ca01_offline_gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
[ -s "$FIXTURE" ] || { echo "missing fixture; run scripts/make_fixtures.sh" >&2; exit 1; }

WORK="$(mktemp -d /tmp/moviecut-ca01.XXXXXX)"
trap 'rm -rf "$WORK"; pkill -x MovieCutMac 2>/dev/null || true' EXIT

PROFILE="$WORK/netdeny.sb"
cat > "$PROFILE" <<'SB'
(version 1)
(allow default)
(deny network*)
SB

# --- Leg 1: Mac, network-denied representative workload ----------------------
echo "=== Leg 1: Mac — parity harness under network-DENIED sandbox ==="

# Profile sanity probe: a loopback connect inside the profile MUST fail,
# otherwise the deny rule is inert and the leg would pass vacuously.
if sandbox-exec -f "$PROFILE" /bin/sh -c 'nc -z -w 1 127.0.0.1 9' 2>/dev/null; then
  echo "FAIL: sandbox profile does not block networking (loopback probe connected)" >&2
  exit 1
fi
echo "profile probe: loopback connect DENIED (profile is effective)"

echo "Building MovieCutMac (Debug)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build \
  > "$WORK/mac_build.log" 2>&1 || { tail -20 "$WORK/mac_build.log" >&2; exit 1; }
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}' || true)"
[ -n "$PRODUCTS_DIR" ] || { echo "FAIL: could not resolve Mac BUILT_PRODUCTS_DIR" >&2; exit 1; }
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

MAC_RESULT="$WORK/mac_result.txt"
MAC_EXPORT="$WORK/mac_export.mp4"
MAC_DUMP="$WORK/mac_dump"; mkdir -p "$MAC_DUMP"
LOG_SINCE="$(date '+%Y-%m-%d %H:%M:%S')"

echo "Running parity harness (import → preview → export) with network denied…"
sandbox-exec -f "$PROFILE" \
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_PARITY=1 \
    MOVIECUT_UITEST_IMPORT="$FIXTURE" \
    MOVIECUT_UITEST_PARITY_TIMES="1.0" \
    MOVIECUT_UITEST_PREVIEW_DUMP="$MAC_DUMP" \
    MOVIECUT_UITEST_EXPORT="$MAC_EXPORT" \
    MOVIECUT_UITEST_RESULT="$MAC_RESULT" \
    MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >/dev/null 2>&1 &
MAC_PID=$!
( sleep 180; kill "$MAC_PID" 2>/dev/null; true ) & MAC_WD=$!
for _ in $(seq 1 360); do
  grep -q "parity_done" "$MAC_RESULT" 2>/dev/null && break
  sleep 0.5
done
wait "$MAC_PID" 2>/dev/null || true
kill "$MAC_WD" 2>/dev/null || true

grep -q "parity_done" "$MAC_RESULT" 2>/dev/null \
  || { echo "FAIL: harness did not finish under network denial ($(tail -1 "$MAC_RESULT" 2>/dev/null))" >&2; exit 1; }
[ -s "$MAC_EXPORT" ] || { echo "FAIL: no export produced under network denial" >&2; exit 1; }
MAC_DURATION="$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$MAC_EXPORT")"
python3 -c "import sys; sys.exit(0 if abs($MAC_DURATION - 2.0) < 0.15 else 1)" \
  || { echo "FAIL: exported file invalid under network denial (duration=$MAC_DURATION)" >&2; exit 1; }
echo "workload: PASS (parity_done, export $(stat -f%z "$MAC_EXPORT") bytes, duration=${MAC_DURATION}s)"

# 캡처: sandboxd must contain ZERO network violations for the wrapped process.
# (log show can emit a leading date-precision warning on stderr; tolerated.)
VIOLATIONS="$(log show --start "$LOG_SINCE" --predicate 'process == "sandboxd"' --info 2>/dev/null \
  | grep -i "network" | grep -ci "MovieCutMac" || true)"
echo "sandbox network violations for MovieCutMac: ${VIOLATIONS:-0}"
[ "${VIOLATIONS:-0}" -eq 0 ] \
  || { echo "FAIL: the app attempted network operations while denied ($VIOLATIONS sandboxd entries)" >&2; exit 1; }

# --- Leg 2: iOS simulator, socket capture during the full G-27 harness -------
echo ""
echo "=== Leg 2: iOS — socket capture during G-27 simulator harness ==="

BUNDLE_ID="com.moviecut.ios"
TONE="$ROOT/Tests/Fixtures/tone_440hz_2s_mono.wav"
[ -s "$TONE" ] || { echo "missing tone fixture" >&2; exit 1; }

UDID="$(xcrun simctl list devices available | grep -E 'iPhone' | head -1 | grep -oE '[0-9A-F-]{36}')"
[ -n "$UDID" ] || { echo "no available iPhone simulator" >&2; exit 1; }
echo "Device: $(xcrun simctl list devices available | grep "$UDID" | sed 's/(.*//;s/^ *//' | head -1) ($UDID)"

echo "Building MovieCutiOS (Debug, simulator)…"
# Build output is captured (not swallowed): a failed build under set -e used
# to exit silently; concurrent build-system contention also deserves one
# retry before failing the gate.
IOS_BUILD_OK=0
for attempt in 1 2; do
  if xcodebuild -project MovieCut.xcodeproj -scheme MovieCutiOS -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build \
    > "$WORK/ios_build.log" 2>&1; then
    IOS_BUILD_OK=1
    break
  fi
  echo "iOS build attempt $attempt failed — retrying after backoff (log: $WORK/ios_build.log)" >&2
  sleep 20
done
[ "$IOS_BUILD_OK" -eq 1 ] || { tail -20 "$WORK/ios_build.log" >&2; exit 1; }
# -showBuildSettings can lose to build-system contention (a failed command
# substitution under set -e used to exit SILENTLY right after a successful
# build) — retry and validate loudly.
IOS_PRODUCTS=""
for attempt in 1 2 3; do
  IOS_PRODUCTS="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutiOS -configuration Debug \
    -destination "platform=iOS Simulator,id=$UDID" \
    -showBuildSettings 2>"$WORK/ios_settings.err" \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}' || true)"
  [ -n "$IOS_PRODUCTS" ] && break
  echo "iOS showBuildSettings attempt $attempt empty — retrying" >&2
  sleep 10
done
[ -n "$IOS_PRODUCTS" ] || { echo "FAIL: could not resolve iOS BUILT_PRODUCTS_DIR" >&2; cat "$WORK/ios_settings.err" >&2; exit 1; }
IOS_APP="$IOS_PRODUCTS/MovieCutiOS.app"
[[ -d "$IOS_APP" ]] || { echo "iOS app not found at $IOS_APP" >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$IOS_APP"
CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
mkdir -p "$CONTAINER/Documents/in"
cp "$FIXTURE" "$CONTAINER/Documents/in/fixture.mp4"
cp "$TONE" "$CONTAINER/Documents/in/tone.wav"
rm -f "$CONTAINER/Documents/g27-result.txt"
IOS_RESULT="$CONTAINER/Documents/g27-result.txt"

SIMCTL_CHILD_MOVIECUT_UITEST=1 xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null

MAX_SOCKETS=0
SAMPLES=0
for _ in $(seq 1 240); do
  grep -q "g27_done" "$IOS_RESULT" 2>/dev/null && break
  IOS_PID="$(pgrep -x MovieCutiOS | head -1 || true)"
  if [ -n "$IOS_PID" ]; then
    # lsof exits NONZERO when it finds no matching sockets (the expected
    # state!) — without `|| true`, pipefail fails the substitution and set -e
    # kills the gate on the very first sample.
    SOCKETS="$(lsof -a -i -p "$IOS_PID" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ' || true)"
    SAMPLES=$((SAMPLES + 1))
    # NB: an `[ … ] && assignment` line returns 1 when the test is false,
    # which set -e treats as a fatal error — hence the explicit if.
    if [ "$SOCKETS" -gt "$MAX_SOCKETS" ]; then
      MAX_SOCKETS="$SOCKETS"
    fi
  fi
  sleep 0.5
done
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

grep -q "g27_done" "$IOS_RESULT" 2>/dev/null \
  || { echo "FAIL: iOS harness did not finish" >&2; cat "$IOS_RESULT" 2>/dev/null >&2; exit 1; }
echo "iOS harness: PASS (g27_done)"
echo "iOS network sockets observed: max=$MAX_SOCKETS across $SAMPLES lsof samples"
[ "$MAX_SOCKETS" -eq 0 ] \
  || { echo "FAIL: the iOS app held network sockets during the workload ($MAX_SOCKETS)" >&2; exit 1; }
[ "$SAMPLES" -ge 10 ] \
  || { echo "FAIL: too few capture samples ($SAMPLES) — capture window suspect" >&2; exit 1; }

echo ""
echo "CA-01 OFFLINE GATE PASS — workload passed with network denied (Mac), 0 violations;"
echo "0 sockets across $SAMPLES samples during the full iOS harness."
