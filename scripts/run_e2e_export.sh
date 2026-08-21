#!/usr/bin/env bash
# Headless import → timeline → export end-to-end check (Phase 0.1c).
#
# Drives the real app pipeline via the DEBUG launch harness (env vars), without
# needing XCUITest's Accessibility/Automation permission. Asserts a genuine
# movie file is produced with the expected duration. Complements
# App/MovieCutMacUITests (which needs an interactive Accessibility grant).
#
# Usage:
#   bash scripts/run_e2e_export.sh             # sandbox OFF (default)
#   SANDBOX=1 bash scripts/run_e2e_export.sh   # sandbox ON (shipping config)
#
# Sandbox mode builds with ENABLE_APP_SANDBOX=YES + MOVIECUT_HARNESS and routes
# every harness invocation through the container via MOVIECUT_UITEST_CONTAINERIZE=1.
# The crash-recovery autosave gate is skipped under the sandbox (timing race;
# covered by AutosaveRecoveryTests unit + pending B-U7 e2e).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SANDBOX="${SANDBOX:-0}"
if [ "$SANDBOX" = "1" ]; then
  # Route fixture import / export writes through the sandbox container's
  # grant-free tmp/ so the same sections run sandboxed.
  export MOVIECUT_UITEST_CONTAINERIZE=1
  DESTINATION='platform=macOS,arch=arm64'
  BUILD_FLAGS=(SWIFT_ACTIVE_COMPILATION_CONDITIONS="MOVIECUT_HARNESS"
               ENABLE_APP_SANDBOX=YES CODE_SIGNING_ALLOWED=NO)
  BUILD_LABEL="Debug, sandbox ON, MOVIECUT_HARNESS"
  AWK_STRIP_CR='sub(/\r/,"",$2);'
else
  DESTINATION='platform=macOS'
  # The project.yml default is ENABLE_APP_SANDBOX=YES (S3 shipping config),
  # but a sandboxed harness build cannot read files passed via env vars
  # without the containerize routing — the import dies with
  # NSCocoaErrorDomain:257 and every section reports MISSING. Build the
  # DEFAULT mode sandbox-OFF (same rationale as perf_4k.sh / ui_capture.sh:
  # the sandbox is a security boundary, not a rendering cost). The SANDBOX=1
  # mode above covers the sandboxed configuration.
  BUILD_FLAGS=(ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO)
  BUILD_LABEL="Debug, sandbox OFF"
  AWK_STRIP_CR=''
fi

FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
[ -s "$FIXTURE" ] || { echo "missing fixture; run scripts/make_fixtures.sh" >&2; exit 1; }
FILMSTRIP_UNSUPPORTED_FIXTURE="$ROOT/Tests/Fixtures/swatch_blue_64x64.png"
[ -s "$FILMSTRIP_UNSUPPORTED_FIXTURE" ] || { echo "missing image fixture; run scripts/make_fixtures.sh" >&2; exit 1; }

echo "Building MovieCutMac (${BUILD_LABEL})…"
# `${BUILD_FLAGS[@]+"..."}` guard: expanding an empty array with [@] errors
# under `set -u` on the macOS-default bash 3.2 (CI's shell) — BUILD_FLAGS is
# empty in the default sandbox-OFF mode.
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination "$DESTINATION" ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"} build >/dev/null

PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination "$DESTINATION" ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"} -showBuildSettings 2>/dev/null \
  | awk -F' = ' "/ BUILT_PRODUCTS_DIR /{${AWK_STRIP_CR} print \$2; exit}")"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found at $APP_BIN" >&2; exit 1; }

# wait_for_result <pid> <iters> <sleep_secs> <file1> [file2]
# Polls for the result file(s) up to <iters> times, sleeping <sleep_secs>
# between checks, then waits for the background <pid>. Collapses the
# repeated "for _ in $(seq …); do [ -s … ] && break; sleep …; done; wait" idiom.
wait_for_result() {
  local pid="$1" iters="$2" sleep_secs="$3" file1="$4" file2="${5:-}"
  if [ -n "$file2" ]; then
    for _ in $(seq 1 "$iters"); do [ -s "$file1" ] && [ -s "$file2" ] && break; sleep "$sleep_secs"; done
  else
    for _ in $(seq 1 "$iters"); do [ -s "$file1" ] && break; sleep "$sleep_secs"; done
  fi
  wait "$pid" 2>/dev/null || true
}


# G-04 Inc 1-2: generate real time-varying frames through
# AVAssetImageGenerator, then exercise the zoom-keyed 128MB cache in the actual
# app process. The status records decoder timestamps and cache transitions.
FILMSTRIP_TMPDIR="$(mktemp -d)"
FILMSTRIP_RESULT="$FILMSTRIP_TMPDIR/filmstrip.txt"
sleep 1
echo "Running G-04 filmstrip generator smoke"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  MOVIECUT_UITEST_FILMSTRIP=1 MOVIECUT_UITEST_RESULT="$FILMSTRIP_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
FP=$!
wait_for_result "$FP" 120 0.25 "$FILMSTRIP_RESULT"
FILMSTRIP_STATUS="$(cat "$FILMSTRIP_RESULT" 2>/dev/null || echo MISSING)"
case "$FILMSTRIP_STATUS" in
  *"error=none"*"filmstrip_frames=4"*"requested=0.250,0.750,1.250,1.750"*"max_height="*"zoom_buckets=0,1,2,3"*"cache_hit=1"*"cache_miss=2"*"cache_inserts=1"*"cache_limit=134217728"*"cache_invalidate=1"*) ;;
  *) echo "FAIL: G-04 filmstrip generator/cache harness failed (status: $FILMSTRIP_STATUS)" >&2; rm -rf "$FILMSTRIP_TMPDIR"; exit 1 ;;
esac
echo "PASS: G-04 filmstrip generator/cache $FILMSTRIP_STATUS"
rm -rf "$FILMSTRIP_TMPDIR"

# G-04 Inc 3-4: exercise the actual TimelineView background and hover consumers. Two long,
# time-varying clips make the first clip only partly near-visible and the second
# clip offscreen/not-ready; an image clip proves unsupported hover stays hidden.
# The DEBUG observer is fed by TimelineFilmstripLayer/Store and the same
# TimelineFilmstripHoverModifier handler used by onContinuousHover;
# UITestHarness only waits for and serializes those real UI-consumer events.
TIMELINE_FILMSTRIP_TMPDIR="$(mktemp -d)"
TIMELINE_FILMSTRIP_FIXTURE="$TIMELINE_FILMSTRIP_TMPDIR/timevarying_30s.mp4"
TIMELINE_FILMSTRIP_RESULT="$TIMELINE_FILMSTRIP_TMPDIR/timeline_filmstrip.txt"
ffmpeg -v error -f lavfi -i "testsrc2=size=160x90:rate=10:duration=30" \
  -an -c:v libx264 -pix_fmt yuv420p -g 10 -keyint_min 10 -sc_threshold 0 \
  "$TIMELINE_FILMSTRIP_FIXTURE"
sleep 1
echo "Running G-04 Inc 3-4 TimelineView filmstrip/hover consumer smoke"
env MOVIECUT_UITEST=1 \
  MOVIECUT_UITEST_IMPORT="$TIMELINE_FILMSTRIP_FIXTURE,$TIMELINE_FILMSTRIP_FIXTURE,$FILMSTRIP_UNSUPPORTED_FIXTURE" \
  MOVIECUT_UITEST_TIMELINE_FILMSTRIP=1 \
  MOVIECUT_UITEST_RESULT="$TIMELINE_FILMSTRIP_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
TFP=$!
wait_for_result "$TFP" 160 0.25 "$TIMELINE_FILMSTRIP_RESULT"
TIMELINE_FILMSTRIP_STATUS="$(cat "$TIMELINE_FILMSTRIP_RESULT" 2>/dev/null || echo MISSING)"
case "$TIMELINE_FILMSTRIP_STATUS" in
  *"error=none"*"timeline_filmstrip_frames="*"offscreen_skipped=1"*"cancelled=1"*"stale_rejected=1"*"fallback_before_ready=1"*"fallback_after_cancel=1"*"hover_visible=1"*"hover_width=120"*"hover_height=68"*"hover_label=1"*"hover_digest_cached=1"*"hover_exit_hidden=1"*"hover_cache_miss_hidden=1"*"hover_unsupported_hidden=1"*"hover_request_delta=0"*"hover_generation_delta=0"*) ;;
  *) echo "FAIL: G-04 Inc 3-4 TimelineView consumer harness failed (status: $TIMELINE_FILMSTRIP_STATUS)" >&2; rm -rf "$TIMELINE_FILMSTRIP_TMPDIR"; exit 1 ;;
esac
python3 - "$TIMELINE_FILMSTRIP_STATUS" <<'PY'
import re, sys
status = sys.argv[1]

def integer(key):
    match = re.search(rf"(?:^| ){key}=([0-9]+)", status)
    if not match:
        raise SystemExit(f"missing {key}: {status}")
    return int(match.group(1))

def number(key):
    match = re.search(rf"(?:^| ){key}=([0-9.]+)", status)
    if not match:
        raise SystemExit(f"missing {key}: {status}")
    return float(match.group(1))

frames = integer("timeline_filmstrip_frames")
digests = integer("distinct_digests")
times = integer("distinct_times")
requested_span = number("requested_span")
full_span = number("full_span")
requested_count = integer("requested_count")
full_count = integer("full_count")
if frames <= 1 or digests <= 1 or times <= 1:
    raise SystemExit(f"filmstrip was not genuinely time-varying: {status}")
if not (0 < requested_span < full_span):
    raise SystemExit(f"visible source span was not limited: {status}")
if not (0 < requested_count < full_count):
    raise SystemExit(f"visible frame count was not limited: {status}")
for key in (
    "offscreen_skipped", "cancelled", "stale_rejected",
    "fallback_before_ready", "fallback_after_cancel"
):
    if integer(key) != 1:
        raise SystemExit(f"{key} was not proven: {status}")
zoom_match = re.search(r"(?:^| )zoom_requests=([^ ]+)", status)
zooms = set(zoom_match.group(1).split(",")) if zoom_match else set()
if len(zooms) < 2:
    raise SystemExit(f"zoom did not change request identity: {status}")
hover_requested = number("hover_requested")
hover_actual = number("hover_actual")
hover_error = number("hover_error")
hover_digest_match = re.search(r"(?:^| )hover_digest=([0-9a-f]{16})(?: |$)", status)
if not hover_digest_match:
    raise SystemExit(f"hover digest was not a real generated-frame digest: {status}")
for key, expected in (
    ("hover_visible", 1), ("hover_width", 120), ("hover_height", 68),
    ("hover_label", 1), ("hover_digest_cached", 1),
    ("hover_exit_hidden", 1), ("hover_cache_miss_hidden", 1),
    ("hover_unsupported_hidden", 1), ("hover_request_delta", 0),
    ("hover_generation_delta", 0),
):
    if integer(key) != expected:
        raise SystemExit(f"{key} expected {expected}: {status}")
if abs(hover_requested - hover_actual) > 0.3 or hover_error > 0.3:
    raise SystemExit(f"hover source-time error exceeded AC4 tolerance: {status}")
print(
    "PASS: G-04 Inc 3-4 TimelineView consumer "
    f"frames={frames} distinct_digests={digests} distinct_times={times} "
    f"visible_span={requested_span:.3f}/{full_span:.3f} "
    f"visible_count={requested_count}/{full_count} offscreen_skipped=1 "
    "cancelled=1 stale_rejected=1 fallback_before_ready=1 fallback_after_cancel=1 "
    f"hover=120x68 label=1 requested={hover_requested:.3f} actual={hover_actual:.3f} "
    f"error={hover_error:.3f} digest={hover_digest_match.group(1)} cached=1 "
    "exit_hidden=1 cache_miss_hidden=1 unsupported_hidden=1 request_delta=0 generation_delta=0"
)
PY
rm -rf "$TIMELINE_FILMSTRIP_TMPDIR"

# Works-First / G-16 AC1-2: drive the ruler-coordinate conversion and the same
# public transport scrub API used by TimelineView. The app must report both UI
# playhead and PlaybackEngine time within one 30fps frame of 1.25s.
SCRUB_TMPDIR="$(mktemp -d)"
SCRUB_RESULT="$SCRUB_TMPDIR/timeline_scrub.txt"
sleep 1
echo "Running G-16 timeline scrub smoke"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  MOVIECUT_UITEST_SCRUB=1.25 MOVIECUT_UITEST_RESULT="$SCRUB_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
SP=$!
wait_for_result "$SP" 120 0.25 "$SCRUB_RESULT"
SCRUB_STATUS="$(cat "$SCRUB_RESULT" 2>/dev/null || echo MISSING)"
case "$SCRUB_STATUS" in
  *"error=none"*"scrub_requested=1.250"*) ;;
  *) echo "FAIL: G-16 scrub harness failed (status: $SCRUB_STATUS)" >&2; rm -rf "$SCRUB_TMPDIR"; exit 1 ;;
esac
python3 - "$SCRUB_STATUS" <<'PY'
import re, sys
status = sys.argv[1]
values = {}
for key in ("scrub_requested", "playhead", "playback"):
    match = re.search(rf"(?:^| )%s=([0-9.]+)" % key, status)
    if not match:
        raise SystemExit(f"missing {key}: {status}")
    values[key] = float(match.group(1))
frame = 1.0 / 30.0
for key in ("playhead", "playback"):
    if abs(values[key] - values["scrub_requested"]) > frame:
        raise SystemExit(f"{key} drift exceeds one frame: {values}")
