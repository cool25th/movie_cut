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
# run_recovery_gate.sh. This is a COLLECTION gate first: exit 1 only when the
# harness fails to produce numbers. Pass --enforce to additionally fail when
# seek_request_p50 exceeds 100ms or project_open exceeds 3000ms (PERFORMANCE_SLO
# v1 targets); keep enforcement off until baselines are recorded in the SLO doc.
#
# Usage: bash scripts/run_latency_baseline.sh [seek_count] [--enforce]
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SEEK_COUNT="${1:-30}"
ENFORCE=0
for arg in "$@"; do
  [ "$arg" = "--enforce" ] && ENFORCE=1
done

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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

RESULT="$WORK/latency.txt"
rm -f "$RESULT"

pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 1
env MOVIECUT_UITEST=1 \
  MOVIECUT_UITEST_LATENCY_BASELINE="$SEEK_COUNT" \
  MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  MOVIECUT_UITEST_RESULT="$RESULT" \
  MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
pid=$!

# The scenario runs N seeks with a 40ms settle each plus composition setup;
# allow generous wall time for slow CI machines. writeHarnessStatus truncates
# per write, so the file's final content is either the latency_baseline line
# or an error checkpoint.
for _ in $(seq 1 240); do
  [ -s "$RESULT" ] && grep -q "latency_baseline\|stage=error" "$RESULT" && break
  sleep 0.5
done
sleep 1
wait "$pid" 2>/dev/null

line="$(grep -o 'latency_baseline.*' "$RESULT" 2>/dev/null || echo "")"
if [ -z "$line" ]; then
  echo "status=FAIL detail=no_latency_baseline_line"
  cat "$RESULT" 2>/dev/null || true
  exit 1
fi
if grep -q "stage=error" "$RESULT"; then
  echo "status=FAIL detail=harness_error"
  cat "$RESULT" 2>/dev/null || true
  exit 1
fi

echo ""
echo "=== latency baseline (seek_count=$SEEK_COUNT) ==="
echo "$line"
echo ""

if [ "$ENFORCE" -eq 1 ]; then
  rc=0
  seek_p50="$(echo "$line" | grep -oE 'seek_request_p50_ms=[0-9.]+' | cut -d= -f2)"
  open_ms="$(echo "$line" | grep -oE 'project_open_ms=[0-9.]+' | cut -d= -f2)"
  if [ -z "$seek_p50" ] || [ -z "$open_ms" ]; then
    echo "status=FAIL detail=missing_metric_for_enforcement"
    exit 1
  fi
  awk -v v="$seek_p50" 'BEGIN { exit (v <= 100) ? 0 : 1 }' \
    || { echo "SLO VIOLATION: seek_request_p50_ms=$seek_p50 > 100"; rc=1; }
  awk -v v="$open_ms" 'BEGIN { exit (v <= 3000) ? 0 : 1 }' \
    || { echo "SLO VIOLATION: project_open_ms=$open_ms > 3000"; rc=1; }
  [ "$rc" -eq 0 ] && echo "status=PASS enforced"
  exit "$rc"
fi

echo "status=PASS collected (baselines recorded ad hoc; enforcement arrives with recorded targets)"
exit 0
