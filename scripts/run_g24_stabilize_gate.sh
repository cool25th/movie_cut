#!/bin/bash
# G-24 P2-G24-6 — stabilization E2E gate: the full pipeline (scene change →
# registration → smoothing → correction → DoD measurement) in the app
# context, on the deterministic wobble fixture.
#
# Asserts:
#   - SceneChangeProvider detected the fixture's boundary (app context)
#   - The DoD verdict: ratio ≤ 0.5·crop ≤ 15%·wobble ≤ 3%·cut errors 0
#
# Usage: bash scripts/run_g24_stabilize_gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXTURE="$ROOT/Tests/Fixtures/stab_wobble_320x240_4s_30fps.mp4"
[ -s "$FIXTURE" ] || { echo "missing fixture; run scripts/make_fixtures.sh" >&2; exit 1; }

echo "Building MovieCutMac (Debug, sandbox OFF)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

WORK="$(mktemp -d /tmp/moviecut-g24.XXXXXX)"
RESULT="$WORK/result.txt"
DUMP="$WORK/stabilize.json"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 1

echo "Running G-24 stabilization E2E…"
env MOVIECUT_UITEST=1 \
  MOVIECUT_UITEST_STABILIZE=1 \
  MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  MOVIECUT_UITEST_STABILIZE_RESULT="$DUMP" \
  MOVIECUT_UITEST_RESULT="$RESULT" \
  MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
PID=$!
( sleep 300; kill "$PID" 2>/dev/null; pkill -x MovieCutMac 2>/dev/null; true ) &
WATCHDOG=$!

for _ in $(seq 1 600); do
  grep -q "stabilize_done" "$RESULT" 2>/dev/null && break
  sleep 0.5
done
wait "$PID" 2>/dev/null || true
kill "$WATCHDOG" 2>/dev/null || true

echo "--- status ---"
cat "$RESULT" 2>/dev/null || echo "MISSING"

if [ ! -s "$DUMP" ]; then
  echo "FAIL: no JSON artifact" >&2
  exit 1
fi

python3 - "$DUMP" <<'PY'
import json, sys

dump = json.load(open(sys.argv[1]))
problems = []

if dump.get("error", "none") != "none":
    problems.append(f"error: {dump['error']}")
if not dump.get("sceneCutDetected"):
    problems.append("scene change not detected in app context")
if dump.get("frameCount", 0) < 100:
    problems.append(f"insufficient frames: {dump.get('frameCount')}")

print(f"scene_change_times: {dump.get('sceneChangeTimes', [])}")
print(f"frames: {dump.get('frameCount')}")
print(f"input_median: {dump.get('inputMedian'):.2f}")
print(f"residual_median: {dump.get('residualMedian'):.2f}")
print(f"reduction_ratio: {dump.get('reductionRatio'):.3f}")
print(f"crop_median: {dump.get('cropMedian'):.3f}")
print(f"severe_wobble: {dump.get('severeWobbleFraction'):.3f}")
print(f"scene_cut_errors: {dump.get('sceneCutErrors')}")
print(f"DoD: {'PASS' if dump.get('meetsDoD') else 'FAIL'}")
print(f"elapsed: {dump.get('elapsedSeconds', 0):.1f}s")

if problems:
    print(f"FAIL: {'; '.join(problems)}")
    sys.exit(1)
if not dump.get("meetsDoD"):
    print("FAIL: DoD not met")
    sys.exit(1)
PY

echo "G-24 STABILIZATION E2E PASS"