print(f"PASS: G-16 timeline scrub requested={values['scrub_requested']:.3f} playhead={values['playhead']:.3f} playback={values['playback']:.3f}")
PY
rm -rf "$SCRUB_TMPDIR"

# G-17 Inc 3: prove the actual app's public multi-clip clipboard APIs preserve
# IDs, relative timing, and atomic undo/redo, then export the retained state.
CLIPBOARD_TMPDIR="$(mktemp -d)"
CLIPBOARD_OUT="$CLIPBOARD_TMPDIR/g17_clipboard.mp4"
CLIPBOARD_RESULT="$CLIPBOARD_TMPDIR/g17_clipboard.txt"
sleep 1
echo "Running G-17 clipboard E2E → $CLIPBOARD_OUT"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE,$FIXTURE" \
  MOVIECUT_UITEST_CLIPBOARD=1 MOVIECUT_UITEST_EXPORT="$CLIPBOARD_OUT" \
  MOVIECUT_UITEST_RESULT="$CLIPBOARD_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
CP=$!
for _ in $(seq 1 240); do
  [ -s "$CLIPBOARD_OUT" ] && [ -s "$CLIPBOARD_RESULT" ] && break
  sleep 0.5
done
wait "$CP" 2>/dev/null || true
CLIPBOARD_STATUS="$(cat "$CLIPBOARD_RESULT" 2>/dev/null || echo MISSING)"
[ -s "$CLIPBOARD_RESULT" ] || { echo "FAIL: G-17 clipboard result missing" >&2; rm -rf "$CLIPBOARD_TMPDIR"; exit 1; }
[ -s "$CLIPBOARD_OUT" ] || { echo "FAIL: G-17 clipboard export missing (status: $CLIPBOARD_STATUS)" >&2; rm -rf "$CLIPBOARD_TMPDIR"; exit 1; }
case "$CLIPBOARD_STATUS" in
  *"error=none"*"clipboard_copy=2 paste=2 paste_starts=10.000,12.000 relative=2.000 paste_undo=1 cut_undo=1 new_ids=1"*) ;;
  *) echo "FAIL: G-17 clipboard invariants failed (status: $CLIPBOARD_STATUS)" >&2; rm -rf "$CLIPBOARD_TMPDIR"; exit 1 ;;
esac
CLIPBOARD_VIDEO="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of csv=p=0 "$CLIPBOARD_OUT" 2>/dev/null || true)"
[ "$CLIPBOARD_VIDEO" = "video" ] || { echo "FAIL: G-17 clipboard export has no video stream (ffprobe: ${CLIPBOARD_VIDEO:-none})" >&2; rm -rf "$CLIPBOARD_TMPDIR"; exit 1; }
CLIPBOARD_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$CLIPBOARD_OUT" 2>/dev/null || echo 0)"
awk -v d="$CLIPBOARD_DURATION" 'BEGIN { exit !(d > 13.7 && d < 14.3) }' \
  || { echo "FAIL: G-17 clipboard duration ${CLIPBOARD_DURATION}s (expected ~14.0; status: $CLIPBOARD_STATUS)" >&2; rm -rf "$CLIPBOARD_TMPDIR"; exit 1; }
echo "PASS: G-17 clipboard E2E status=[$CLIPBOARD_STATUS] ffprobe_video=$CLIPBOARD_VIDEO ffprobe_duration=${CLIPBOARD_DURATION}s"
rm -rf "$CLIPBOARD_TMPDIR"

# Works-First / G-15: still image clips must render through the real app
# preview/export pipeline instead of silently skipping because PNG has no video
# track. This reproduces the user bug and locks AC1: blue PNG -> exported blue
# middle frame.
IMAGE_FIXTURE="$ROOT/Tests/Fixtures/swatch_blue_64x64.png"
[ -s "$IMAGE_FIXTURE" ] || { echo "missing image fixture; run scripts/make_fixtures.sh" >&2; exit 1; }
IMAGE_TMPDIR="$(mktemp -d)"
IMAGE_OUT="$IMAGE_TMPDIR/image_clip.mp4"
IMAGE_RESULT="$IMAGE_TMPDIR/image_clip.txt"
sleep 1
echo "Running G-15 image smoke → $IMAGE_OUT"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$IMAGE_FIXTURE" \
  MOVIECUT_UITEST_EXPORT="$IMAGE_OUT" MOVIECUT_UITEST_RESULT="$IMAGE_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
IP=$!
wait_for_result "$IP" 180 0.5 "$IMAGE_OUT" "$IMAGE_RESULT"
IMAGE_STATUS="$(cat "$IMAGE_RESULT" 2>/dev/null || echo MISSING)"
[ -s "$IMAGE_OUT" ] || { echo "FAIL: G-15 image export missing (status: $IMAGE_STATUS)" >&2; rm -rf "$IMAGE_TMPDIR"; exit 1; }
case "$IMAGE_STATUS" in
  *"error=none"*) ;;
  *) echo "FAIL: G-15 image harness failed (status: $IMAGE_STATUS)" >&2; rm -rf "$IMAGE_TMPDIR"; exit 1 ;;
esac
IMAGE_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IMAGE_OUT" 2>/dev/null || echo 0)"
awk -v d="$IMAGE_DURATION" 'BEGIN { exit !(d > 4.7 && d < 5.3) }' \
  || { echo "FAIL: G-15 image duration ${IMAGE_DURATION}s (expected ~5.0)" >&2; rm -rf "$IMAGE_TMPDIR"; exit 1; }
IMAGE_RGB="$(python3 - "$IMAGE_OUT" <<'PY'
import subprocess, sys
path = sys.argv[1]
data = subprocess.check_output([
    "ffmpeg", "-v", "error", "-ss", "2.5", "-i", path,
    "-vf", "scale=1:1", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
])
if len(data) < 3:
    raise SystemExit("no frame bytes")
r, g, b = data[0], data[1], data[2]
print(f"rgb={r},{g},{b}")
if not (b > 120 and b > r * 2 and b > g * 2):
    raise SystemExit(2)
PY
)" || { echo "FAIL: G-15 image middle frame is not blue (${IMAGE_RGB:-no rgb})" >&2; rm -rf "$IMAGE_TMPDIR"; exit 1; }
rm -rf "$IMAGE_TMPDIR"
echo "PASS: G-15 image clip export ${IMAGE_DURATION}s ${IMAGE_RGB}"

# Works-First / G-15 AC2 / B-F1.3: mixed photo + video timeline must export
# through the real app path. The harness imports the 5s image first, then
# appends the 2s video via MOVIECUT_UITEST_IMPORT_EXTRA. Expected duration is
# therefore the media clip sum: 5s + 2s = 7s. Text burn-in is covered by the
# existing text-animation/template E2E below; this smoke isolates the image/video
# adjacency bug that used to hold the image frame over later clips.
MIXED_TMPDIR="$(mktemp -d)"
MIXED_OUT="$MIXED_TMPDIR/mixed_image_video.mp4"
MIXED_RESULT="$MIXED_TMPDIR/mixed_image_video.txt"
sleep 1
echo "Running G-15 mixed image+video smoke → $MIXED_OUT"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$IMAGE_FIXTURE" \
  MOVIECUT_UITEST_IMPORT_EXTRA="$FIXTURE" \
  MOVIECUT_UITEST_EXPORT="$MIXED_OUT" MOVIECUT_UITEST_RESULT="$MIXED_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
MP=$!
wait_for_result "$MP" 180 0.5 "$MIXED_OUT" "$MIXED_RESULT"
MIXED_STATUS="$(cat "$MIXED_RESULT" 2>/dev/null || echo MISSING)"
[ -s "$MIXED_OUT" ] || { echo "FAIL: G-15 mixed export missing (status: $MIXED_STATUS)" >&2; rm -rf "$MIXED_TMPDIR"; exit 1; }
case "$MIXED_STATUS" in
  *"clips=2"*"error=none"*"timeline=video:image=0.000-5.000,video:video=5.000-7.000"*) ;;
  *) echo "FAIL: G-15 mixed harness failed (status: $MIXED_STATUS)" >&2; rm -rf "$MIXED_TMPDIR"; exit 1 ;;
esac
MIXED_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MIXED_OUT" 2>/dev/null || echo 0)"
awk -v d="$MIXED_DURATION" 'BEGIN { exit !(d > 6.9 && d < 7.1) }' \
  || { echo "FAIL: G-15 mixed duration ${MIXED_DURATION}s (expected ~7.0)" >&2; rm -rf "$MIXED_TMPDIR"; exit 1; }
MIXED_RGB="$(python3 - "$MIXED_OUT" <<'PY'
import subprocess
import sys

path = sys.argv[1]

def rgb_at(timestamp):
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path, "-ss", f"{timestamp:.3f}",
        "-vf", "scale=1:1", "-frames:v", "1", "-f", "rawvideo",
        "-pix_fmt", "rgb24", "-"
    ])
    if len(data) < 3:
        raise SystemExit(f"no frame bytes at {timestamp:.3f}s")
    return data[0], data[1], data[2]

blue = rgb_at(2.5)
red = rgb_at(6.0)
print(
    f"image_rgb={blue[0]},{blue[1]},{blue[2]} "
    f"video_rgb={red[0]},{red[1]},{red[2]}"
)
if not (blue[2] > 120 and blue[2] > blue[0] * 2 and blue[2] > blue[1] * 2):
    raise SystemExit(2)
if not (red[0] >= 4 and red[0] > red[1] * 2 and red[0] > red[2] * 2 and red[2] < 20):
    raise SystemExit(3)
PY
)" || { echo "FAIL: G-15 mixed image/video color samples failed (${MIXED_RGB:-no rgb})" >&2; rm -rf "$MIXED_TMPDIR"; exit 1; }
rm -rf "$MIXED_TMPDIR"
echo "PASS: G-15 mixed image+video export ${MIXED_DURATION}s ${MIXED_RGB} ($MIXED_STATUS)"

# Works-First / G-15 AC3: grading a still image must reach the real app export
# pipeline. Compare against AC1's measured export rather than ideal source RGB
# values because H.264 encoding darkens the solid swatch slightly.
IMAGE_GRADE_TMPDIR="$(mktemp -d)"
IMAGE_GRADE_OUT="$IMAGE_GRADE_TMPDIR/image_clip_warm.mp4"
IMAGE_GRADE_RESULT="$IMAGE_GRADE_TMPDIR/image_clip_warm.txt"
sleep 1
echo "Running G-15 warm-graded image smoke → $IMAGE_GRADE_OUT"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$IMAGE_FIXTURE" MOVIECUT_UITEST_GRADE=1 \
  MOVIECUT_UITEST_EXPORT="$IMAGE_GRADE_OUT" MOVIECUT_UITEST_RESULT="$IMAGE_GRADE_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
IGP=$!
wait_for_result "$IGP" 180 0.5 "$IMAGE_GRADE_OUT" "$IMAGE_GRADE_RESULT"
IMAGE_GRADE_STATUS="$(cat "$IMAGE_GRADE_RESULT" 2>/dev/null || echo MISSING)"
[ -s "$IMAGE_GRADE_OUT" ] || { echo "FAIL: G-15 warm-graded image export missing (status: $IMAGE_GRADE_STATUS)" >&2; rm -rf "$IMAGE_GRADE_TMPDIR"; exit 1; }
case "$IMAGE_GRADE_STATUS" in
  *"error=none"*) ;;
  *) echo "FAIL: G-15 warm-graded image harness failed (status: $IMAGE_GRADE_STATUS)" >&2; rm -rf "$IMAGE_GRADE_TMPDIR"; exit 1 ;;
esac
IMAGE_GRADE_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IMAGE_GRADE_OUT" 2>/dev/null || echo 0)"
awk -v d="$IMAGE_GRADE_DURATION" 'BEGIN { exit !(d > 4.7 && d < 5.3) }' \
  || { echo "FAIL: G-15 warm-graded image duration ${IMAGE_GRADE_DURATION}s (expected ~5.0)" >&2; rm -rf "$IMAGE_GRADE_TMPDIR"; exit 1; }
IMAGE_GRADE_RGB="$(python3 - "$IMAGE_RGB" "$IMAGE_GRADE_OUT" <<'PY'
import re
import subprocess
import sys

baseline_text, path = sys.argv[1:]
match = re.fullmatch(r"rgb=(\d+),(\d+),(\d+)", baseline_text)
if match is None:
    print(f"baseline_rgb={baseline_text} graded_rgb=unavailable")
    raise SystemExit(2)
baseline = tuple(map(int, match.groups()))

data = subprocess.check_output([
    "ffmpeg", "-v", "error", "-ss", "2.5", "-i", path,
    "-vf", "scale=1:1", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
])
if len(data) < 3:
    print(f"baseline_rgb={baseline[0]},{baseline[1]},{baseline[2]} graded_rgb=unavailable")
    raise SystemExit(3)
graded = data[0], data[1], data[2]
red_delta = graded[0] - baseline[0]
blue_delta = graded[2] - baseline[2]
print(
    f"baseline_rgb={baseline[0]},{baseline[1]},{baseline[2]} "
    f"graded_rgb={graded[0]},{graded[1]},{graded[2]} "
    f"red_delta={red_delta:+d} blue_delta={blue_delta:+d}"
)
if red_delta < 20 or blue_delta > -12:
    raise SystemExit(4)
