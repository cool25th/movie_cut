#!/usr/bin/env bash
# Release-build performance baseline.
#
# This fills the structural gap noted in PERF_BASELINE: every prior number
# (1080p, 4K, G-04 filmstrip) was measured in Debug because the headless
# export harness (UITestHarness.swift) was gated by `#if DEBUG` and therefore
# absent from Release. As of 2026-08-01 the harness gate is
# `#if DEBUG || MOVIECUT_HARNESS`, so a Release build compiled with the
# MOVIECUT_HARNESS condition can drive the same headless export. This script
# produces that build and runs the same 4K three-path measurement as
# perf_4k.sh, so Debug (conservative upper bound) and Release (the actual
# shipping performance) are directly comparable.
#
# Why MOVIECUT_HARNESS and not DEBUG: a Release build with DEBUG would disable
# optimizations (-Onone) and defeat the purpose of measuring shipping speed.
# MOVIECUT_HARNESS compiles the harness into an otherwise-normal optimized
# (-O, wholemodule) Release build. Shipping builds are produced without the
# condition, so the harness stays out of the App Store binary.
#
# The build is done with ENABLE_APP_SANDBOX=NO for the same reason as
# perf_4k.sh: the sandbox (on for shipping) blocks the harness from reaching
# env-var files, and the sandbox is a security boundary, not a rendering cost.
# Sandbox-ON measurement is the separate perf_4k_sandbox.sh.
#
# Metrics are measured, not self-reported: export wall-clock, realtime
# multiplier, and peak RSS. Requires ffmpeg.
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
# $1 = "Release"  → optimized build + MOVIECUT_HARNESS (harness in, -O kept).
# $1 = "Debug"    → standard debug build (DEBUG condition, harness in).
# Both use ENABLE_APP_SANDBOX=NO so the harness can read env-var files.
build_for() {
  local config="$1"
  local extra=()
  if [ "$config" = "Release" ]; then
    extra+=(SWIFT_ACTIVE_COMPILATION_CONDITIONS=MOVIECUT_HARNESS
            SWIFT_OPTIMIZATION_LEVEL=-O)
  fi
  echo "Building MovieCutMac ($config, sandbox OFF for headless harness)…"
  xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration "$config" \
    -destination 'platform=macOS,arch=arm64' \
    ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO \
    ${extra[@]+"${extra[@]}"} build >/dev/null
  local products
  products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration "$config" \
    -destination 'platform=macOS,arch=arm64' -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
  APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
}

# Times one headless 4K export. $1=label, $2..=extra MOVIECUT_UITEST_* env.
# Writes "$WORK/<label>.real" and "$WORK/<label>.rss".
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
  # Poll for the export artifact; sample peak RSS while it runs.
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
measure_config Release

echo "" && echo "=== 4K baseline comparison (10s / 3840x2160 export) ==="
printf "%-12s %-12s %8s %12s %12s\n" "config" "path" "real(s)" "realtime-x" "peak-MB"
peak_overall=0
for config in Debug Release; do
  for path in passthrough color heavy; do
    label="${config}_${path}"
    real="$(cat "$WORK/${label}.real")"
    rss="$(cat "$WORK/${label}.rss")"
    [ "$rss" -gt "$peak_overall" ] && peak_overall="$rss"
    printf "%-12s %-12s %8.2f %12.2f %12.0f\n" "$config" "$path" "$real" \
      "$(python3 -c "print(round($real/$DURATION_S,2))")" \
      "$(python3 -c "print(round($rss/1048576,0))")"
  done
done

echo ""
echo "peak RSS across all configs/paths: $(python3 -c "print(round($peak_overall/1048576,0))") MB"
if [ "$peak_overall" -le "$MEM_LIMIT_BYTES" ]; then
  echo "=> 4 GB memory budget: WITHIN (peak $((peak_overall / 1048576)) MB <= 4096 MB)"
else
  echo "=> 4 GB memory budget: EXCEEDED (peak $((peak_overall / 1048576)) MB > 4096 MB)"
fi
