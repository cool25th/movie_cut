#!/usr/bin/env bash
# 4K composite + memory baseline (S6 of docs/PRO_SPEC_GAP_WORKORDER_20260730.md).
#
# Fills the two PERF_BASELINE review triggers — "heavy composite" and
# "4K / long-form" — that the 720p→1080p Debug-only baseline left open. This is
# the decision input that keeps or retracts the Metal defer.
#
# Fixture: 10s / 3840x2160 / 30fps generated test pattern. Three export paths:
#   1. passthrough — no per-clip effects (the floor)
#   2. color       — 5-step color correction, every frame via CoreImage
#   3. heavy       — transition + mask + 3 overlapping layers (worst case)
#
# Measured in Debug only. The headless export harness (UITestHarness.swift) is
# wrapped in `#if DEBUG`, so it is absent from Release builds and cannot drive a
# headless export there. Debug is the conservative upper bound — Release is
# optimized, so any "not a bottleneck" conclusion holds a fortiori for Release
# (the same logic the existing PERF_BASELINE uses). The build is done with
# ENABLE_APP_SANDBOX=NO because the sandbox (enabled for shipping by S3) blocks
# the harness from reaching files passed via env vars; the sandbox is a security
# boundary, not a rendering cost, so this does not change what S6 measures.
#
# Metrics (measured, not self-reported): export wall-clock, realtime multiplier
# (= wall / clip duration), and peak RSS. The wall clock is the single real
# export interval (start → artifact present); the 0.2s poll loop only exists to
# sample `ps` RSS while the export runs — sleep duration is never used as a
# performance metric (the G-04 lesson from PERF_BASELINE). Requires ffmpeg.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }

DURATION_S=10
MEM_LIMIT_BYTES=$((4 * 1024 * 1024 * 1024))   # 4 GB external-spec budget

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT
FIXTURE="$WORK/perf_4k_src.mp4"
echo "Generating ${DURATION_S}s 3840x2160 perf fixture…"
ffmpeg -y -loglevel error -f lavfi -i "testsrc2=s=3840x2160:r=30" -t "$DURATION_S" \
  -pix_fmt yuv420p -c:v libx264 -preset ultrafast "$FIXTURE"

# Builds one configuration; sets APP_BIN to its app binary path.
#
# The build is done with ENABLE_APP_SANDBOX=NO on purpose. Under the sandbox
# (enabled for shipping by S3), the headless harness cannot reach files passed
# via MOVIECUT_UITEST_IMPORT because there is no security-scoped grant at launch,
# so the export silently produces nothing. The sandbox is a security boundary,
# not a rendering cost, so disabling it here does not change what S6 measures
# (CoreImage composite cost / memory). This mirrors how perf_baseline.sh ran
# before S3 turned the sandbox on.
build_for() {
  local config="$1"
  echo "Building MovieCutMac ($config, sandbox OFF for headless harness)…"
  xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration "$config" \
    -destination 'platform=macOS,arch=arm64' \
    ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
  local products
  products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration "$config" \
    -destination 'platform=macOS,arch=arm64' -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
  APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
}

# Times one headless 4K export. $1=label, $2..=extra MOVIECUT_UITEST_* env
# assignments. Writes "$WORK/<label>.real" and "$WORK/<label>.rss".
run_export() {
  local label="$1"; shift
  local out="$WORK/${label}.mp4"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 2
  local start; start="$(python3 -c 'import time; print(time.time())')"
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_IMPORT="$FIXTURE" \
    MOVIECUT_UITEST_EXPORT_RESOLUTION=p4K \
    MOVIECUT_UITEST_EXPORT="$out" \
    MOVIECUT_UITEST_QUIT=1 \
    "$@" \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$! maxrss=0 rss i
  # Poll for the export artifact (proven pattern); sample peak RSS while it runs.
  for i in $(seq 1 1200); do
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
  echo "  $label real=${real}s rssKB=${maxrss} out=${outdur}s"
  echo "$real" > "$WORK/${label}.real"
  echo "$((maxrss * 1024))" > "$WORK/${label}.rss"
}

measure_config() {
  local config="$1"
  build_for "$config"
  [ -x "$APP_BIN" ] || { echo "app binary not found ($config)" >&2; exit 1; }

  echo "" && echo "=== measuring ($config) ==="
  run_export "${config}_passthrough"
  run_export "${config}_color"      MOVIECUT_UITEST_COLOR=1
  # heavy = transition + mask + 3 overlapping layers of the same 4K source.
  run_export "${config}_heavy" \
    MOVIECUT_UITEST_TRANSITION=crossDissolve \
    MOVIECUT_UITEST_MASK=1 \
    MOVIECUT_UITEST_IMPORT_EXTRA="$FIXTURE:$FIXTURE"
}

measure_config Debug

echo "" && echo "=== 4K baseline (10s / 3840x2160 export, Debug) ==="
printf "%-18s %8s %12s %12s\n" "path" "real(s)" "realtime-x" "peak-MB"
peak_overall=0
for path in passthrough color heavy; do
  label="Debug_${path}"
  real="$(cat "$WORK/${label}.real")"
  rss="$(cat "$WORK/${label}.rss")"
  [ "$rss" -gt "$peak_overall" ] && peak_overall="$rss"
  printf "%-18s %8.2f %12.2f %12.0f\n" "$path" "$real" \
    "$(python3 -c "print(round($real/$DURATION_S,2))")" \
    "$(python3 -c "print(round($rss/1048576,0))")"
done

echo ""
echo "peak RSS across all paths: $(python3 -c "print(round($peak_overall/1048576,0))") MB"
if [ "$peak_overall" -le "$MEM_LIMIT_BYTES" ]; then
  echo "=> 4 GB memory budget: WITHIN (peak $((peak_overall / 1048576)) MB <= 4096 MB)"
else
  echo "=> 4 GB memory budget: EXCEEDED (peak $((peak_overall / 1048576)) MB > 4096 MB)"
fi