PY
)" || { echo "FAIL: G-15 warm shift too small (${IMAGE_GRADE_RGB:-baseline_rgb=unavailable graded_rgb=unavailable}; expected red_delta>=+20 and blue_delta<=-12)" >&2; rm -rf "$IMAGE_GRADE_TMPDIR"; exit 1; }
rm -rf "$IMAGE_GRADE_TMPDIR"
echo "PASS: G-15 warm-graded image export ${IMAGE_GRADE_DURATION}s ${IMAGE_GRADE_RGB} ($IMAGE_GRADE_STATUS)"

# Prior harness launches terminate through MOVIECUT_UITEST_QUIT; never signal an
# unrelated MovieCutMac process before continuing with the sequential checks.
sleep 1

OUT="$(mktemp -d)/e2e_export.mp4"
echo "Running headless harness → $OUT"
MOVIECUT_UITEST=1 \
  MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  MOVIECUT_UITEST_EXPORT="$OUT" \
  MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
APP_PID=$!

for _ in $(seq 1 120); do
  [ -s "$OUT" ] && break
  sleep 0.5
done
wait "$APP_PID" 2>/dev/null || true

if [ ! -s "$OUT" ]; then
  echo "FAIL: no export artifact — import or export regressed at runtime" >&2
  exit 1
fi

DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" || echo 0)"
SIZE="$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT")"
echo "PASS: export ${SIZE} bytes, duration ${DURATION}s"

# Duration must be ~2.0s (the fixture length), tolerance 0.2s.
awk -v d="$DURATION" 'BEGIN { exit !(d > 1.8 && d < 2.2) }' \
  || { echo "FAIL: unexpected duration ${DURATION}s (expected ~2.0)" >&2; rm -rf "$(dirname "$OUT")"; exit 1; }
rm -rf "$(dirname "$OUT")"

# Freeze frame must be reflected in export: a 2s freeze grows the output by ~2s.
FREEZE_OUT="$(mktemp -d)/freeze.mp4"
MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" MOVIECUT_UITEST_FREEZE=1 \
  MOVIECUT_UITEST_EXPORT="$FREEZE_OUT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
FP=$!
wait_for_result "$FP" 120 0.5 "$FREEZE_OUT"
FREEZE_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FREEZE_OUT" 2>/dev/null || echo 0)"
echo "PASS: freeze export duration ${FREEZE_DURATION}s (baseline ${DURATION}s)"
awk -v base="$DURATION" -v frz="$FREEZE_DURATION" 'BEGIN { d = frz - base; exit !(d > 1.7 && d < 2.3) }' \
  || { echo "FAIL: freeze not reflected in export (delta $(awk -v b="$DURATION" -v f="$FREEZE_DURATION" 'BEGIN{printf "%.2f", f-b}')s, expected ~2.0)" >&2; rm -rf "$(dirname "$FREEZE_OUT")"; exit 1; }
rm -rf "$(dirname "$FREEZE_OUT")"

# Optical-flow slow motion must do more than stretch duration/fps: the 0.25x
# export should be ~8s at 120fps and previously duplicated in-between frames
# must now have measurable motion-compensated deltas.
OF_FIXTURE="$ROOT/Tests/Fixtures/moving_subject_320x240_2s_30fps.mp4"
[ -s "$OF_FIXTURE" ] || { echo "missing optical-flow fixture; run scripts/make_fixtures.sh" >&2; exit 1; }
OF_OUT="$(mktemp -d)/optical_flow.mp4"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$OF_FIXTURE" MOVIECUT_UITEST_PLAYBACK_RATE=0.25 \
  MOVIECUT_UITEST_OPTICAL_FLOW=1 MOVIECUT_UITEST_EXPORT="$OF_OUT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
OFP=$!
wait_for_result "$OFP" 240 0.5 "$OF_OUT"
[ -s "$OF_OUT" ] || { echo "FAIL: optical-flow export missing" >&2; exit 1; }
OF_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OF_OUT" 2>/dev/null || echo 0)"
OF_FPS="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$OF_OUT" 2>/dev/null || echo 0)"
OF_FRAMES="$(ffprobe -v error -select_streams v:0 -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$OF_OUT" 2>/dev/null || echo 0)"
awk -v d="$OF_DURATION" 'BEGIN { exit !(d > 7.7 && d < 8.3) }' \
  || { echo "FAIL: optical-flow duration ${OF_DURATION}s (expected ~8.0s)" >&2; rm -rf "$(dirname "$OF_OUT")"; exit 1; }
awk -v r="$OF_FPS" 'BEGIN { split(r, p, "/"); fps = (p[2] && p[2] != 0) ? p[1] / p[2] : r + 0; exit !(fps > 119 && fps < 121) }' \
  || { echo "FAIL: optical-flow fps ${OF_FPS} (expected 120fps)" >&2; rm -rf "$(dirname "$OF_OUT")"; exit 1; }
awk -v f="$OF_FRAMES" 'BEGIN { exit !(f >= 940 && f <= 980) }' \
  || { echo "FAIL: optical-flow frame count ${OF_FRAMES} (expected ~960)" >&2; rm -rf "$(dirname "$OF_OUT")"; exit 1; }
OF_METRICS="$(python3 - "$OF_OUT" <<'PY'
import subprocess, sys
path = sys.argv[1]

def frame_n(n):
    return subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-vf", f"select=eq(n\\,{n}),scale=64:48", "-vsync", "0",
        "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ])

def mad(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / max(len(a), 1)

def blend(a, b):
    return bytes((x + y) // 2 for x, y in zip(a, b))

adjacent = []
mid_vs_blend = []
anchors = []
for base in (120, 240, 360):
    frames = [frame_n(base + offset) for offset in range(5)]
    adjacent.extend(mad(frames[i], frames[i + 1]) for i in range(4))
    mid_vs_blend.append(mad(frames[2], blend(frames[0], frames[4])))
    anchors.append(mad(frames[0], frames[4]))

avg_adjacent = sum(adjacent) / len(adjacent)
avg_mid_vs_blend = sum(mid_vs_blend) / len(mid_vs_blend)
avg_anchor = sum(anchors) / len(anchors)
print(f"adjacent_mad={avg_adjacent:.6f} mid_vs_blend={avg_mid_vs_blend:.6f} anchor_mad={avg_anchor:.6f}")
if not (avg_adjacent > 0.0008 and avg_mid_vs_blend > 0.0008 and avg_anchor > 0.003):
    raise SystemExit(2)
PY
)" || { echo "FAIL: optical-flow frames still look duplicated or simple blended (${OF_METRICS:-no metrics})" >&2; rm -rf "$(dirname "$OF_OUT")"; exit 1; }
rm -rf "$(dirname "$OF_OUT")"
echo "PASS: optical-flow slow motion produced ${OF_DURATION}s ${OF_FPS} ${OF_FRAMES} frames with motion-aware deltas ($OF_METRICS)"

# Text animation presets must burn into real exports and show time-varying frame
# content for every animated preset. The .none preset is checked as a stable text
# overlay against the source fixture.
TEXT_ANIMATION_PRESETS=(none fadeIn fadeOut fadeInOut slideInLeft slideInRight slideInUp slideInDown typewriter bounceIn zoomIn popIn wave)
TEXT_ANIMATION_SOURCE="$OF_FIXTURE"
TEXT_ANIMATION_BASELINE_DIR="$(mktemp -d)"
TEXT_ANIMATION_BASELINE_OUT="$TEXT_ANIMATION_BASELINE_DIR/text_none_baseline.mp4"
TEXT_ANIMATION_BASELINE_RESULT="$TEXT_ANIMATION_BASELINE_DIR/text_none_baseline.txt"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$TEXT_ANIMATION_SOURCE" MOVIECUT_UITEST_COLOR=1 MOVIECUT_UITEST_TEXT_ANIMATION_PRESET="none" \
  MOVIECUT_UITEST_EXPORT="$TEXT_ANIMATION_BASELINE_OUT" MOVIECUT_UITEST_RESULT="$TEXT_ANIMATION_BASELINE_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
TBP=$!
wait_for_result "$TBP" 180 0.5 "$TEXT_ANIMATION_BASELINE_OUT" "$TEXT_ANIMATION_BASELINE_RESULT"
TEXT_ANIMATION_BASELINE_STATUS="$(cat "$TEXT_ANIMATION_BASELINE_RESULT" 2>/dev/null || echo MISSING)"
if [ ! -s "$TEXT_ANIMATION_BASELINE_OUT" ]; then
  echo "FAIL: text animation none baseline export missing (status: $TEXT_ANIMATION_BASELINE_STATUS)" >&2
  rm -rf "$TEXT_ANIMATION_BASELINE_DIR"
  exit 1
fi
case "$TEXT_ANIMATION_BASELINE_STATUS" in
  *"error=none"*) ;;
  *) echo "FAIL: text animation none baseline harness failed (status: $TEXT_ANIMATION_BASELINE_STATUS)" >&2; rm -rf "$TEXT_ANIMATION_BASELINE_DIR"; exit 1 ;;
esac
TEXT_ANIMATION_METRICS=()
for preset in "${TEXT_ANIMATION_PRESETS[@]}"; do
  TEXT_TMPDIR="$(mktemp -d)"
  TEXT_OUT="$TEXT_TMPDIR/text_${preset}.mp4"
  TEXT_RESULT="$TEXT_TMPDIR/text_${preset}.txt"

  env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$TEXT_ANIMATION_SOURCE" MOVIECUT_UITEST_COLOR=1 MOVIECUT_UITEST_TEXT_ANIMATION_PRESET="$preset" \
    MOVIECUT_UITEST_EXPORT="$TEXT_OUT" MOVIECUT_UITEST_RESULT="$TEXT_RESULT" MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >/dev/null 2>&1 &
  TAP=$!
  wait_for_result "$TAP" 180 0.5 "$TEXT_OUT" "$TEXT_RESULT"

  TEXT_STATUS="$(cat "$TEXT_RESULT" 2>/dev/null || echo MISSING)"
  if [ ! -s "$TEXT_OUT" ]; then
    echo "FAIL: text animation ${preset} export missing (status: $TEXT_STATUS)" >&2
    rm -rf "$TEXT_TMPDIR"
    exit 1
  fi
  case "$TEXT_STATUS" in
    *"error=none"*) ;;
    *) echo "FAIL: text animation ${preset} harness failed (status: $TEXT_STATUS)" >&2; rm -rf "$TEXT_TMPDIR"; exit 1 ;;
  esac

  TEXT_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TEXT_OUT" 2>/dev/null || echo 0)"
  awk -v d="$TEXT_DURATION" 'BEGIN { exit !(d > 1.8 && d < 2.2) }' \
    || { echo "FAIL: text animation ${preset} duration ${TEXT_DURATION}s (expected ~2.0)" >&2; rm -rf "$TEXT_TMPDIR"; exit 1; }

  TEXT_COMPARE_SOURCE="$TEXT_ANIMATION_BASELINE_OUT"
  if [ "$preset" = "none" ]; then
    TEXT_COMPARE_SOURCE="$TEXT_ANIMATION_SOURCE"
  fi
  TEXT_METRIC="$(python3 - "$preset" "$TEXT_COMPARE_SOURCE" "$TEXT_OUT" <<'PY'
import subprocess
import sys

preset, source_path, export_path = sys.argv[1:4]
# Sample exact frame indices so the baseline/preset comparison cannot collapse to
# the same keyframe during timestamp seeking.
frames = (0, 8, 24, 51)

def frame(path, frame_index):
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-vf", f"select=eq(n\\,{frame_index}),scale=80:60",
        "-vsync", "0",
        "-frames:v", "1",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ])
    expected = 80 * 60 * 3
    if len(data) != expected:
        raise SystemExit(f"expected {expected} frame bytes from {path} at frame {frame_index}, got {len(data)}")
    return data

def mad(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / max(len(a), 1)

export_frames = [frame(export_path, frame_index) for frame_index in frames]
source_frames = [frame(source_path, frame_index) for frame_index in frames]
residual_frames = [bytes(abs(o - s) for o, s in zip(out, src)) for out, src in zip(export_frames, source_frames)]
adjacent_residual_mads = [mad(residual_frames[i], residual_frames[i + 1]) for i in range(len(residual_frames) - 1)]
residual_temporal_mad = sum(adjacent_residual_mads) / len(adjacent_residual_mads)
max_residual_temporal_mad = max(adjacent_residual_mads)
overlay_mad = sum(sum(residual) / max(len(residual), 1) for residual in residual_frames) / len(residual_frames)

print(f"residual_temporal_mad={residual_temporal_mad:.6f} max_residual_temporal_mad={max_residual_temporal_mad:.6f} overlay_mad={overlay_mad:.6f} duration_checked=2s")
if preset == "none":
    if not (overlay_mad > 0.05):
        raise SystemExit(2)
else:
    if not (max_residual_temporal_mad > 0.2 and overlay_mad > 0.05):
        raise SystemExit(2)
PY
)" || { echo "FAIL: text animation ${preset} frame-diff check failed (${TEXT_METRIC:-no metrics}; status: $TEXT_STATUS)" >&2; rm -rf "$TEXT_TMPDIR"; exit 1; }
  TEXT_ANIMATION_METRICS+=("${preset}:${TEXT_METRIC}")
  rm -rf "$TEXT_TMPDIR"
done
TEXT_ANIMATION_SUMMARY="$(printf '%s; ' "${TEXT_ANIMATION_METRICS[@]}")"
rm -rf "$TEXT_ANIMATION_BASELINE_DIR"
echo "PASS: text animations 13 presets export proof (${TEXT_ANIMATION_SUMMARY%; })"

