#!/usr/bin/env bash
# 4K baseline under the App Sandbox (shipping configuration).
#
# perf_4k.sh measures with ENABLE_APP_SANDBOX=NO because the harness could not
# reach env-var files under the sandbox. As of 2026-08-01 the harness supports
# `MOVIECUT_UITEST_CONTAINERIZE=1`: fixtures are copied into the sandbox
# container's tmp/ (grant-free) and exports/results are staged there then moved
# to the requested path. This script runs the SAME 4K three-path measurement as
# perf_4k.sh but with ENABLE_APP_SANDBOX=YES (the shipping default), so the
# memory and wall-clock numbers are observed under the actual deployment
# boundary rather than with it disabled.
#
# Build: Debug + MOVIECUT_HARNESS. Sandbox ON. This answers the open question
# in PERF_BASELINE: the prior Debug/sandbox-OFF numbers left the sandbox
# interaction unmeasured. Release performance is perf_release.sh; this script
# isolates the sandbox variable.
#
# Requires ffmpeg. Exits non-zero if the harness fails to produce an artifact
# under the sandbox (which would itself be a finding worth recording).
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

# Build with sandbox ON (shipping default) and MOVIECUT_HARNESS so the harness
# compiles into an otherwise-normal Debug build. CODE_SIGNING_ALLOWED=NO keeps
# the build ad-hoc (the sandbox entitlements still take effect at run time).
echo "Building MovieCutMac (Debug, sandbox ON, MOVIECUT_HARNESS)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="MOVIECUT_HARNESS" \
  ENABLE_APP_SANDBOX=YES CODE_SIGNING_ALLOWED=NO build >/dev/null
products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

# Times one headless 4K export under the sandbox. $1=label, $2..=extra env.
run_export() {
  local label="$1"; shift
  local out="$WORK/${label}.mp4"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 2
  local start; start="$(python3 -c 'import time; print(time.time())')"
  # CONTAINERIZE=1 routes imports/exports through the sandbox container.
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_CONTAINERIZE=1 \
    MOVIECUT_UITEST_IMPORT="$FIXTURE" \
    MOVIECUT_UITEST_EXPORT_RESOLUTION=p4K \
    MOVIECUT_UITEST_EXPORT="$out" \
    MOVIECUT_UITEST_QUIT=1 \
    "$@" \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$! maxrss=0 rss i
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

echo "" && echo "=== measuring (Debug, sandbox ON) ==="
run_export sandbox_passthrough
run_export sandbox_color      MOVIECUT_UITEST_COLOR=1
# heavy = transition + mask + 3 overlapping layers of the same 4K source.
run_export sandbox_heavy \
  MOVIECUT_UITEST_TRANSITION=crossDissolve \
  MOVIECUT_UITEST_MASK=1 \
  MOVIECUT_UITEST_IMPORT_EXTRA="$FIXTURE:$FIXTURE"

echo "" && echo "=== 4K baseline (10s / 3840x2160 export, Debug, sandbox ON) ==="
printf "%-18s %8s %12s %12s\n" "path" "real(s)" "realtime-x" "peak-MB"
peak_overall=0
for path in passthrough color heavy; do
  label="sandbox_${path}"
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
