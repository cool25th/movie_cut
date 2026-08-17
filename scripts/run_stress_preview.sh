#!/usr/bin/env bash
# Stress-preview render measurement for the three fixed stress timelines
# (PERFORMANCE_SLO.md §스트레스 타임라인 3종, 구성 확정 2026-08-17).
#
# T1 멀티레이어·자막: bars + 텍스트 오버레이(카라오케) + 마스크 + BGM
# T2 광학플로우·AI:   moving subject + optical-flow slow-mo + 배경제거
#                    (모션 트래킹은 하니스 게이트 부재로 미포함 — SLO 참조)
# T3 컬러 체인:        solid red + 3-way grade + HSL/curve + color correction
#
# Each run drives the REAL app through the parity harness flow (the gates
# below are the fixed composition), sweeps N preview seeks, and reads the
# compositor render probe (p50/p95/max ms per frame request). The probe is
# armed only via MOVIECUT_UITEST_PREVIEW_PERF. Fixture media comes from the
# deterministic generators in make_fixtures.sh — no blobs, runs are
# reproducible on the same host/build.
#
# Usage:  bash scripts/run_stress_preview.sh [sample_count]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SAMPLES="${1:-40}"

BARS="$ROOT/Tests/Fixtures/bars_320x240_3s_30fps.mp4"
RED="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
SUBJECT="$ROOT/Tests/Fixtures/moving_subject_320x240_2s_30fps.mp4"
AUDIO="$ROOT/Tests/Fixtures/tone_440hz_2s_mono.wav"
for f in "$BARS" "$RED" "$SUBJECT" "$AUDIO"; do
  [ -s "$f" ] || { echo "missing fixture $f; run scripts/make_fixtures.sh" >&2; exit 1; }
done

echo "Building MovieCutMac (parity Debug)…"
PARITY_DERIVED_DATA="/tmp/MovieCutParityDerivedData"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$PARITY_DERIVED_DATA" \
  ENABLE_DEBUG_DYLIB=NO build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$PARITY_DERIVED_DATA" \
  ENABLE_DEBUG_DYLIB=NO -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BUNDLE="$PRODUCTS_DIR/MovieCutMac.app"
APP_BIN="$APP_BUNDLE/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found at $APP_BIN" >&2; exit 1; }

APP_CONTAINER_TMP="$HOME/Library/Containers/com.moviecut.mac/Data/tmp/moviecut-stress"
STAGED="$APP_CONTAINER_TMP/fixtures-stress"
mkdir -p "$STAGED"
cp "$BARS" "$STAGED/bars.mp4"
cp "$RED" "$STAGED/red.mp4"
cp "$SUBJECT" "$STAGED/subject.mp4"
cp "$AUDIO" "$STAGED/audio.wav"
trap 'rm -rf "$STAGED"' EXIT

# run_stress <name> <times> <extra_env...>
run_stress() {
  local name="$1"; local times="$2"; shift 2
  local work="$APP_CONTAINER_TMP/$name"
  rm -rf "$work"; mkdir -p "$work/preview"
  open -n -W \
    --env "MOVIECUT_UITEST=1" \
    --env "MOVIECUT_UITEST_PARITY=1" \
    --env "MOVIECUT_UITEST_PARITY_TIMES=$times" \
    --env "MOVIECUT_UITEST_PREVIEW_PERF=$SAMPLES" \
    --env "MOVIECUT_UITEST_PREVIEW_DUMP=$work/preview" \
    --env "MOVIECUT_UITEST_RESULT=$work/result.txt" \
    --env "MOVIECUT_UITEST_QUIT=1" \
    "$@" \
    "$APP_BUNDLE" >/dev/null 2>&1 &
  local pid=$!
  ( sleep 300; kill "$pid" 2>/dev/null; pkill -f "$APP_BIN" 2>/dev/null ) &
  local wd=$!
  for _ in $(seq 1 600); do [ -s "$work/result.txt" ] && grep -q "parity_done\|error=" "$work/result.txt" && break; sleep 0.5; done
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true
  wait "$wd" 2>/dev/null || true

  local status; status="$(cat "$work/result.txt" 2>/dev/null || echo MISSING)"
  if ! echo "$status" | grep -q "parity_done"; then
    echo "  $name: HARNESS INCOMPLETE — $status" >&2
    return 1
  fi
  echo "  $name: $status" | tr ' ' '\n' | grep -E "preview_render|error=" | tr '\n' ' '
  echo
}

echo "Stress preview measurement (samples=$SAMPLES, macOS Debug build):"
echo "T1 — 멀티레이어·자막 (bars + karaoke text + mask + bgm):"
run_stress t1_multilayer "0.5" \
  --env "MOVIECUT_UITEST_IMPORT=$STAGED/bars.mp4" \
  --env "MOVIECUT_UITEST_TEXT_AT=0.5" \
  --env "MOVIECUT_UITEST_KARAOKE=1" \
  --env "MOVIECUT_UITEST_MASK=1" \
  --env "MOVIECUT_UITEST_BGM_AT=0.5" \
  --env "MOVIECUT_UITEST_BGM_PATH=$STAGED/audio.wav" || true

echo "T2 — 광학플로우·AI (subject + 0.5x optical flow + background removal; tracking gate 미포함):"
run_stress t2_optical_ai "0.5" \
  --env "MOVIECUT_UITEST_IMPORT=$STAGED/subject.mp4" \
  --env "MOVIECUT_UITEST_SPEED_RATE=0.5" \
  --env "MOVIECUT_UITEST_OPTICAL_FLOW=1" \
  --env "MOVIECUT_UITEST_BACKGROUND_REMOVAL=1" || true

echo "T3 — 컬러 체인 (red + grade + hsl/curves + correction):"
run_stress t3_color_chain "0.5" \
  --env "MOVIECUT_UITEST_IMPORT=$STAGED/red.mp4" \
  --env "MOVIECUT_UITEST_GRADE=1" \
  --env "MOVIECUT_UITEST_HSL_CURVES=1" \
  --env "MOVIECUT_UITEST_COLOR=1" || true

echo "Done. Record p50/p95 into docs/PERFORMANCE_SLO.md (measured values, host/build noted)."