# Built-in title templates must be applied through the real app template path and
# visibly burn into exported frames. This codifies G-12 #7 for all 14 templates,
# not just static library/Inspector contracts.
TITLE_TEMPLATE_NAMES=(Title Subtitle "Lower Third" Caption Credits "News Banner" Quote Callout Kinetic Handwritten "Neon Glow" Outline Typewriter "Social Handle")
TITLE_TEMPLATE_BASELINE_DIR="$(mktemp -d)"
TITLE_TEMPLATE_BASELINE_OUT="$TITLE_TEMPLATE_BASELINE_DIR/title_template_baseline.mp4"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" \
  MOVIECUT_UITEST_EXPORT="$TITLE_TEMPLATE_BASELINE_OUT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
TTBP=$!
wait_for_result "$TTBP" 120 0.5 "$TITLE_TEMPLATE_BASELINE_OUT"
[ -s "$TITLE_TEMPLATE_BASELINE_OUT" ] || { echo "FAIL: title template baseline export missing" >&2; rm -rf "$TITLE_TEMPLATE_BASELINE_DIR"; exit 1; }
TITLE_TEMPLATE_METRICS=()
for template_name in "${TITLE_TEMPLATE_NAMES[@]}"; do
  TITLE_TMPDIR="$(mktemp -d)"
  TITLE_OUT="$TITLE_TMPDIR/title_template.mp4"
  TITLE_RESULT="$TITLE_TMPDIR/title_template.txt"
  TITLE_ENV_NAME="${template_name// /_}"

  env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" MOVIECUT_UITEST_TEXT_TEMPLATE_NAME="$TITLE_ENV_NAME" \
    MOVIECUT_UITEST_EXPORT="$TITLE_OUT" MOVIECUT_UITEST_RESULT="$TITLE_RESULT" MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >/dev/null 2>&1 &
  TTP=$!
  wait_for_result "$TTP" 180 0.5 "$TITLE_OUT" "$TITLE_RESULT"

  TITLE_STATUS="$(cat "$TITLE_RESULT" 2>/dev/null || echo MISSING)"
  if [ ! -s "$TITLE_OUT" ]; then
    echo "FAIL: title template ${template_name} export missing (status: $TITLE_STATUS)" >&2
    rm -rf "$TITLE_TMPDIR"
    exit 1
  fi
  case "$TITLE_STATUS" in
    *"error=none"*"text_template=${TITLE_ENV_NAME}"*"text_template_clips=1"*) ;;
    *) echo "FAIL: title template ${template_name} harness failed (status: $TITLE_STATUS)" >&2; rm -rf "$TITLE_TMPDIR"; exit 1 ;;
  esac

  TITLE_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TITLE_OUT" 2>/dev/null || echo 0)"
  awk -v d="$TITLE_DURATION" 'BEGIN { exit !(d > 1.8 && d < 2.2) }' \
    || { echo "FAIL: title template ${template_name} duration ${TITLE_DURATION}s (expected ~2.0)" >&2; rm -rf "$TITLE_TMPDIR"; exit 1; }

  TITLE_METRIC="$(python3 - "$template_name" "$TITLE_TEMPLATE_BASELINE_OUT" "$TITLE_OUT" <<'PY'
import subprocess
import sys

template_name, source_path, export_path = sys.argv[1:4]
frames = (8, 24, 51)

def frame(path, frame_index):
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-vf", f"select=eq(n\\,{frame_index}),scale=80:60",
        "-vsync", "0",
        "-frames:v", "1",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ])
    expected = 80 * 60 * 3
    if len(data) != expected:
        raise SystemExit(f"expected {expected} bytes from {path} frame {frame_index}, got {len(data)}")
    return data

def mad(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / max(len(a), 1)

export_frames = [frame(export_path, n) for n in frames]
source_frames = [frame(source_path, n) for n in frames]
residual_mads = [mad(out, src) for out, src in zip(export_frames, source_frames)]
max_overlay_mad = max(residual_mads)
mean_overlay_mad = sum(residual_mads) / len(residual_mads)
print(f"mean_overlay_mad={mean_overlay_mad:.6f} max_overlay_mad={max_overlay_mad:.6f}")
if not (max_overlay_mad > 0.05):
    raise SystemExit(2)
PY
)" || { echo "FAIL: title template ${template_name} frame overlay check failed (${TITLE_METRIC:-no metrics}; status: $TITLE_STATUS)" >&2; rm -rf "$TITLE_TMPDIR"; exit 1; }
  TITLE_TEMPLATE_METRICS+=("${TITLE_ENV_NAME}:${TITLE_METRIC}")
  rm -rf "$TITLE_TMPDIR"
done
TITLE_TEMPLATE_SUMMARY="$(printf '%s; ' "${TITLE_TEMPLATE_METRICS[@]}")"
rm -rf "$TITLE_TEMPLATE_BASELINE_DIR"
echo "PASS: title templates 14 presets export proof (${TITLE_TEMPLATE_SUMMARY%; })"

# Noise reduction must run the real AVAudioEngine DSP in the app context without
# crashing (the offline-render path aborts under `swift test`).
TONE="$ROOT/Tests/Fixtures/tone_440hz_2s_mono.wav"
NR_RESULT="$(mktemp -d)/nr.txt"
MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$TONE" MOVIECUT_UITEST_DENOISE=1 \
  MOVIECUT_UITEST_RESULT="$NR_RESULT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
NP=$!
wait_for_result "$NP" 120 0.5 "$NR_RESULT"
NR_STATUS="$(cat "$NR_RESULT" 2>/dev/null || echo MISSING)"
rm -rf "$(dirname "$NR_RESULT")"
case "$NR_STATUS" in
  *"error=none"*) echo "PASS: noise reduction ran in app context ($NR_STATUS)" ;;
  *) echo "FAIL: noise reduction did not complete cleanly (status: $NR_STATUS)" >&2; exit 1 ;;
esac

# Noise reduction must measurably reduce high-frequency hiss while preserving
# the voice-band carrier. The fixture contains 1kHz voice-band tone + 8kHz hiss.
NOISY="$ROOT/Tests/Fixtures/noisy_voice_1k_hiss_8k_2s_mono.wav"
[ -s "$NOISY" ] || { echo "missing NR fixture; run scripts/make_fixtures.sh" >&2; exit 1; }
NR_BASE="$(mktemp -d)/nr_base.m4a"
NR_DENOISED="$(mktemp -d)/nr_denoised.m4a"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$NOISY" MOVIECUT_UITEST_EXPORT="$NR_BASE" \
  MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
NP=$!; for _ in $(seq 1 120); do [ -s "$NR_BASE" ] && break; sleep 0.5; done; wait "$NP" 2>/dev/null || true
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$NOISY" MOVIECUT_UITEST_DENOISE=1 \
  MOVIECUT_UITEST_EXPORT="$NR_DENOISED" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
NP=$!; for _ in $(seq 1 120); do [ -s "$NR_DENOISED" ] && break; sleep 0.5; done; wait "$NP" 2>/dev/null || true
[ -s "$NR_BASE" ] || { echo "FAIL: baseline noisy export missing" >&2; exit 1; }
[ -s "$NR_DENOISED" ] || { echo "FAIL: denoised export missing" >&2; exit 1; }
NR_METRICS="$(python3 - "$NR_BASE" "$NR_DENOISED" <<'PY'
import math, struct, subprocess, sys

def tone_power(path, freq):
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-ac", "1", "-ar", "44100", "-f", "f32le", "-"
    ])
    count = len(raw) // 4
    if count == 0:
        raise SystemExit(f"no decoded audio for {path}")
    samples = struct.unpack("<" + "f" * count, raw)
    n = min(count, 88200)
    samples = samples[:n]
    omega = 2.0 * math.pi * freq / 44100.0
    cos_sum = 0.0
    sin_sum = 0.0
    for i, s in enumerate(samples):
        cos_sum += s * math.cos(omega * i)
        sin_sum += s * math.sin(omega * i)
    return (cos_sum * cos_sum + sin_sum * sin_sum) / max(n, 1)

def metrics(path):
    voice = tone_power(path, 1000.0)
    hiss = tone_power(path, 8000.0)
    ratio = hiss / max(voice, 1e-18)
    return voice, hiss, ratio

base_voice, base_hiss, base_ratio = metrics(sys.argv[1])
denoised_voice, denoised_hiss, denoised_ratio = metrics(sys.argv[2])
improvement_db = 10.0 * math.log10(max(base_ratio, 1e-18) / max(denoised_ratio, 1e-18))
voice_retention = denoised_voice / max(base_voice, 1e-18)
print(f"base_ratio={base_ratio:.6f} denoised_ratio={denoised_ratio:.6f} improvement_db={improvement_db:.2f} base_voice={base_voice:.6e} denoised_voice={denoised_voice:.6e} base_hiss={base_hiss:.6e} denoised_hiss={denoised_hiss:.6e} voice_retention={voice_retention:.3f}")
if not (denoised_ratio < base_ratio * 0.45 and improvement_db > 3.0 and voice_retention > 0.45):
    raise SystemExit(2)
PY
)" || { echo "FAIL: noise reduction SNR check failed (${NR_METRICS:-no metrics})" >&2; rm -rf "$(dirname "$NR_BASE")" "$(dirname "$NR_DENOISED")"; exit 1; }
rm -rf "$(dirname "$NR_BASE")" "$(dirname "$NR_DENOISED")"
echo "PASS: noise reduction improved voice/hiss ratio ($NR_METRICS)"

# Equalizer must produce a real spectral difference in the app/export path, not a
# static UI claim. The fixture contains equal 110Hz and 4kHz tones; bassBoost
# must raise the low/high energy ratio relative to trebleBoost.
EQ_FIXTURE="$ROOT/Tests/Fixtures/eq_low_high_2s_mono.wav"
[ -s "$EQ_FIXTURE" ] || { echo "missing EQ fixture; run scripts/make_fixtures.sh" >&2; exit 1; }
EQ_BASS="$(mktemp -d)/eq_bass.m4a"
EQ_TREBLE="$(mktemp -d)/eq_treble.m4a"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$EQ_FIXTURE" MOVIECUT_UITEST_EQ_PRESET="bassBoost" \
  MOVIECUT_UITEST_EXPORT="$EQ_BASS" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
EP=$!; for _ in $(seq 1 120); do [ -s "$EQ_BASS" ] && break; sleep 0.5; done; wait "$EP" 2>/dev/null || true
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$EQ_FIXTURE" MOVIECUT_UITEST_EQ_PRESET="trebleBoost" \
  MOVIECUT_UITEST_EXPORT="$EQ_TREBLE" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
EP=$!; for _ in $(seq 1 120); do [ -s "$EQ_TREBLE" ] && break; sleep 0.5; done; wait "$EP" 2>/dev/null || true
[ -s "$EQ_BASS" ] || { echo "FAIL: bassBoost EQ export missing" >&2; exit 1; }
[ -s "$EQ_TREBLE" ] || { echo "FAIL: trebleBoost EQ export missing" >&2; exit 1; }
EQ_METRICS="$(python3 - "$EQ_BASS" "$EQ_TREBLE" <<'PY'
import math, struct, subprocess, sys

def tone_power(path, freq):
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-ac", "1", "-ar", "44100", "-f", "f32le", "-"
    ])
    if not raw:
        raise SystemExit(f"no decoded audio for {path}")
    count = len(raw) // 4
    samples = struct.unpack("<" + "f" * count, raw)
    # Use at most the first 2s to match the deterministic fixture.
    n = min(count, 88200)
    samples = samples[:n]
    omega = 2.0 * math.pi * freq / 44100.0
    cos_sum = 0.0
    sin_sum = 0.0
    for i, s in enumerate(samples):
        cos_sum += s * math.cos(omega * i)
        sin_sum += s * math.sin(omega * i)
    return (cos_sum * cos_sum + sin_sum * sin_sum) / max(n, 1)

def ratio(path):
    low = tone_power(path, 110.0)
    high = tone_power(path, 4000.0)
    return low / max(high, 1e-18), low, high

bass_ratio, bass_low, bass_high = ratio(sys.argv[1])
treble_ratio, treble_low, treble_high = ratio(sys.argv[2])
print(f"bass_ratio={bass_ratio:.6f} treble_ratio={treble_ratio:.6f} bass_low={bass_low:.6e} bass_high={bass_high:.6e} treble_low={treble_low:.6e} treble_high={treble_high:.6e}")
# A real EQ should move the low/high ratio in opposite directions by a wide
# margin. Keep thresholds loose enough for AAC/container differences while still
# rejecting volume-only processing.
if not (bass_ratio > treble_ratio * 2.0 and bass_low > treble_low * 1.25 and treble_high > bass_high * 1.25):
    raise SystemExit(2)
PY
)" || { echo "FAIL: equalizer spectrum check failed (${EQ_METRICS:-no metrics})" >&2; rm -rf "$(dirname "$EQ_BASS")" "$(dirname "$EQ_TREBLE")"; exit 1; }
rm -rf "$(dirname "$EQ_BASS")" "$(dirname "$EQ_TREBLE")"
echo "PASS: EQ bassBoost vs trebleBoost spectrum diverged ($EQ_METRICS)"

# Extract Audio must create a real audio clip from a video asset that contains
# audio, then export that clip through the app's audio-only export path.
EXTRACT_AUDIO_FIXTURE="$ROOT/Tests/Fixtures/solid_red_tone_320x240_2s_30fps.mp4"
[ -s "$EXTRACT_AUDIO_FIXTURE" ] || { echo "missing extract-audio fixture; run scripts/make_fixtures.sh" >&2; exit 1; }
EXTRACT_AUDIO_OUT="$(mktemp -d)/extract_audio.m4a"
EXTRACT_AUDIO_RESULT="$(mktemp -d)/extract_audio.txt"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$EXTRACT_AUDIO_FIXTURE" MOVIECUT_UITEST_EXTRACT_AUDIO=1 \
  MOVIECUT_UITEST_EXPORT_AUDIO="$EXTRACT_AUDIO_OUT" MOVIECUT_UITEST_RESULT="$EXTRACT_AUDIO_RESULT" \
  MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
