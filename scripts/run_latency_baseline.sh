#!/usr/bin/env bash
# Latency baseline collection gate (development direction §3, P0-C).
#
# Collects the FIRST p50/p95 wall-clock baselines for the two SLOs that
# previously had instrumentation but no measured values:
#   - timeline seek (playback.seek signpost semantics: the seek REQUEST)
#   - project open (import.openProject interval: decode+migrate+swap)
#
# Drives the real app through the DEBUG harness
# (MOVIECUT_UITEST_LATENCY_BASELINE) — same launch pattern as
# run_recovery_gate.sh.
#
# G-27 cleanup (2026-08-19): enforcement is now the DEFAULT — baselines are
# recorded in PERFORMANCE_SLO.md (small + 10-minute fixture) and the gate
# fails on seek_request_p50 > 100ms or project_open > 3000ms (SLO v1
# targets). Pass --no-enforce for diagnostic collection. The gate runs TWO
# passes: the small fixture (fast regression window) and a deterministically
# generated 10-minute fixture (the project-open SLO's original meaning).
#
# Usage: bash scripts/run_latency_baseline.sh [seek_count] [--no-enforce]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SEEK_COUNT="${1:-30}"
ENFORCE=1
for arg in "$@"; do
  [ "$arg" = "--no-enforce" ] && ENFORCE=0
done

FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
[ -f "$FIXTURE" ] || { echo "missing fixture: run scripts/make_fixtures.sh" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg required for the 10-minute pass" >&2; exit 1; }

echo "Building MovieCutMac (Debug)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null 2>&1 \
  || { echo "build failed" >&2; exit 1; }
products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

# run_one <label> <fixture> — one harness launch; echoes the latency line.
run_one() {
  local label="$1" fixture="$2"
  local result="$WORK/latency-$label.txt"
  rm -f "$result"

  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_LATENCY_BASELINE="$SEEK_COUNT" \
    MOVIECUT_UITEST_IMPORT="$fixture" \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!

  # The scenario runs N seeks with a 40ms settle each plus composition
  # setup; writeHarnessStatus truncates per write, so the file's final
  # content is either the latency_baseline line or an error checkpoint.
  for _ in $(seq 1 240); do
    [ -s "$result" ] && grep -q "latency_baseline\|stage=error" "$result" && break
    sleep 0.5
  done
  sleep 1
  wait "$pid" 2>/dev/null

  if grep -q "stage=error" "$result" 2>/dev/null; then
    echo "[$label] status=FAIL detail=harness_error"
    cat "$result" 2>/dev/null || true
    return 1
  fi
  local line
  line="$(grep -o 'latency_baseline.*' "$result" 2>/dev/null || echo "")"
  if [ -z "$line" ]; then
    echo "[$label] status=FAIL detail=no_latency_baseline_line"
    cat "$result" 2>/dev/null || true
    return 1
  fi
  echo "[$label] $line"
  LAST_LINE="$line"
  return 0
}

enforce_line() {
  local label="$1" line="$2"
  local rc=0
  local seek_p50 open_ms
  seek_p50="$(echo "$line" | grep -oE 'seek_request_p50_ms=[0-9.]+' | cut -d= -f2)"
  open_ms="$(echo "$line" | grep -oE 'project_open_ms=[0-9.]+' | cut -d= -f2)"
  if [ -z "$seek_p50" ] || [ -z "$open_ms" ]; then
    echo "[$label] status=FAIL detail=missing_metric_for_enforcement"
    return 1
  fi
  awk -v v="$seek_p50" 'BEGIN { exit (v <= 100) ? 0 : 1 }' \
    || { echo "SLO VIOLATION [$label]: seek_request_p50_ms=$seek_p50 > 100"; rc=1; }
  awk -v v="$open_ms" 'BEGIN { exit (v <= 3000) ? 0 : 1 }' \
    || { echo "SLO VIOLATION [$label]: project_open_ms=$open_ms > 3000"; rc=1; }
  return "$rc"
}

pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 1

LAST_LINE=""
echo "=== latency baseline pass 1: small fixture (seek_count=$SEEK_COUNT) ==="
run_one small "$FIXTURE" || exit 1
SMALL_LINE="$LAST_LINE"

# Pass 2: a deterministic 10-minute fixture — the project-open SLO's
# original meaning (a LONG project must still open under 3s).
LONG_FIXTURE="$WORK/longform_10min_320x240.mp4"
echo "=== latency baseline pass 2: generated 10-minute fixture ==="
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc=duration=600:size=320x240:rate=30" \
  -f lavfi -i "sine=frequency=220:duration=600" \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -shortest "$LONG_FIXTURE" \
  || { echo "long fixture generation failed" >&2; exit 1; }
run_one longform "$LONG_FIXTURE" || exit 1
LONG_LINE="$LAST_LINE"

echo ""
echo "$SMALL_LINE"
echo "$LONG_LINE"
echo ""

if [ "$ENFORCE" -eq 1 ]; then
  rc=0
  enforce_line small "$SMALL_LINE" || rc=1
  enforce_line longform "$LONG_LINE" || rc=1
  [ "$rc" -eq 0 ] && echo "status=PASS enforced (small + 10-minute)"
  exit "$rc"
fi

echo "status=PASS collected (--no-enforce diagnostic mode)"
exit 0
