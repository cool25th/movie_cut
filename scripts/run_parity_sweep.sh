#!/usr/bin/env bash
# Parity sweep — collects preview+export evidence for every `=` B-ID effect.
#
# PERF_BASELINE / CAPCUT_BENCHMARK_STANDARD note that many `=` parity verdicts
# were assigned without simultaneous preview+export evidence (the 2026-07-28
# finding that the main Preview was not using the project composition path).
# This script drives the parity harness (`MOVIECUT_UITEST_PARITY=1`) across
# each effect gate, producing for every scenario:
#   - preview PNG dumps at t=0.5s and t=1.5s
#   - an export mp4
#   - a pixel diff (verify_preview_export_parity.py) + duration check
# A scenario PASS means preview and export agree within tolerance at both
# timestamps AND the export duration is within one frame of the composition
# duration. The sweep result is a `key=value` table so a doc can record it.
#
# Uses the committed fixture Tests/Fixtures/solid_red_320x240_2s_30fps.mp4
# (run scripts/make_fixtures.sh first if missing). Builds Debug+sandbox OFF.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
[ -f "$FIXTURE" ] || { echo "missing fixture: run scripts/make_fixtures.sh" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

PARITY_TIMES="0.5,1.5"
TOLERANCE=12.0

echo "Building MovieCutMac (Debug, sandbox OFF for parity sweep)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build >/dev/null
products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

# Runs one parity scenario. $1=name, $2=PARITY_TIMES, $3..=parity env gates.
# Writes PASS/FAIL to stdout as `name status=<PASS|FAIL> detail=<...>`.
# Scenarios that change the timeline duration (trim, speed_rate, speed_ramp,
# freeze) take shorter PARITY_TIMES so both samples stay inside the export.
run_scenario() {
  local name="$1"; shift
  local times="$1"; shift
  local dir="$WORK/$name"
  mkdir -p "$dir"
  local export_mp4="$dir/export.mp4"
  local preview_dir="$dir/preview"
  local result="$dir/result.txt"
  rm -f "$result"

  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 2
  env MOVIECUT_UITEST=1 MOVIECUT_UITEST_PARITY=1 \
    MOVIECUT_UITEST_IMPORT="$FIXTURE" \
    MOVIECUT_UITEST_PARITY_TIMES="$times" \
    MOVIECUT_UITEST_PREVIEW_DUMP="$preview_dir" \
    MOVIECUT_UITEST_EXPORT="$export_mp4" \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    "$@" \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!
  # Watchdog: 240s hard kill (parity path can hang on host GPU compositor).
  ( sleep 240; kill "$pid" 2>/dev/null || true ) &
  local wd=$!
  for _ in $(seq 1 480); do [ -s "$result" ] && break; sleep 0.5; done
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true

  local status detail
  status="$(grep -o 'parity_done' "$result" 2>/dev/null || echo "")"
  local comp_err exp_err dumped
  comp_err="$(grep -oE 'composition_error=[^ ]*' "$result" 2>/dev/null | head -1 | cut -d= -f2)"
  exp_err="$(grep -oE 'error=[^ ]*' "$result" 2>/dev/null | tail -1 | cut -d= -f2)"
  dumped="$(grep -oE 'dumped_frames=[0-9]+' "$result" 2>/dev/null | head -1 | cut -d= -f2)"
  local comp_dur
  comp_dur="$(grep -oE 'duration=[0-9.]+' "$result" 2>/dev/null | head -1 | cut -d= -f2)"

  if [ "$status" != "parity_done" ] || [ "${exp_err:-none}" != "none" ] \
     || [ "${comp_err:-none}" != "none" ] || [ "${dumped:-0}" -lt 1 ]; then
    printf "%-14s status=FAIL detail=harness comp_err=%s exp_err=%s dumped=%s\n" \
      "$name" "${comp_err:-missing}" "${exp_err:-missing}" "${dumped:-0}"
    return
  fi
  if [ ! -s "$export_mp4" ]; then
    printf "%-14s status=FAIL detail=no_export_mp4\n" "$name"
    return
  fi

  # Pixel + duration parity via the shared comparator.
  local cmp_out cmp_rc
  cmp_out="$(python3 "$ROOT/scripts/verify_preview_export_parity.py" \
    --preview-dir "$preview_dir" --export-mp4 "$export_mp4" \
    --times "$times" --tolerance "$TOLERANCE" --size 320x240 \
    --expect-duration "${comp_dur:-2.0}" --frame-rate 30 2>&1)" || cmp_rc=$?
  if [ "${cmp_rc:-0}" -eq 0 ] && echo "$cmp_out" | grep -q "RESULT: PASS"; then
    printf "%-14s status=PASS detail=%s\n" "$name" \
      "$(echo "$cmp_out" | grep -oE 'overall_MAD=[0-9.]+' | tail -1)"
  else
    printf "%-14s status=FAIL detail=pixel_or_duration\n" "$name"
    echo "$cmp_out" | grep -E "RESULT:|FAIL|Duration" | sed "s/^/      $name> /" || true
  fi
}

echo "" && echo "=== parity sweep (preview vs export, 13 scenarios) ==="
echo ""
# Default samples land inside a 2s timeline. Scenarios that shorten the
# timeline (trim to 1s, 2x speed to 1s, speed ramp to ~1.4s) use 0.3,0.7.
run_scenario passthrough "$PARITY_TIMES"
run_scenario color         "$PARITY_TIMES" MOVIECUT_UITEST_COLOR=1
run_scenario grade         "$PARITY_TIMES" MOVIECUT_UITEST_GRADE=1
run_scenario hsl_curves    "$PARITY_TIMES" MOVIECUT_UITEST_HSL_CURVES=1
run_scenario freeze        "$PARITY_TIMES" MOVIECUT_UITEST_FREEZE=1
run_scenario reverse       "$PARITY_TIMES" MOVIECUT_UITEST_REVERSE=1
run_scenario optical_flow  "$PARITY_TIMES" MOVIECUT_UITEST_OPTICAL_FLOW=1 MOVIECUT_UITEST_SPEED_RATE=0.5
run_scenario trim          "0.3,0.7"        MOVIECUT_UITEST_TRIM_AT=1.0
run_scenario move          "$PARITY_TIMES" MOVIECUT_UITEST_MOVE_TO=1.0
run_scenario mask          "$PARITY_TIMES" MOVIECUT_UITEST_MASK=1
run_scenario text          "$PARITY_TIMES" MOVIECUT_UITEST_TEXT_AT=0.5
run_scenario speed_rate    "0.3,0.7"        MOVIECUT_UITEST_SPEED_RATE=2.0
run_scenario speed_ramp    "0.3,0.7"        MOVIECUT_UITEST_SPEED_RAMP=1

echo ""
echo "=== parity sweep complete ==="