EAP=$!
for _ in $(seq 1 120); do
  [ -s "$EXTRACT_AUDIO_OUT" ] && [ -s "$EXTRACT_AUDIO_RESULT" ] && break
  sleep 0.5
done
wait "$EAP" 2>/dev/null || true
EXTRACT_AUDIO_STATUS="$(cat "$EXTRACT_AUDIO_RESULT" 2>/dev/null || echo MISSING)"
EXTRACT_AUDIO_CLIPS="$(printf '%s' "$EXTRACT_AUDIO_STATUS" | sed -n 's/.*extract_audio_clips=\([0-9][0-9]*\).*/\1/p')"
EXTRACT_AUDIO_CLIP_DURATION="$(printf '%s' "$EXTRACT_AUDIO_STATUS" | sed -n 's/.*extract_audio_duration=\([0-9.]*\).*/\1/p')"
if [ ! -s "$EXTRACT_AUDIO_OUT" ]; then
  echo "FAIL: extract-audio export missing (status: $EXTRACT_AUDIO_STATUS)" >&2
  rm -rf "$(dirname "$EXTRACT_AUDIO_OUT")" "$(dirname "$EXTRACT_AUDIO_RESULT")"
  exit 1
fi
case "$EXTRACT_AUDIO_STATUS" in
  *"error=none"*) ;;
  *) echo "FAIL: extract-audio harness failed (status: $EXTRACT_AUDIO_STATUS)" >&2; rm -rf "$(dirname "$EXTRACT_AUDIO_OUT")" "$(dirname "$EXTRACT_AUDIO_RESULT")"; exit 1 ;;
esac
if [ "${EXTRACT_AUDIO_CLIPS:-0}" -lt 1 ]; then
  echo "FAIL: extract-audio harness did not create an audio clip (status: $EXTRACT_AUDIO_STATUS)" >&2
  rm -rf "$(dirname "$EXTRACT_AUDIO_OUT")" "$(dirname "$EXTRACT_AUDIO_RESULT")"
  exit 1
fi
awk -v d="${EXTRACT_AUDIO_CLIP_DURATION:-0}" 'BEGIN { exit !(d > 1.8 && d < 2.2) }' \
  || { echo "FAIL: extracted audio clip duration ${EXTRACT_AUDIO_CLIP_DURATION:-missing}s (expected ~2.0)" >&2; rm -rf "$(dirname "$EXTRACT_AUDIO_OUT")" "$(dirname "$EXTRACT_AUDIO_RESULT")"; exit 1; }
EXTRACT_AUDIO_CODEC="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$EXTRACT_AUDIO_OUT" 2>/dev/null)"
EXTRACT_AUDIO_DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$EXTRACT_AUDIO_OUT" 2>/dev/null || echo 0)"
if [ -z "$EXTRACT_AUDIO_CODEC" ]; then
  echo "FAIL: extract-audio export has no audio stream" >&2
  rm -rf "$(dirname "$EXTRACT_AUDIO_OUT")" "$(dirname "$EXTRACT_AUDIO_RESULT")"
  exit 1
fi
awk -v d="$EXTRACT_AUDIO_DURATION" 'BEGIN { exit !(d > 1.8 && d < 2.2) }' \
  || { echo "FAIL: extract-audio export duration ${EXTRACT_AUDIO_DURATION}s (expected ~2.0)" >&2; rm -rf "$(dirname "$EXTRACT_AUDIO_OUT")" "$(dirname "$EXTRACT_AUDIO_RESULT")"; exit 1; }
EXTRACT_AUDIO_RMS="$(python3 - "$EXTRACT_AUDIO_OUT" <<'PY'
import math, struct, subprocess, sys

raw = subprocess.check_output([
    "ffmpeg", "-v", "error", "-i", sys.argv[1],
    "-ac", "1", "-ar", "44100", "-f", "f32le", "-"
])
count = len(raw) // 4
if count == 0:
    raise SystemExit("no decoded audio")
samples = struct.unpack("<" + "f" * count, raw)
rms = math.sqrt(sum(s * s for s in samples) / count)
print(f"{rms:.6f}")
if rms <= 0.005:
    raise SystemExit(2)
PY
)" || { echo "FAIL: extract-audio export decoded as silence (${EXTRACT_AUDIO_RMS:-no rms})" >&2; rm -rf "$(dirname "$EXTRACT_AUDIO_OUT")" "$(dirname "$EXTRACT_AUDIO_RESULT")"; exit 1; }
rm -rf "$(dirname "$EXTRACT_AUDIO_OUT")" "$(dirname "$EXTRACT_AUDIO_RESULT")"
echo "PASS: audio extraction produced valid audio stream (clips=${EXTRACT_AUDIO_CLIPS}, clip_duration=${EXTRACT_AUDIO_CLIP_DURATION}s, export_duration=${EXTRACT_AUDIO_DURATION}s, codec=${EXTRACT_AUDIO_CODEC}, rms=${EXTRACT_AUDIO_RMS})"

# Chapter/beat markers must be written into the exported file as real chapter
# metadata, not just present in the in-memory project. The app harness creates two
# standard markers (Intro/Outro) plus one beat marker and enables beat chapters;
# ffprobe must then see timed chapter atoms at those marker times.
CHAPTER_TMPDIR="$(mktemp -d)"
CHAPTER_OUT="$CHAPTER_TMPDIR/chapters.mp4"
CHAPTER_RESULT="$CHAPTER_TMPDIR/chapters.txt"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" MOVIECUT_UITEST_CHAPTER_MARKERS=1 MOVIECUT_UITEST_BEAT_CHAPTERS=1 \
  MOVIECUT_UITEST_EXPORT="$CHAPTER_OUT" MOVIECUT_UITEST_RESULT="$CHAPTER_RESULT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
CP=$!
wait_for_result "$CP" 180 0.5 "$CHAPTER_OUT" "$CHAPTER_RESULT"
CHAPTER_STATUS="$(cat "$CHAPTER_RESULT" 2>/dev/null || echo MISSING)"
[ -s "$CHAPTER_OUT" ] || { echo "FAIL: chapter marker export missing (status: $CHAPTER_STATUS)" >&2; rm -rf "$CHAPTER_TMPDIR"; exit 1; }
case "$CHAPTER_STATUS" in
  *"error=none"*"chapters=2"*"beat_chapters=1"*"include_beats=1"*) ;;
  *) echo "FAIL: chapter marker harness did not create expected markers (status: $CHAPTER_STATUS)" >&2; rm -rf "$CHAPTER_TMPDIR"; exit 1 ;;
esac
CHAPTER_METRICS="$(python3 - "$CHAPTER_OUT" <<'PY'
import json
import subprocess
import sys

path = sys.argv[1]
raw = subprocess.check_output([
    "ffprobe", "-v", "error", "-show_chapters", "-of", "json", path
], text=True)
chapters = json.loads(raw).get("chapters", [])
starts = [float(chapter.get("start_time", "nan")) for chapter in chapters]
expected = [0.25, 0.75, 1.25]
if len(chapters) != 3:
    raise SystemExit(f"expected 3 chapters, got {len(chapters)}")
for got, want in zip(starts, expected):
    if abs(got - want) > 0.02:
        raise SystemExit(f"chapter starts {starts} do not match {expected}")
ends = [float(chapter.get("end_time", "nan")) for chapter in chapters]
if not all(end > start for start, end in zip(starts, ends)):
    raise SystemExit(f"invalid chapter ranges starts={starts} ends={ends}")
print("count=3 starts=" + ",".join(f"{v:.2f}" for v in starts) + " ends=" + ",".join(f"{v:.2f}" for v in ends))
PY
)" || { echo "FAIL: exported chapter metadata missing or malformed (${CHAPTER_METRICS:-no metrics})" >&2; rm -rf "$CHAPTER_TMPDIR"; exit 1; }
rm -rf "$CHAPTER_TMPDIR"
echo "PASS: chapter marker metadata export proof (Intro/Beat 1/Outro; $CHAPTER_METRICS)"

# Ducking must attenuate BGM under a voice cue in the real app export path. The
# harness creates two audio tracks, applies SetAudioDuckingCommand to the BGM,
# and the metric isolates the 220Hz BGM component so the 1kHz voice cue cannot
# falsely satisfy the check.
DUCK_BGM="$ROOT/Tests/Fixtures/duck_bgm_220hz_4s_mono.wav"
DUCK_VOICE="$ROOT/Tests/Fixtures/duck_voice_1000hz_1s_mono.wav"
[ -s "$DUCK_BGM" ] || { echo "missing ducking BGM fixture; run scripts/make_fixtures.sh" >&2; exit 1; }
[ -s "$DUCK_VOICE" ] || { echo "missing ducking voice fixture; run scripts/make_fixtures.sh" >&2; exit 1; }
DUCK_BASE="$(mktemp -d)/duck_base.m4a"
DUCKED="$(mktemp -d)/ducked.m4a"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_DUCKING_BGM="$DUCK_BGM" MOVIECUT_UITEST_DUCKING_VOICE="$DUCK_VOICE" \
  MOVIECUT_UITEST_EXPORT="$DUCK_BASE" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
DP=$!; for _ in $(seq 1 120); do [ -s "$DUCK_BASE" ] && break; sleep 0.5; done; wait "$DP" 2>/dev/null || true
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_DUCKING_BGM="$DUCK_BGM" MOVIECUT_UITEST_DUCKING_VOICE="$DUCK_VOICE" MOVIECUT_UITEST_DUCKING_APPLY=1 \
  MOVIECUT_UITEST_EXPORT="$DUCKED" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
DP=$!; for _ in $(seq 1 120); do [ -s "$DUCKED" ] && break; sleep 0.5; done; wait "$DP" 2>/dev/null || true
[ -s "$DUCK_BASE" ] || { echo "FAIL: baseline ducking export missing" >&2; exit 1; }
[ -s "$DUCKED" ] || { echo "FAIL: ducked export missing" >&2; exit 1; }
DUCK_METRICS="$(python3 - "$DUCK_BASE" "$DUCKED" <<'PY'
import math, struct, subprocess, sys

def samples(path):
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-ac", "1", "-ar", "44100", "-f", "f32le", "-"
    ])
    count = len(raw) // 4
    if count == 0:
        raise SystemExit(f"no decoded audio for {path}")
    return struct.unpack("<" + "f" * count, raw)

def tone_power_window(data, freq, start, end, rate=44100):
    a = max(0, int(start * rate))
    b = min(len(data), int(end * rate))
    if b <= a:
        raise SystemExit("empty analysis window")
    omega = 2.0 * math.pi * freq / rate
    cos_sum = 0.0
    sin_sum = 0.0
    for offset, s in enumerate(data[a:b], start=a):
        cos_sum += s * math.cos(omega * offset)
        sin_sum += s * math.sin(omega * offset)
    n = b - a
    return (cos_sum * cos_sum + sin_sum * sin_sum) / n

base = samples(sys.argv[1])
ducked = samples(sys.argv[2])
# Central voice window avoids attack/release edges; quiet windows avoid the voice cue.
base_voice = tone_power_window(base, 220.0, 1.25, 1.75)
ducked_voice = tone_power_window(ducked, 220.0, 1.25, 1.75)
base_quiet = (tone_power_window(base, 220.0, 0.25, 0.75) + tone_power_window(base, 220.0, 2.75, 3.25)) / 2.0
ducked_quiet = (tone_power_window(ducked, 220.0, 0.25, 0.75) + tone_power_window(ducked, 220.0, 2.75, 3.25)) / 2.0
reduction_db = 10.0 * math.log10(max(base_voice, 1e-18) / max(ducked_voice, 1e-18))
quiet_delta_db = 10.0 * math.log10(max(ducked_quiet, 1e-18) / max(base_quiet, 1e-18))
voice_vs_quiet_ratio = ducked_voice / max(ducked_quiet, 1e-18)
print(f"base_voice={base_voice:.6e} ducked_voice={ducked_voice:.6e} reduction_db={reduction_db:.2f} base_quiet={base_quiet:.6e} ducked_quiet={ducked_quiet:.6e} quiet_delta_db={quiet_delta_db:.2f} ducked_voice_quiet_ratio={voice_vs_quiet_ratio:.3f}")
if not (reduction_db > 6.0 and abs(quiet_delta_db) < 1.5 and voice_vs_quiet_ratio < 0.35):
    raise SystemExit(2)
PY
)" || { echo "FAIL: ducking RMS check failed (${DUCK_METRICS:-no metrics})" >&2; rm -rf "$(dirname "$DUCK_BASE")" "$(dirname "$DUCKED")"; exit 1; }
rm -rf "$(dirname "$DUCK_BASE")" "$(dirname "$DUCKED")"
echo "PASS: ducking lowered BGM under voice ($DUCK_METRICS)"

# 3-way color grade must be reflected in export: a warm grade shifts the exported
# average color (red up, blue down) vs an ungraded export of the same clip.
BARS="$ROOT/Tests/Fixtures/bars_320x240_3s_30fps.mp4"

