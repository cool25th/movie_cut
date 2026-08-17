#!/bin/bash
# T2-M — Motion Tracking Analysis measurement driver (validation doc §3.2).
#
# Runs the opt-in MotionTrackingAnalysisPerfTests suite in the RELEASE
# configuration (the measurement protocol rejects Debug numbers) and records
# the host environment the protocol requires (OS build, model, thermal/power
# state, repeat count). Output lands in artifacts/perf/ as the durable
# measurement artifact.
#
# Usage:
#   bash scripts/run_t2m_motion_tracking.sh
#   MOVIECUT_T2M_REPEATS=10 bash scripts/run_t2m_motion_tracking.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Deterministic input bytes (validation doc §4.5): hash-verify both fixtures.
FIXTURE_PLAIN="$ROOT/Tests/Fixtures/moving_subject_320x240_2s_30fps.mp4"
FIXTURE_OCCLUDED="$ROOT/Tests/Fixtures/moving_subject_occluded_320x240_3s_30fps.mp4"
EXPECTED_PLAIN_SHA="b7a9cb2e4209256ad43b3fbe7e704af447bdc6ca9e5224d988b4a0ce28fc2a63"
EXPECTED_OCCLUDED_SHA="2c697b489943ac549253d5d7c79293e8fb1306cb4d5faf7c29ca75426a6c1379"
for pair in "$FIXTURE_PLAIN:$EXPECTED_PLAIN_SHA" "$FIXTURE_OCCLUDED:$EXPECTED_OCCLUDED_SHA"; do
  f="${pair%%:*}"; want="${pair##*:}"
  if [[ ! -s "$f" ]]; then
    echo "missing fixture $f; run scripts/make_fixtures.sh" >&2
    exit 1
  fi
  got="$(shasum -a 256 "$f" | awk '{print $1}')"
  if [[ "$got" != "$want" ]]; then
    echo "fixture hash mismatch: $f expected=$want actual=$got" >&2
    exit 1
  fi
done

OUT_DIR="$ROOT/artifacts/perf"
mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$OUT_DIR/t2m-motion-tracking-$STAMP.txt"

{
  echo "== T2-M motion tracking analysis =="
  date
  sw_vers
  echo "arch=$(uname -m)"
  sysctl -n machdep.cpu.brand_string 2>/dev/null || true
  system_profiler SPHardwareDataType 2>/dev/null | grep -E "Model Name|Model Identifier|Chip|Memory" || true
  echo "-- power / thermal --"
  pmset -g therm 2>/dev/null || true
  pmset -g batt 2>/dev/null || true
  echo "-- config --"
  echo "config=release repeats=${MOVIECUT_T2M_REPEATS:-5} fixture=moving_subject_320x240_2s_30fps.mp4 sample_rate=15"
  echo "-- swift toolchain --"
  swift --version 2>&1 | head -2
} >"$OUT"

echo "Running T2-M (Release, repeats=${MOVIECUT_T2M_REPEATS:-5})…"
if ! MOVIECUT_T2M=1 swift test -c release --filter MotionTrackingAnalysisPerfTests 2>&1 | tee -a "$OUT"; then
  echo "T2M_FAIL (artifact: $OUT)" >&2
  exit 1
fi

if ! grep -q "T2M_AGG" "$OUT"; then
  echo "T2M_FAIL: no T2M_AGG aggregate line (artifact: $OUT)" >&2
  exit 1
fi
if ! grep -q "T2M_OCC" "$OUT"; then
  echo "T2M_FAIL: no T2M_OCC occlusion line (artifact: $OUT)" >&2
  exit 1
fi

grep -E "T2M_RUN|T2M_AGG|T2M_OCC" "$OUT"
echo "T2M_PASS (artifact: $OUT)"
