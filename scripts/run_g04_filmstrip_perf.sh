#!/usr/bin/env bash
# G-04 Inc 5 actual-app TimelineView performance and memory verification.
#
# This is deliberately separate from the broad export E2E suite: it creates
# sparse/low-bitrate temporary long fixtures, drives the DEBUG-only real
# TimelineView zoom/ScrollViewReader consumer, and leaves no generated media in
# the repository. The UI timing metric is the duration of signposted main-thread
# request, publish, consumer update, and AppKit draw operations. It deliberately
# excludes idle/scheduler delay and is not literal display-presentation FPS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v ffmpeg >/dev/null || { echo "FAIL: ffmpeg is required" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "FAIL: ffprobe is required" >&2; exit 1; }
if pgrep -f '[r]un_e2e_export.sh' >/dev/null 2>&1; then
  echo "FAIL: scripts/run_e2e_export.sh is already running; filmstrip perf uses the same app process" >&2
  exit 1
fi

WORK="$(mktemp -d)"
APP_PATTERN="MovieCutMac.app/Contents/MacOS/MovieCutMac"
APP_PID=""
cleanup() {
  if [ -n "$APP_PID" ]; then
    kill "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

if pgrep -f "$APP_PATTERN" >/dev/null 2>&1; then
  echo "FAIL: MovieCutMac is already running; close it before the isolated filmstrip perf check" >&2
  exit 1
fi

echo "Building MovieCutMac (Debug)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "FAIL: app binary not found at $APP_BIN" >&2; exit 1; }

IMAGE_FIXTURE="$ROOT/Tests/Fixtures/swatch_blue_64x64.png"
AUDIO_FIXTURE="$ROOT/Tests/Fixtures/duck_bgm_220hz_4s_mono.wav"
[ -s "$IMAGE_FIXTURE" ] || { echo "FAIL: missing $IMAGE_FIXTURE" >&2; exit 1; }
[ -s "$AUDIO_FIXTURE" ] || { echo "FAIL: missing $AUDIO_FIXTURE" >&2; exit 1; }

make_looped_fixture() {
  local width="$1" height="$2" duration="$3" output="$4" short="$5"
  ffmpeg -y -v error -f lavfi \
    -i "testsrc=size=${width}x${height}:rate=10:duration=12" \
    -an -c:v libx264 -preset ultrafast -crf 42 -pix_fmt yuv420p \
    -g 10 -keyint_min 10 -sc_threshold 0 "$short"
  ffmpeg -y -v error -stream_loop -1 -i "$short" -t "$duration" -c copy \
    -movflags +faststart "$output"
}

DENSITY_FIXTURE="$WORK/filmstrip_1080p_180s.mp4"
MEMORY_FIXTURE="$WORK/filmstrip_4k_600s.mp4"
echo "Generating temporary 3-minute 1080p density fixture…"
make_looped_fixture 1920 1080 180 "$DENSITY_FIXTURE" "$WORK/density_short.mp4"
echo "Generating temporary 10-minute 4K memory fixture…"
make_looped_fixture 3840 2160 600 "$MEMORY_FIXTURE" "$WORK/memory_short.mp4"

read -r memory_width memory_height memory_duration < <(
  ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height:format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$MEMORY_FIXTURE" \
  | awk 'NR==1{w=$1} NR==2{h=$1} NR==3{d=$1} END{print w,h,d}'
)
python3 - "$memory_width" "$memory_height" "$memory_duration" <<'PY'
import sys
w, h, duration = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
if (w, h) != (3840, 2160) or duration < 599.0:
    raise SystemExit(f"FAIL: memory fixture is not a 10-minute 4K asset: {w}x{h} {duration:.3f}s")
PY

run_density() {
  local result="$WORK/density_result.txt"
  echo "Running actual TimelineView density/zoom/scroll scenario…"
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_IMPORT="$IMAGE_FIXTURE,$DENSITY_FIXTURE" \
    MOVIECUT_UITEST_IMPORT_EXTRA="$AUDIO_FIXTURE" \
    MOVIECUT_UITEST_FILMSTRIP_PERF=density \
    MOVIECUT_UITEST_RESULT="$result" MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >"$WORK/density_app.log" 2>&1 &
  APP_PID=$!
  local pid=$APP_PID
  for _ in $(seq 1 1200); do
    [ -s "$result" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  wait "$pid" 2>/dev/null || true
  APP_PID=""
  local status
  status="$(cat "$result" 2>/dev/null || echo MISSING)"
  echo "$status" > "$WORK/density_status.txt"
  python3 - "$status" <<'PY'
import re, sys
status = sys.argv[1]

def integer(key):
    match = re.search(rf"(?:^| ){re.escape(key)}=(-?[0-9]+)(?: |$)", status)
    if not match:
        raise SystemExit(f"FAIL: missing {key}: {status}")
    return int(match.group(1))

def number(key):
    match = re.search(rf"(?:^| ){re.escape(key)}=([0-9.]+)(?: |$)", status)
    if not match:
        raise SystemExit(f"FAIL: missing {key}: {status}")
    return float(match.group(1))

def text(key):
    match = re.search(rf"(?:^| ){re.escape(key)}=([^ ]+)(?: |$)", status)
    if not match:
        raise SystemExit(f"FAIL: missing {key}: {status}")
    return match.group(1)

if "error=none" not in status or text("filmstrip_perf") != "density" or integer("perf_complete") != 1:
    raise SystemExit(f"FAIL: density harness did not complete: {status}")

levels = (20, 40, 80, 160)
densities = []
identities = []
for expected_bucket, level in enumerate(levels):
    if integer(f"density_{level}_bucket") != expected_bucket:
        raise SystemExit(f"FAIL: zoom bucket mismatch at {level}px/s: {status}")
    if min(integer(f"density_{level}_frames"), integer(f"density_{level}_digests"), integer(f"density_{level}_times")) <= 1:
        raise SystemExit(f"FAIL: rendered set was static/trivial at {level}px/s: {status}")
    if integer(f"density_{level}_requests") != 4 or integer(f"density_{level}_distinct_requests") != 4:
        raise SystemExit(f"FAIL: expected zoom plus three distinct real scroll requests at {level}px/s: {status}")
    if integer(f"ui_work_{level}_samples") < 16:
        raise SystemExit(f"FAIL: insufficient main-thread request/publish/update/draw samples at {level}px/s: {status}")
    identities.append(text(f"density_{level}_identity"))
    densities.append(number(f"density_{level}_fps"))
if len(set(identities)) != 4:
    raise SystemExit(f"FAIL: request identities did not change at all four levels: {identities}")
if any(left >= right for left, right in zip(densities, densities[1:])):
    raise SystemExit(f"FAIL: published frame density did not increase: {densities}")

samples = integer("ui_work_samples")
p95 = number("ui_work_p95_ms")
maximum = number("ui_work_max_ms")
over = integer("ui_work_over_16_6")
requests = integer("ui_work_requests")
publishes = integer("ui_work_publishes")
updates = integer("ui_work_updates")
draws = integer("ui_work_draws")
distinct_work_requests = integer("ui_work_distinct_requests")
off_main = integer("ui_work_off_main")
if samples < 64 or requests < 16 or publishes < 16 or updates < 16 or draws < 16 or distinct_work_requests < 16:
    raise SystemExit(
        "FAIL: insufficient filmstrip-attributable main-thread work coverage: "
        f"samples={samples} request_ops={requests} publishes={publishes} "
        f"updates={updates} draws={draws} identities={distinct_work_requests}"
    )
if off_main != 0:
    raise SystemExit(f"FAIL: filmstrip UI consumer work escaped the main thread: {off_main}")
if p95 > 16.6:
    raise SystemExit(f"FAIL: filmstrip main-thread work p95 exceeds 16.6ms: {p95:.3f}ms")
if maximum > 16.6:
    raise SystemExit(f"FAIL: filmstrip main-thread work max exceeds 16.6ms: {maximum:.3f}ms")
if over != 0:
    raise SystemExit(f"FAIL: filmstrip main-thread intervals over 16.6ms must be zero, found {over}")
if integer("cache_peak_bytes") > integer("cache_limit_bytes"):
    raise SystemExit(f"FAIL: decoded cache accounting exceeded its limit: {status}")
if integer("max_frame_height") > 60:
    raise SystemExit(f"FAIL: decoded frame height exceeded 60px: {status}")
for key in ("preserved_image", "preserved_audio", "preserved_text"):
    if integer(key) != 1:
        raise SystemExit(f"FAIL: actual TimelineView did not preserve {key}: {status}")

print(
    "PASS: density actual TimelineView "
    f"levels=20/40/80/160 buckets=0/1/2/3 "
    f"densities={','.join(f'{value:.3f}' for value in densities)} "
    f"main_thread_work_samples={samples} request_ops={requests} publishes={publishes} "
    f"updates={updates} draws={draws} identities={distinct_work_requests} "
    f"p95={p95:.3f}ms max={maximum:.3f}ms over16.6={over} "
    f"cache_peak={integer('cache_peak_bytes')}B limit={integer('cache_limit_bytes')}B "
    "max_height<=60 image/audio/text=preserved"
)
PY
}

run_memory() {
  local result="$WORK/memory_result.txt" phase="$WORK/memory_phase.txt"
  local samples="$WORK/memory_rss_samples.txt"
  echo "Running actual TimelineView 10-minute 4K one-minute-seek cache churn…"
  env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$MEMORY_FIXTURE" \
    MOVIECUT_UITEST_FILMSTRIP_PERF=memory MOVIECUT_UITEST_PERF_PHASE="$phase" \
    MOVIECUT_UITEST_RESULT="$result" MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >"$WORK/memory_app.log" 2>&1 &
  APP_PID=$!
  local pid=$APP_PID
  : > "$samples"
  for _ in $(seq 1 2400); do
    local current_phase rss
    current_phase="$(cat "$phase" 2>/dev/null || echo startup)"
    rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    [ -n "$rss" ] && echo "$current_phase $rss" >> "$samples"
    [ -s "$result" ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.05
  done
  wait "$pid" 2>/dev/null || true
  APP_PID=""
  local status
  status="$(cat "$result" 2>/dev/null || echo MISSING)"
  echo "$status" > "$WORK/memory_status.txt"
  python3 - "$status" "$samples" <<'PY'
import re, statistics, sys
status, sample_path = sys.argv[1], sys.argv[2]

def integer(key):
    match = re.search(rf"(?:^| ){re.escape(key)}=(-?[0-9]+)(?: |$)", status)
    if not match:
        raise SystemExit(f"FAIL: missing {key}: {status}")
    return int(match.group(1))

if "error=none" not in status or "filmstrip_perf=memory" not in status or integer("perf_complete") != 1:
    raise SystemExit(f"FAIL: memory harness did not complete: {status}")
for key in ("memory_seeks", "memory_published_sets", "memory_distinct_requests", "memory_nontrivial_sets"):
    if integer(key) != 10:
        raise SystemExit(f"FAIL: expected ten one-minute cache-churn sets ({key}): {status}")
if integer("cache_peak_bytes") > integer("cache_limit_bytes"):
    raise SystemExit(f"FAIL: decoded cache accounting exceeded 128MB: {status}")
if integer("cache_limit_bytes") != 128 * 1024 * 1024:
    raise SystemExit(f"FAIL: decoded cache limit changed: {status}")
if integer("max_frame_height") > 60:
    raise SystemExit(f"FAIL: decoded frame height exceeded 60px: {status}")

baseline = []
churn = []
with open(sample_path, encoding="utf-8") as handle:
    for line in handle:
        phase, raw = line.split()
        value = int(raw)
        if phase == "baseline":
            baseline.append(value)
        elif phase in ("churn", "complete"):
            churn.append(value)
if len(baseline) < 5 or not churn:
    raise SystemExit(f"FAIL: insufficient RSS phase samples baseline={len(baseline)} churn={len(churn)}")
baseline_kb = int(statistics.median(baseline))
peak_kb = max(churn)
delta_kb = max(0, peak_kb - baseline_kb)
limit_kb = 100 * 1024
if delta_kb > limit_kb:
    raise SystemExit(
        f"FAIL: 10-minute 4K actual-app RSS delta {delta_kb / 1024:.1f}MB exceeds +100MB"
    )
print(
    "PASS: memory actual TimelineView "
    f"fixture=3840x2160/600s seeks=30..570s/60s "
    f"rss_baseline={baseline_kb / 1024:.1f}MB rss_peak={peak_kb / 1024:.1f}MB "
    f"rss_delta={delta_kb / 1024:.1f}MB threshold=100MB "
    f"cache_current={integer('cache_current_bytes')}B cache_peak={integer('cache_peak_bytes')}B "
    f"cache_limit={integer('cache_limit_bytes')}B keys={integer('cache_keys')} "
    f"evictions={integer('cache_evictions')} max_height={integer('max_frame_height')}"
)
PY
}

run_density
run_memory
echo "G-04 AC1 actual-app performance check OK"