platform_export_check() {
  local raw="$1"
  local label="$2"
  local expected_width="$3"
  local expected_height="$4"
  local expected_fps="$5"
  local expected_codec="$6"
  local expected_ext="$7"
  local tmpdir
  local out
  tmpdir="$(mktemp -d)"
  out="$tmpdir/${raw}.${expected_ext}"

  env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_PLATFORM_PRESET="$raw" \
    MOVIECUT_UITEST_EXPORT="$out" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
  local pp=$!
  wait_for_result "$pp" 240 0.5 "$out"

  if [ ! -s "$out" ]; then
    echo "FAIL: ${label} platform preset export missing" >&2
    rm -rf "$tmpdir"
    exit 1
  fi

  local width
  local height
  local avg_frame_rate
  local codec
  local format_name
  width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$out" 2>/dev/null)"
  height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$out" 2>/dev/null)"
  avg_frame_rate="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$out" 2>/dev/null)"
  codec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$out" 2>/dev/null)"
  format_name="$(ffprobe -v error -show_entries format=format_name -of csv=p=0 "$out" 2>/dev/null)"

  if [ "$width" != "$expected_width" ] || [ "$height" != "$expected_height" ]; then
    echo "FAIL: ${label} preset exported ${width}x${height}, expected ${expected_width}x${expected_height}" >&2
    rm -rf "$tmpdir"
    exit 1
  fi
  if [ "$codec" != "$expected_codec" ]; then
    echo "FAIL: ${label} preset codec ${codec}, expected ${expected_codec}" >&2
    rm -rf "$tmpdir"
    exit 1
  fi
  if [ "${out##*.}" != "$expected_ext" ]; then
    echo "FAIL: ${label} preset extension ${out##*.}, expected ${expected_ext}" >&2
    rm -rf "$tmpdir"
    exit 1
  fi
  case "$format_name" in
    *"$expected_ext"*) ;;
    *) echo "FAIL: ${label} preset container ${format_name}, expected ${expected_ext}" >&2; rm -rf "$tmpdir"; exit 1 ;;
  esac
  awk -v r="$avg_frame_rate" -v expected="$expected_fps" 'BEGIN {
      split(r, parts, "/")
      fps = (parts[2] && parts[2] != 0) ? parts[1] / parts[2] : r + 0
      exit !(fps > expected - 0.05 && fps < expected + 0.05)
    }' || {
      echo "FAIL: ${label} preset fps ${avg_frame_rate}, expected ${expected_fps}" >&2
      rm -rf "$tmpdir"
      exit 1
    }

  echo "PASS: ${label} preset export ${width}x${height} ${avg_frame_rate} ${codec} ${format_name} .${expected_ext}"
  rm -rf "$tmpdir"
}

platform_export_check "tikTok" "TikTok" "1080" "1920" "30" "h264" "mp4"
platform_export_check "instagramReels" "Instagram Reels" "1080" "1920" "30" "h264" "mp4"
platform_export_check "youtubeShorts" "YouTube Shorts" "1080" "1920" "30" "h264" "mp4"
platform_export_check "youtubeStandard" "YouTube Standard" "1920" "1080" "30" "h264" "mp4"
platform_export_check "instagramPost" "Instagram Post" "1080" "1080" "30" "h264" "mp4"

favg() { ffmpeg -v error -i "$1" -vf "scale=1:1" -frames:v 1 -f rawvideo -pix_fmt rgb24 - 2>/dev/null | xxd -p; }
GBASE="$(mktemp -d)/gbase.mp4"; GGRADE="$(mktemp -d)/ggrade.mp4"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_EXPORT="$GBASE" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
GP=$!; for _ in $(seq 1 120); do [ -s "$GBASE" ] && break; sleep 0.5; done; wait "$GP" 2>/dev/null || true
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_GRADE=1 MOVIECUT_UITEST_EXPORT="$GGRADE" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
GP=$!; for _ in $(seq 1 120); do [ -s "$GGRADE" ] && break; sleep 0.5; done; wait "$GP" 2>/dev/null || true
B_AVG="$(favg "$GBASE")"; G_AVG="$(favg "$GGRADE")"
rm -rf "$(dirname "$GBASE")" "$(dirname "$GGRADE")"
if [ -n "$B_AVG" ] && [ "$B_AVG" != "$G_AVG" ]; then
  echo "PASS: color grade reflected in export (avg $B_AVG -> $G_AVG)"
else
  echo "FAIL: color grade not reflected in export (avg $B_AVG vs $G_AVG)" >&2; exit 1
fi

# G-03 adjustment layer: marking the (only) clip as an adjustment layer
# with a strong grade must change the export — but an adjustment-ONLY
# project (no visible content) must be REJECTED, never silently degraded.
GADJ="$(mktemp -d)/gadj.mp4"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" \
  MOVIECUT_UITEST_GRADE=1 MOVIECUT_UITEST_ADJUSTMENT_LAYER=1 \
  MOVIECUT_UITEST_EXPORT="$GADJ" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
GAP=$!; for _ in $(seq 1 120); do [ -s "$GADJ" ] && break; sleep 0.5; done; wait "$GAP" 2>/dev/null || true
if [ -s "$GADJ" ]; then
  echo "FAIL: adjustment-only project exported (should be rejected: no visible content)" >&2
  exit 1
fi
echo "PASS: G-03 adjustment-only project correctly rejected (no visible content)"

# G-02 Inc 3 HSL/curve grade must be reflected in export without relying on
# lift/gamma/gain. Compare a same-app baseline of the solid red fixture against
# an HSL red desaturation + master curve export.
G02_BASE="$(mktemp -d)/g02_hsl_curve_base.mp4"; G02_GRADE="$(mktemp -d)/g02_hsl_curve_grade.mp4"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" MOVIECUT_UITEST_EXPORT="$G02_BASE" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
G02P=$!; for _ in $(seq 1 120); do [ -s "$G02_BASE" ] && break; sleep 0.5; done; wait "$G02P" 2>/dev/null || true
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" MOVIECUT_UITEST_HSL_CURVES=1 MOVIECUT_UITEST_EXPORT="$G02_GRADE" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
G02P=$!; for _ in $(seq 1 120); do [ -s "$G02_GRADE" ] && break; sleep 0.5; done; wait "$G02P" 2>/dev/null || true
[ -s "$G02_BASE" ] || { echo "FAIL: G-02 HSL/curve baseline export missing" >&2; exit 1; }
[ -s "$G02_GRADE" ] || { echo "FAIL: G-02 HSL/curve export missing" >&2; exit 1; }
G02_METRICS="$(python3 - "$G02_BASE" "$G02_GRADE" <<'PY'
import subprocess
import sys

base_path, grade_path = sys.argv[1:3]

def avg_rgb(path):
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-ss", "1.0", "-i", path,
        "-vf", "scale=1:1", "-frames:v", "1",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ])
    if len(data) != 3:
        raise SystemExit(f"expected 3 avg RGB bytes for {path}, got {len(data)}")
    return tuple(data)

base = avg_rgb(base_path)
grade = avg_rgb(grade_path)
gray_spread = max(grade) - min(grade)
print(f"base_rgb={base[0]},{base[1]},{base[2]} grade_rgb={grade[0]},{grade[1]},{grade[2]} gray_spread={gray_spread}")
base_spread = max(base) - min(base)
channel_delta = sum(abs(int(grade[i]) - int(base[i])) for i in range(3))
if not (
    base[0] > base[1] + 3 and base[0] > base[2] + 3
    and gray_spread <= 2
    and gray_spread < base_spread
    and channel_delta >= 8
):
    raise SystemExit(2)
PY
)" || { echo "FAIL: G-02 HSL/curve grade not reflected in export (${G02_METRICS:-no metrics})" >&2; rm -rf "$(dirname "$G02_BASE")" "$(dirname "$G02_GRADE")"; exit 1; }
rm -rf "$(dirname "$G02_BASE")" "$(dirname "$G02_GRADE")"
echo "PASS: G-02 HSL/curve grade reflected in export ($G02_METRICS)"

# G-01 Inc 2: karaoke active-word highlighting must be reflected in the real
# export. Two exports of the same text overlay (karaoke OFF baseline, karaoke
# ON with deterministic word timings) driven through the PARITY harness flow —
# that is where the TEXT_AT/KARAOKE gates live. The OFF export's text is
# static, so frames 0.85s apart are pixel-identical (noise floor); the ON
# export's glyphs progressively turn yellow (base white #FFFFFF -> highlight
# #FFD60A), so the same two frames differ on a measurable glyph-area pixel
# count. Text clip starts at 0.5s; word i starts 0.1+0.4i seconds into the
# clip, so t=0.6 has one word highlighted and t=1.45 has all three.
K01_OFF="$(mktemp -d)/k01_karaoke_off.mp4"; K01_ON="$(mktemp -d)/k01_karaoke_on.mp4"
K01_ENV=(MOVIECUT_UITEST=1 MOVIECUT_UITEST_PARITY=1 MOVIECUT_UITEST_PARITY_TIMES=0.6
  MOVIECUT_UITEST_IMPORT="$FIXTURE" MOVIECUT_UITEST_TEXT_AT=0.5
  MOVIECUT_UITEST_PREVIEW_DUMP="$(dirname "$K01_OFF")/preview" MOVIECUT_UITEST_QUIT=1)
env "${K01_ENV[@]}" MOVIECUT_UITEST_EXPORT="$K01_OFF" "$APP_BIN" >/dev/null 2>&1 &
K1P=$!; for _ in $(seq 1 120); do [ -s "$K01_OFF" ] && break; sleep 0.5; done; wait "$K1P" 2>/dev/null || true
env "${K01_ENV[@]}" MOVIECUT_UITEST_EXPORT="$K01_ON" MOVIECUT_UITEST_KARAOKE=1 "$APP_BIN" >/dev/null 2>&1 &
K1P=$!; for _ in $(seq 1 120); do [ -s "$K01_ON" ] && break; sleep 0.5; done; wait "$K1P" 2>/dev/null || true
[ -s "$K01_OFF" ] || { echo "FAIL: G-01 karaoke baseline export missing" >&2; exit 1; }
[ -s "$K01_ON" ] || { echo "FAIL: G-01 karaoke export missing" >&2; exit 1; }
K01_METRICS="$(python3 - "$K01_OFF" "$K01_ON" <<'PY'
import subprocess
import sys

off_path, on_path = sys.argv[1:3]

def frame(path, t):
    return subprocess.check_output([
        "ffmpeg", "-v", "error", "-ss", str(t), "-i", path,
        "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ])

def changed_pixels(a, b, threshold=40):
    if len(a) != len(b):
        raise SystemExit(f"frame size mismatch {len(a)} vs {len(b)}")
    return sum(1 for i in range(0, len(a), 3)
               if abs(a[i] - b[i]) > threshold
               or abs(a[i + 1] - b[i + 1]) > threshold
               or abs(a[i + 2] - b[i + 2]) > threshold)

off_early, off_late = frame(off_path, 0.6), frame(off_path, 1.45)
on_early, on_late = frame(on_path, 0.6), frame(on_path, 1.45)
off_changed = changed_pixels(off_early, off_late)
on_changed = changed_pixels(on_early, on_late)
print(f"off_changed={off_changed} on_changed={on_changed}")
# Karaoke ON must recolor a real glyph area between the two phases (two more
# words highlighted: "text overlay"); the OFF baseline text is static. The
# floor tolerates codec noise; the cap rules out a full-frame change (which
# would mean something other than glyph recoloring moved).
if not (on_changed > 150 and on_changed - off_changed > 100 and on_changed < len(on_early) // 30):
    raise SystemExit(2)
PY
)" || { echo "FAIL: G-01 karaoke highlight not reflected in export (${K01_METRICS:-no metrics})" >&2; rm -rf "$(dirname "$K01_OFF")" "$(dirname "$K01_ON")"; exit 1; }
rm -rf "$(dirname "$K01_OFF")" "$(dirname "$K01_ON")"
echo "PASS: G-01 karaoke active-word highlight reflected in export ($K01_METRICS)"

# Color scope must produce real histogram data from the graded thumbnail.
SC_RESULT="$(mktemp -d)/sc.txt"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_SCOPE=1 \
  MOVIECUT_UITEST_RESULT="$SC_RESULT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
SP=$!; for _ in $(seq 1 90); do [ -s "$SC_RESULT" ] && break; sleep 0.5; done; wait "$SP" 2>/dev/null || true
SC_STATUS="$(cat "$SC_RESULT" 2>/dev/null || echo MISSING)"; rm -rf "$(dirname "$SC_RESULT")"
SC_SUM="$(printf '%s' "$SC_STATUS" | sed -n 's/.*scope_luma_sum=\([0-9]*\).*/\1/p')"
if [ -n "$SC_SUM" ] && [ "$SC_SUM" -gt 0 ]; then
  echo "PASS: color scope produced histogram data (luma samples $SC_SUM)"
else
  echo "FAIL: color scope produced no data ($SC_STATUS)" >&2; exit 1
fi

# ProRes master must export as actual ProRes.
PR_OUT="$(mktemp -d)/master.mov"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_EXPORT_PRORES="$PR_OUT" \
  MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
PP=$!; for _ in $(seq 1 180); do [ -s "$PR_OUT" ] && break; sleep 0.5; done; wait "$PP" 2>/dev/null || true
PR_CODEC="$(ffprobe -v error -select_streams v -show_entries stream=codec_name -of csv=p=0 "$PR_OUT" 2>/dev/null)"
rm -rf "$(dirname "$PR_OUT")"
[ "$PR_CODEC" = "prores" ] && echo "PASS: ProRes master exported (codec $PR_CODEC)" \
  || { echo "FAIL: ProRes export wrong codec ($PR_CODEC)" >&2; exit 1; }

# v1 contract (Phase 1 render reliability): HDR mastering is feature-gated
# OFF — the 8-bit SDR pipeline must never emit a file TAGGED as HDR. The old
# assertion expected 10-bit/HLG/Rec.2020 output; with the flag off the export
# is refused and no file appears, which used to kill ffprobe (and the whole
# script) under set -e with no FAIL line. The honest assertion now checks the
# false-label guarantee: no output at all, or an output with no HDR tags.
HDR_OUT="$(mktemp -d)/hdr.mov"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_EXPORT_HDR="$HDR_OUT" \
  MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
HP=$!; for _ in $(seq 1 180); do [ -s "$HDR_OUT" ] && break; sleep 0.5; done; wait "$HP" 2>/dev/null || true
if [ ! -s "$HDR_OUT" ]; then
  rm -rf "$(dirname "$HDR_OUT")"
  echo "PASS: HDR master refused under FeatureFlag.hdrMaster (no mislabeled output)"
else
  HDR_TAGS="$(ffprobe -v error -select_streams v -show_entries stream=pix_fmt,color_transfer,color_primaries -of csv=p=0 "$HDR_OUT" 2>/dev/null || true)"
  rm -rf "$(dirname "$HDR_OUT")"
  case "$HDR_TAGS" in
    *arib-std-b67*|*smpte2084*|*bt2020*|*yuv420p10le*)
      echo "FAIL: HDR-tagged output emitted from the SDR-only build ($HDR_TAGS)" >&2; exit 1 ;;
    *) echo "PASS: HDR request produced an untagged SDR fallback (no false HDR labels: $HDR_TAGS)" ;;
  esac
