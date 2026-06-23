#!/usr/bin/env bash
# Phase 0.3 performance baseline.
#
# Measures export wall-clock and peak memory for a standard 10s / 1080p export
# on two paths:
#   1. passthrough  — no per-clip effects
#   2. color        — color correction, forcing every frame through the CoreImage
#                     CustomVideoCompositor
#
# The delta between them is the CoreImage compositor cost, which is the decision
# input for Phase 2B (Metal pipeline only if this is a real bottleneck). Single
# run per path — a baseline, not a benchmark suite. Requires ffmpeg.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }

DURATION_S=10
echo "Building MovieCutMac (Debug)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT
FIXTURE="$WORK/perf_src.mp4"
echo "Generating ${DURATION_S}s 1280x720 perf fixture…"
ffmpeg -y -loglevel error -f lavfi -i "testsrc2=s=1280x720:r=30" -t "$DURATION_S" \
  -pix_fmt yuv420p -c:v libx264 -preset ultrafast "$FIXTURE"

# Times one headless export. Direct launch (a /usr/bin/time wrapper stops the GUI
# app from starting its run loop, so the .task harness never fires). Wall clock
# via python; peak RSS by sampling `ps` while the export runs. $1=label, $2=COLOR.
run_export() {
  local label="$1" color="$2"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 2
  local out="$WORK/${label}.mp4" extra=""
  [ -n "$color" ] && extra="MOVIECUT_UITEST_COLOR=1"
  local start; start="$(python3 -c 'import time; print(time.time())')"
  env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" $extra \
    MOVIECUT_UITEST_EXPORT="$out" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
  local pid=$! maxrss=0 rss i
  # Poll for the export artifact (proven pattern); sample RSS while it runs.
  for i in $(seq 1 600); do
    [ -s "$out" ] && break
    rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    if [ -n "$rss" ] && [ "$rss" -gt "$maxrss" ] 2>/dev/null; then maxrss="$rss"; fi
    sleep 0.2
  done
  wait "$pid" 2>/dev/null || true
  local end; end="$(python3 -c 'import time; print(time.time())')"
  local real outdur
  real="$(python3 -c "print(round($end-$start,2))")"
  outdur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" 2>/dev/null || echo 0)"
  echo "$label real=${real}s rssKB=${maxrss} out=${outdur}s"
  echo "$real" > "$WORK/${label}.real"
  echo "$((maxrss * 1024))" > "$WORK/${label}.rss"
}

echo "" && echo "=== measuring ==="
run_export passthrough ""
run_export color 1

PT="$(cat "$WORK/passthrough.real")"; PR="$(cat "$WORK/passthrough.rss")"
CT="$(cat "$WORK/color.real")";       CR="$(cat "$WORK/color.rss")"

echo "" && echo "=== Phase 0.3 baseline (10s / 1080p export) ==="
awk -v d="$DURATION_S" -v pt="$PT" -v pr="$PR" -v ct="$CT" -v cr="$CR" 'BEGIN {
  printf "passthrough : %6.2fs  (%.2fx realtime)  peak %.0f MB\n", pt, pt/d, pr/1048576
  printf "color (CI)  : %6.2fs  (%.2fx realtime)  peak %.0f MB\n", ct, ct/d, cr/1048576
  printf "CoreImage compositor overhead: +%.2fs  (%.1fx slower)\n", ct-pt, (pt>0?ct/pt:0)
  print  ""
  if (ct/d > 1.0) print "=> color export is slower than realtime: CustomVideoCompositor is a likely bottleneck (Phase 2B Metal candidate)."
  else            print "=> color export is faster than realtime: CoreImage path is NOT the bottleneck (defer Metal)."
}'
