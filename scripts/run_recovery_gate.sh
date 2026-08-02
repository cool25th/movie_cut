#!/usr/bin/env bash
# B-U7 recovery regression gate.
#
# Verifies the crash-recovery flow (recoverableProject → adoptRecoveredProject
# / clearRecoveryAutosave) by driving a dedicated harness scenario that:
#   1. builds a project with real clips
#   2. flushAutosave() writes the crash-recovery file (what a crash leaves)
#   3. resets to a fresh project, then runs the recover/discard choice
#   4. reports recovered_clips + status so the gate can assert the outcome
#
# This mirrors the verified injection pattern (confirmDiscardUnsavedChanges +
# MOVIECUT_UITEST_UNSAVED_RESPONSE) rather than tapping the modal alert,
# whose accessibility handshake is unstable under XCUITest. The single-
# process simulation writes and re-reads the autosave within one launch, so
# no SIGKILL/relaunch is needed. The terminate-clear gate
# (MOVIECUT_UITEST_SKIP_RECOVERY_CLEAR) is set so a future two-launch XCUITest
# path can reuse the same recovery file.
#
# Two paths: "recover" (recovered_clips >= 1, status = Recovered unsaved work.)
# and "discard" (recovered_clips = 0, status = discarded).
#
# Usage: bash scripts/run_recovery_gate.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
[ -f "$FIXTURE" ] || { echo "missing fixture: run scripts/make_fixtures.sh" >&2; exit 1; }

echo "Building MovieCutMac (Debug)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build >/dev/null 2>&1 \
  || { echo "build failed" >&2; exit 1; }
products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

# Isolated autosave dir per run so recovery state doesn't leak across runs.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

# run_path <response> → drives one recovery path. Echoes PASS/FAIL.
run_path() {
  local response="$1"
  local result="$WORK/${response}.txt"
  rm -f "$result"

  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 1
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_RECOVERY=1 \
    MOVIECUT_UITEST_RECOVERY_RESPONSE="$response" \
    MOVIECUT_UITEST_IMPORT="$FIXTURE" \
    MOVIECUT_AUTOSAVE_DIR="$WORK/autosave_${response}" \
    MOVIECUT_UITEST_SKIP_RECOVERY_CLEAR=1 \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!
  for _ in $(seq 1 240); do [ -s "$result" ] && break; sleep 0.5; done
  wait "$pid" 2>/dev/null

  local line autosave clips status
  line="$(grep -o 'recovery_done.*' "$result" 2>/dev/null || echo "")"
  autosave="$(echo "$line" | grep -oE 'autosave_present=[01]' | cut -d= -f2)"
  clips="$(echo "$line" | grep -oE 'recovered_clips=[0-9]+' | cut -d= -f2)"
  status="$(echo "$line" | grep -oE 'status=.*' | cut -d= -f2-)"

  if [ -z "$line" ]; then
    printf "%-10s status=FAIL detail=no_recovery_done_line\n" "$response"
    return
  fi
  if [ "${autosave:-0}" != "1" ]; then
    printf "%-10s status=FAIL detail=autosave_not_present line=%s\n" "$response" "$line"
    return
  fi
  if [ "$response" = "recover" ]; then
    if [ "${clips:-0}" -ge 1 ] && echo "$status" | grep -q "Recovered unsaved work"; then
      printf "%-10s status=PASS recovered_clips=%s\n" "$response" "${clips}"
    else
      printf "%-10s status=FAIL detail=expected_clips>=1_and_recovery_status clips=%s status=%s\n" \
        "$response" "${clips:-?}" "$status"
    fi
  else  # discard
    if [ "${clips:-0}" -eq 0 ] && echo "$status" | grep -q "discarded"; then
      printf "%-10s status=PASS recovered_clips=%s\n" "$response" "${clips}"
    else
      printf "%-10s status=FAIL detail=expected_clips=0_and_discarded_status clips=%s status=%s\n" \
        "$response" "${clips:-?}" "$status"
    fi
  fi
}

echo "" && echo "=== recovery gate (B-U7) ==="
echo ""
rc=0
out="$(run_path recover)"; echo "$out"; echo "$out" | grep -q "status=PASS" || rc=1
out="$(run_path discard)"; echo "$out"; echo "$out" | grep -q "status=PASS" || rc=1
echo ""
if [ "$rc" -eq 0 ]; then
  echo "=> PASS: recover + discard both behaved correctly"
else
  echo "=> FAIL: at least one recovery path regressed (see above)"
fi
exit $rc