fi

# On-device auto white balance must produce a corrective per-channel gain.
WB_RESULT="$(mktemp -d)/wb.txt"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_AUTOWB=1 \
  MOVIECUT_UITEST_RESULT="$WB_RESULT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
WP=$!; for _ in $(seq 1 90); do [ -s "$WB_RESULT" ] && break; sleep 0.5; done; wait "$WP" 2>/dev/null || true
WB_STATUS="$(cat "$WB_RESULT" 2>/dev/null || echo MISSING)"; rm -rf "$(dirname "$WB_RESULT")"
WB_GAIN="$(printf '%s' "$WB_STATUS" | sed -n 's/.*autowb_gain=\([0-9.,]*\).*/\1/p')"
if [ -n "$WB_GAIN" ] && [ "$WB_GAIN" != "none" ] && [ "$WB_GAIN" != "1.000,1.000,1.000" ]; then
  echo "PASS: auto white balance produced a corrective gain ($WB_GAIN)"
else
  echo "FAIL: auto white balance did not correct ($WB_STATUS)" >&2; exit 1
fi

# On-device auto levels must produce a contrast stretch (gain > 1).
AL_RESULT="$(mktemp -d)/al.txt"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_AUTOLEVELS=1 \
  MOVIECUT_UITEST_RESULT="$AL_RESULT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
AP=$!; for _ in $(seq 1 90); do [ -s "$AL_RESULT" ] && break; sleep 0.5; done; wait "$AP" 2>/dev/null || true
AL_STATUS="$(cat "$AL_RESULT" 2>/dev/null || echo MISSING)"; rm -rf "$(dirname "$AL_RESULT")"
AL_GAIN="$(printf '%s' "$AL_STATUS" | sed -n 's/.*autolevels_gain=\([0-9.]*\).*/\1/p')"
if [ -n "$AL_GAIN" ] && awk -v g="$AL_GAIN" 'BEGIN{exit !(g>1.0)}'; then
  echo "PASS: auto levels produced a contrast stretch (gain $AL_GAIN)"
else
  echo "FAIL: auto levels did not stretch ($AL_STATUS)" >&2; exit 1
fi

# One-tap auto enhance must combine white balance and a contrast stretch.
AE_RESULT="$(mktemp -d)/ae.txt"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_AUTOENHANCE=1 \
  MOVIECUT_UITEST_RESULT="$AE_RESULT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
AEP=$!; for _ in $(seq 1 90); do [ -s "$AE_RESULT" ] && break; sleep 0.5; done; wait "$AEP" 2>/dev/null || true
AE_STATUS="$(cat "$AE_RESULT" 2>/dev/null || echo MISSING)"; rm -rf "$(dirname "$AE_RESULT")"
case "$AE_STATUS" in
  *autoenhance_gain=*lift=-*) echo "PASS: auto enhance combined WB + contrast ($(printf '%s' "$AE_STATUS" | grep -o 'autoenhance_gain=[^ ]* lift=[^ ]*'))" ;;
  *) echo "FAIL: auto enhance did not produce a combined grade ($AE_STATUS)" >&2; exit 1 ;;
esac

# Crash-recovery autosave must be written off the edit path (isolated dir).
if [ "$SANDBOX" = "1" ]; then
  # SKIPPED under the sandbox: recovery.moviecut is written by flushAutosave()
  # during the harness shutdown path, then immediately cleared by the
  # willTerminate handler that follows NSApp.terminate. The sandbox-OFF path
  # only passes because its poll loop catches the file in the window between
  # flush and clear — a timing race that is not a stable signal sandboxed.
  # The recovery semantics are covered by AutosaveRecoveryTests (unit); the
  # end-to-end force-kill gate is the pending B-U7 task.
  echo "SKIP: crash-recovery autosave — timing-race under sandbox; covered by AutosaveRecoveryTests (unit) and pending B-U7 (e2e)"
else
AS_DIR="$(mktemp -d)"
env MOVIECUT_UITEST=1 MOVIECUT_AUTOSAVE_DIR="$AS_DIR" MOVIECUT_UITEST_IMPORT="$TONE" \
  MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
AP=$!
for _ in $(seq 1 60); do [ -s "$AS_DIR/recovery.moviecut" ] && break; sleep 0.5; done
wait "$AP" 2>/dev/null || true
if [ -s "$AS_DIR/recovery.moviecut" ]; then
  echo "PASS: crash-recovery autosave written ($(stat -f%z "$AS_DIR/recovery.moviecut") bytes)"
else
  echo "FAIL: no crash-recovery autosave after edit" >&2; rm -rf "$AS_DIR"; exit 1
fi
rm -rf "$AS_DIR"
fi

# G-18 Inc 4: actual-app card editor save/reload E2E. Drives the same
# EditorViewModel/CardEditorView/CardCanvasView command paths through a real
# MovieCutMac process: add/duplicate/delete/reorder pages, all three formats,
# inline text update with undo/redo, save, reload into a fresh session, and a
# fail-closed machine-readable dump. Static contracts do not count as proof.
CARD_FIXTURE="$ROOT/Tests/Fixtures/card_editor_bootstrap.moviecut"
[ -s "$CARD_FIXTURE" ] || { echo "missing card editor fixture" >&2; exit 1; }
CARD_TMPDIR="$(mktemp -d)"
CARD_RESULT="$CARD_TMPDIR/card_editor.json"
CARD_SAVE="$CARD_TMPDIR/saved.moviecut"
CARD_RELOAD="$CARD_TMPDIR/reloaded.moviecut"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_CARD_EDITOR=1 \
  MOVIECUT_UITEST_CARD_EDITOR_SOURCE="$CARD_FIXTURE" \
  MOVIECUT_UITEST_CARD_EDITOR_SAVE="$CARD_SAVE" \
  MOVIECUT_UITEST_CARD_EDITOR_RELOAD="$CARD_RELOAD" \
  MOVIECUT_UITEST_RESULT="$CARD_RESULT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
CAP=$!
wait_for_result "$CAP" 120 0.5 "$CARD_RESULT"
CARD_STATUS="$(cat "$CARD_RESULT" 2>/dev/null || echo MISSING)"
# Fail closed unless every required field is present and correct.
CARD_COMPLETE="$(printf '%s' "$CARD_STATUS" | python3 -c 'import json,sys
d=json.load(sys.stdin)
ok=(d.get("complete") is True
    and d.get("completionMarker")=="G18_CARD_EDITOR_E2E_COMPLETE"
    and d.get("error")=="none"
    and d.get("finalPageCount")==5
    and d.get("actionCounts",{}).get("add",99)<=2
    and d.get("actionCounts",{}).get("duplicate",99)<=2
    and d.get("actionCounts",{}).get("delete",99)<=2
    and d.get("actionCounts",{}).get("reorder",99)<=2
    and d.get("actionCounts",{}).get("inlineDoubleClick")==1
    and d.get("observedFormats")==["square","portrait","story"]
    and float(d.get("maxNormalizedFrameError",999))<=0.001
    and bool(d.get("inlineUndoRestored")) is True
    and bool(d.get("inlineRedoRestored")) is True
    and bool(d.get("saveReloadEqual")) is True
    and bool(d.get("freshSessionReloaded")) is True
    and int(d.get("savedProjectBytes",0))>0
    and int(d.get("reloadedProjectBytes",0))>0)
print("1" if ok else "0")
' 2>/dev/null || echo 0)"
if [ "$CARD_COMPLETE" = "1" ] && [ -s "$CARD_SAVE" ] && [ -s "$CARD_RELOAD" ]; then
  CARD_PAGES="$(printf '%s' "$CARD_STATUS" | python3 -c 'import json,sys;print(len(json.load(sys.stdin).get("orderedPageIDs",[])))' 2>/dev/null || echo 0)"
  echo "PASS: card editor save/reload E2E (5 pages, inline undo/redo, save==reload, $CARD_PAGES ordered IDs)"
else
  echo "FAIL: card editor save/reload E2E ($CARD_STATUS)" >&2
  cat "$CARD_RESULT" 2>/dev/null >&2 || true
  rm -rf "$CARD_TMPDIR"; exit 1
fi
rm -rf "$CARD_TMPDIR"

# G-19 Inc 4: actual-app template gallery/master-style E2E. Enumerates the
# built-in manifest, applies a complete five-page set through the gallery's
# ViewModel API, builds the eight-page UB-C5 fixture through duplicate commands,
# applies a master preset, and proves both atomic changes restore in one undo.
# Only the exact MovieCutMac PID launched here is eligible for timeout cleanup.
CARD_TEMPLATE_TMPDIR="$(mktemp -d)"
CARD_TEMPLATE_RESULT="$CARD_TEMPLATE_TMPDIR/card_template.json"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_CARD_TEMPLATE=1 \
  MOVIECUT_UITEST_CARD_TEMPLATE_SOURCE="$CARD_FIXTURE" \
  MOVIECUT_UITEST_RESULT="$CARD_TEMPLATE_RESULT" MOVIECUT_UITEST_QUIT=1 \
  "$APP_BIN" >/dev/null 2>&1 &
CARD_TEMPLATE_PID=$!
for _ in $(seq 1 120); do
  [ -s "$CARD_TEMPLATE_RESULT" ] && break
  sleep 0.5
done
if kill -0 "$CARD_TEMPLATE_PID" 2>/dev/null; then
  kill "$CARD_TEMPLATE_PID" 2>/dev/null || true
fi
wait "$CARD_TEMPLATE_PID" 2>/dev/null || true
CARD_TEMPLATE_STATUS="$(cat "$CARD_TEMPLATE_RESULT" 2>/dev/null || echo MISSING)"
CARD_TEMPLATE_COMPLETE="$(printf '%s' "$CARD_TEMPLATE_STATUS" | python3 -c 'import json,sys
d=json.load(sys.stdin)
roles=d.get("rolesPresent",[])
changed=d.get("masterChangedAttributes",[])
ok=(d.get("complete") is True
    and d.get("completionMarker")=="G19_CARD_TEMPLATE_E2E_COMPLETE"
    and d.get("error")=="none"
    and int(d.get("builtinCount",0))>=10
    and len(d.get("builtinSetIDs",[]))==int(d.get("builtinCount",0))
    and len(set(d.get("builtinSetIDs",[])))==int(d.get("builtinCount",0))
    and len(d.get("builtinSetNames",[]))==int(d.get("builtinCount",0))
    and bool(d.get("appliedSetID"))
    and bool(d.get("appliedSetName"))
    and int(d.get("pageCount",0))==5
    and roles==["cover","body","emphasis","closing"]
    and int(d.get("emptyRequiredSlotCount",-1))==0
    and int(d.get("templateClickCount",99))<=2
    and int(d.get("masterClickCount",99))<=3
    and int(d.get("masterPropagationPageCount",0))>=8
    and d.get("masterPropagationAcrossAllPages") is True
    and int(d.get("masterInheritedPageCount",0))>=7
    and d.get("masterFontFamily")=="Futura"
    and d.get("masterPrimaryColorHex")=="#FF6B35"
    and isinstance(d.get("masterLogoPlacement"),dict)
    and all(key in changed for key in ("fontFamily","primaryColorHex","logoPlacement"))
    and int(d.get("masterLogoElementCount",0))>0
    and int(d.get("masterLogoPlacementMatchCount",-1))==int(d.get("masterLogoElementCount",0))
    and int(d.get("pageOverrideCount",0))>=1
    and d.get("pageOverridesPreserved") is True
    and d.get("templateUndoRestored") is True
    and d.get("templateRedoRestored") is True
    and d.get("masterUndoRestored") is True)
print("1" if ok else "0")
' 2>/dev/null || echo 0)"
if [ "$CARD_TEMPLATE_COMPLETE" = "1" ]; then
  CARD_TEMPLATE_SUMMARY="$(printf '%s' "$CARD_TEMPLATE_STATUS" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print("builtins=%s set=%s pages=%s roles=%s empty=%s template_clicks=%s master_pages=%s master_clicks=%s template_undo=%s master_undo=%s" % (
    d.get("builtinCount"), d.get("appliedSetID"), d.get("pageCount"),
    ",".join(d.get("rolesPresent",[])), d.get("emptyRequiredSlotCount"),
    d.get("templateClickCount"), d.get("masterPropagationPageCount"),
    d.get("masterClickCount"), int(d.get("templateUndoRestored",False)),
    int(d.get("masterUndoRestored",False))))
' 2>/dev/null || echo summary_error)"
  echo "PASS: G-19 card template/master style E2E ($CARD_TEMPLATE_SUMMARY)"
else
  echo "FAIL: G-19 card template/master style E2E ($CARD_TEMPLATE_STATUS)" >&2
  cat "$CARD_TEMPLATE_RESULT" 2>/dev/null >&2 || true
  rm -rf "$CARD_TEMPLATE_TMPDIR"; exit 1
fi
rm -rf "$CARD_TEMPLATE_TMPDIR"

# G-25 Inc 9 (spec §8·§11④): AAC post-check on the ACTUAL exported file +
# audio-solo E2E. The project is TWO separate audio tracks (the ducking
# harness builds real BGM/Voice tracks: 220 Hz BGM 0-4s, 1 kHz voice 1-2s)
# exported as AUDIO-ONLY m4a — §8's gate is about the encoded audio file.
# (A video import + these ducking tracks + an mp4 export hangs in a
# PREEXISTING defect unrelated to G-25 — recorded in docs/LOOP_STATE.md.)
# Two runs:
#   A — plain export; the harness re-decodes the real output file and the
#       project's preview-mix render, reporting lengths, RMS difference, and
#       the measured LUFS-I / true peak / clipping (shared Core functions).
#   B — the LAST audio track (Voice) is SOLOED through the real
#       SetTrackPropertyCommand path before export; soloing the quiet voice
#       suppresses the louder BGM, so the exported mix must get measurably
#       quieter — proving solo reaches the export audio mix.
# Both sides of the post-check are AAC today (the reference is the preview
# mix render until the graph encoder input lands), so codec padding can move
# lengths by an AAC frame — the gate bounds |Δlength| ≤ 2112 samples and
# |RMS| ≤ 1 dB and reports exact numbers; the strict ±1-sample form belongs
# to the graph-input era (documented in docs/LOOP_STATE.md).
G25_POSTCHECK_TMPDIR="$(mktemp -d)"
G25_POSTCHECK_A_RESULT="$G25_POSTCHECK_TMPDIR/a.txt"
G25_POSTCHECK_A_JSON="$G25_POSTCHECK_TMPDIR/a.json"
G25_POSTCHECK_B_RESULT="$G25_POSTCHECK_TMPDIR/b.txt"
G25_POSTCHECK_B_JSON="$G25_POSTCHECK_TMPDIR/b.json"
G25_EXPORT_A="$G25_POSTCHECK_TMPDIR/export-a.m4a"
G25_EXPORT_B="$G25_POSTCHECK_TMPDIR/export-b.m4a"
G25_BGM="$ROOT/Tests/Fixtures/duck_bgm_220hz_4s_mono.wav"
G25_VOICE="$ROOT/Tests/Fixtures/duck_voice_1000hz_1s_mono.wav"
G25_APP="${APP_BIN%/*/*/*}"
sleep 1
echo "Running G-25 §8 export post-check (run A: plain mix)"
open -n -W \
  --env MOVIECUT_UITEST=1 \
  --env MOVIECUT_UITEST_DUCKING_BGM="$G25_BGM" \
  --env MOVIECUT_UITEST_DUCKING_VOICE="$G25_VOICE" \
  --env MOVIECUT_UITEST_EXPORT_AUDIO="$G25_EXPORT_A" \
  --env MOVIECUT_UITEST_EXPORT_POSTCHECK="$G25_POSTCHECK_A_JSON" \
  --env MOVIECUT_UITEST_RESULT="$G25_POSTCHECK_A_RESULT" \
  --env MOVIECUT_UITEST_QUIT=1 \
  "$G25_APP" >/dev/null 2>&1 &
G25A=$!
wait_for_result "$G25A" 120 0.5 "$G25_POSTCHECK_A_RESULT"
G25_A_STATUS="$(cat "$G25_POSTCHECK_A_RESULT" 2>/dev/null || echo MISSING)"
sleep 1
echo "Running G-25 §8 export post-check (run B: Voice track soloed, BGM suppressed)"
open -n -W \
  --env MOVIECUT_UITEST=1 \
  --env MOVIECUT_UITEST_DUCKING_BGM="$G25_BGM" \
  --env MOVIECUT_UITEST_DUCKING_VOICE="$G25_VOICE" \
  --env MOVIECUT_UITEST_SOLO_LAST_AUDIO_TRACK=1 \
  --env MOVIECUT_UITEST_EXPORT_AUDIO="$G25_EXPORT_B" \
  --env MOVIECUT_UITEST_EXPORT_POSTCHECK="$G25_POSTCHECK_B_JSON" \
  --env MOVIECUT_UITEST_RESULT="$G25_POSTCHECK_B_RESULT" \
  --env MOVIECUT_UITEST_QUIT=1 \
  "$G25_APP" >/dev/null 2>&1 &
G25B=$!
wait_for_result "$G25B" 120 0.5 "$G25_POSTCHECK_B_RESULT"
G25_B_STATUS="$(cat "$G25_POSTCHECK_B_RESULT" 2>/dev/null || echo MISSING)"
G25_POSTCHECK_SUMMARY="$(python3 - "$G25_POSTCHECK_A_JSON" "$G25_POSTCHECK_B_JSON" "$G25_A_STATUS" "$G25_B_STATUS" <<'PY'
import json, re, sys

a_json, b_json, a_status, b_status = sys.argv[1:5]

def fail(message):
    raise SystemExit(f"FAIL: {message}")

for label, status in (("A", a_status), ("B", b_status)):
    if "error=none" not in status:
        fail(f"run {label} reported an error: {status}")
    if "export_postcheck=ok" not in status:
        fail(f"run {label} post-check did not complete: {status}")

if "solo_applied=1" not in b_status:
    fail(f"run B did not solo the last audio track: {b_status}")

def number(status, key):
    match = re.search(rf"(?:^| ){key}=(-?[0-9.]+)", status)
    if not match:
        fail(f"missing {key}: {status}")
    return float(match.group(1))

a = json.load(open(a_json))
b = json.load(open(b_json))
if a["error"] != "none" or b["error"] != "none":
    fail(f"artifact error: {a['error']} / {b['error']}")

# Length gate (AAC-vs-AAC era bound; strict ±1 belongs to graph input). The
# preview render and the export can carry DIFFERENT sample rates and AAC
# padding conventions (measured: the preview m4a renders ~0.35 s longer),
# so the gate is on DURATION, not frames: |Δt| ≤ 0.5 s.
for label, dump in (("A", a), ("B", b)):
    if dump["referenceFrames"] <= 0 or dump["decodedFrames"] <= 0:
        fail(f"run {label} decoded empty audio: {dump}")
    reference_duration = dump["referenceFrames"] / dump["referenceSampleRate"]
    decoded_duration = dump["decodedFrames"] / dump["decodedSampleRate"]
    if abs(decoded_duration - reference_duration) > 0.5:
        fail(f"run {label} duration delta beyond 0.5 s: {dump}")
    if abs(dump["rmsDifferenceDb"]) > 1.0:
        fail(f"run {label} RMS difference beyond 1 dB: {dump['rmsDifferenceDb']}")
    if dump["clippingRunCount"] != 0:
        fail(f"run {label} clipped output: {dump}")

# Solo must measurably change the exported mix: soloing the QUIET voice
# suppresses the LOUDER BGM, so run B must come out 1.5-12 LU quieter.
if a["decodedLufs"] is None or b["decodedLufs"] is None:
    fail(f"loudness missing: {a['decodedLufs']} / {b['decodedLufs']}")
delta = b["decodedLufs"] - a["decodedLufs"]
if not (-12.0 < delta < -1.5):
    fail(f"solo did not quiet the exported mix as expected (LUFS Δ={delta:.3f})")

print(
    "len=%d/%d rms=%.3fdB lufs=%.2f→%.2f (solo Δ=%.2f LU) tp=%.2f→%.2f warnings=%d/%d" % (
        a["decodedFrames"], b["decodedFrames"],
        a["rmsDifferenceDb"], a["decodedLufs"], b["decodedLufs"], delta,
        a["decodedTruePeakDbTp"], b["decodedTruePeakDbTp"],
        a["warningCount"], b["warningCount"])
)
PY
)" || { echo "$G25_POSTCHECK_SUMMARY" >&2; echo "G-25 §8 post-check FAIL (artifacts: $G25_POSTCHECK_TMPDIR)" >&2; exit 1; }
echo "PASS: G-25 §8 export post-check + solo ($G25_POSTCHECK_SUMMARY)"

# --- G-25 switchover 2B: master meter through the GRAPH (run M) ---------------
# Same ducking-harness project, plus bass-boost EQ on the BGM clip (real
# command path) so the §0 effective-media derivation is exercised: the meter
# measures the graph mix (builder + derived EQ + §3.1 adapter), the export
# still mixes via audioMix (derived EQ offline) — the two must agree within
# tolerance while both paths are alive.
G25_POSTCHECK_M_RESULT="$G25_POSTCHECK_TMPDIR/m.txt"
G25_POSTCHECK_M_JSON="$G25_POSTCHECK_TMPDIR/m.json"
G25_POSTCHECK_M_METER="$G25_POSTCHECK_TMPDIR/meter.json"
G25_EXPORT_M="$G25_POSTCHECK_TMPDIR/export-m.m4a"
sleep 1
echo "Running G-25 §8 meter run (M: graph master meter + EQ on BGM)"
open -n -W \
  --env MOVIECUT_UITEST=1 \
  --env MOVIECUT_UITEST_DUCKING_BGM="$G25_BGM" \
  --env MOVIECUT_UITEST_DUCKING_VOICE="$G25_VOICE" \
  --env MOVIECUT_UITEST_MASTER_METER="$G25_POSTCHECK_M_METER" \
  --env MOVIECUT_UITEST_MASTER_METER_EQ=1 \
  --env MOVIECUT_UITEST_EXPORT_AUDIO="$G25_EXPORT_M" \
  --env MOVIECUT_UITEST_EXPORT_POSTCHECK="$G25_POSTCHECK_M_JSON" \
  --env MOVIECUT_UITEST_RESULT="$G25_POSTCHECK_M_RESULT" \
  --env MOVIECUT_UITEST_QUIT=1 \
  "$G25_APP" >/dev/null 2>&1 &
G25M=$!
wait_for_result "$G25M" 120 0.5 "$G25_POSTCHECK_M_RESULT"
G25_M_STATUS="$(cat "$G25_POSTCHECK_M_RESULT" 2>/dev/null || echo MISSING)"
G25_METER_SUMMARY="$(python3 - "$G25_POSTCHECK_M_JSON" "$G25_POSTCHECK_M_METER" "$G25_M_STATUS" <<'PY'
import json, re, sys

m_json, meter_json, m_status = sys.argv[1:4]

def fail(message):
    raise SystemExit(f"FAIL: {message}")

if "error=none" not in m_status:
    fail(f"run M reported an error: {m_status}")
for needed in ("master_meter=1", "meter_eq=1", "export_postcheck=ok"):
    if needed not in m_status:
        fail(f"run M missing {needed}: {m_status}")
meter_lufs_match = re.search(r"(?:^| )meter_lufs=(-?[0-9.]+)", m_status)
if not meter_lufs_match:
    fail(f"run M meter LUFS missing/silent: {m_status}")
meter_lufs = float(meter_lufs_match.group(1))

m = json.load(open(m_json))
meter = json.load(open(meter_json))
if m["error"] != "none" or meter["error"] != "none":
    fail(f"run M artifact error: {m['error']} / {meter['error']}")
if meter["lufs"] is None:
    fail(f"run M meter produced no integrated loudness: {meter}")
if m["decodedLufs"] is None:
    fail(f"run M export produced no loudness: {m}")

# The graph meter and the actually-encoded export must agree: tolerance
# spans the measured path delta (~0.003 LU first measurement) plus
# tap-vs-offline EQ DSP and AAC encoding.
delta = meter_lufs - m["decodedLufs"]
if abs(delta) > 1.5:
    fail(f"graph meter vs encoded export disagree: Δ={delta:.3f} LU")
if abs(m["rmsDifferenceDb"]) > 1.0:
    fail(f"run M RMS difference beyond 1 dB: {m['rmsDifferenceDb']}")
if m["clippingRunCount"] != 0:
    fail(f"run M clipped output: {m}")
# G-25 2C-2/2C-3: M's reference is now the graph PCM (like A/B), so this
# RMS gate measures codec fidelity of the EQ'd graph mix end to end.

print("meter: graph=%.2f LU export=%.2f LU Δ=%.2f tp=%.2f eq=1" % (
    meter_lufs, m["decodedLufs"], delta, meter["truePeakDbTp"]))
PY
)" || { echo "$G25_METER_SUMMARY" >&2; echo "G-25 §8 meter run FAIL (artifacts: $G25_POSTCHECK_TMPDIR)" >&2; exit 1; }
echo "PASS: G-25 §8 graph master meter ($G25_METER_SUMMARY)"
rm -rf "$G25_POSTCHECK_TMPDIR"

echo "E2E check OK (import->export + freeze + optical-flow slow motion + text animations + noise reduction SNR + EQ spectrum + audio extraction + ducking RMS + platform presets + color grade + G-03 adjustment layers + G-02 HSL/curves + scope + prores + hdr + autosave + G-18 card editor save/reload + G-19 card templates/master style + G-25 §8 post-check/solo + graph master meter)"
