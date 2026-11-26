#!/usr/bin/env bash
# QAUTO-06 — media compatibility corpus (미디어 호환 코퍼스).
#
# Contract (pre-registered 2026-09-22): every corpus entry is a
# deterministic lavfi-generated fixture pushed through the REAL app harness
# (import → export). Each leg must end in exactly one of:
#   SUCCESS — the harness completed (UITEST_DONE), reported error=none,
#             produced an artifact with a video stream and a container
#             duration within ±0.2 s of the fixture;
#   EXPLICIT-UNSUPPORTED — the harness completed and surfaced a classified
#             error (error != none). A hang, crash, or missing result line
#             is a FAILURE (the parked-app lesson), never "unsupported".
#
# Corpus (generated at run time — deterministic ffmpeg expressions; the
# provenance class is GENERATED, not committed fixtures):
#   h264_4k_30        3840x2160@30 + stereo 48 kHz
#   h264_1080_60      1920x1080@60 + stereo 48 kHz
#   hevc_1080_30      HEVC (libx265, hvc1 tag) 1920x1080@30 + stereo 48 kHz
#     — the hvc1 tag is the Apple-compatible form (iPhone recordings).
#       An hev1-tagged HEVC source is a KNOWN boundary measured on
#       2026-09-22: the harness surfaces a classified error ("작업이 중단됨")
#       at preset export — explicit-unsupported by contract; see the
#       QAUTO-06 record and the codec-tag validation backlog note.
#   silent_1080_30    video only (no audio track)
#   mono_44k1_1080    mono 44.1 kHz audio (mixed sample-rate axis)
#   portrait_9x16     1080x1920@30 portrait orientation
#
# Fail-closed guards: an empty/missing probe value or a missing result line
# is an ERROR (exit 2), never a pass. Disk guard preflight refuses to start
# on BLOCK/STOP.
#
# Usage: bash scripts/run_qauto06_media_corpus.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 2; }
command -v ffmpeg  >/dev/null || { echo "ffmpeg required" >&2;  exit 2; }

if [ -x "$ROOT/scripts/disk_guard.sh" ]; then
  "$ROOT/scripts/disk_guard.sh" >/dev/null 2>&1 || {
    rc=$?
    echo "ERROR: disk guard refuses new measurement (rc=$rc) — aborting" >&2
    exit 2
  }
fi

echo "Building MovieCutMac (Debug, sandbox OFF)..."
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
APP_BIN="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 2; }

WORK="$(mktemp -d /tmp/moviecut-qauto06.XXXXXX)"
LOG="$WORK/measure.log"
cleanup() {
  rm -rf "$WORK"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true
}
trap cleanup EXIT

# generate <out> <video-src> <rate> <audio-src|-> <vcodec> <size> <sample-rate|->
generate() {
  local out="$1" vsrc="$2" rate="$3" asrc="$4" vcodec="$5" size="$6" srate="$7"
  if [ "$asrc" = "-" ]; then
    ffmpeg -hide_banner -loglevel error -f lavfi -i "$vsrc=size=$size:rate=$rate:duration=2" \
      -c:v "$vcodec" -preset ultrafast -pix_fmt yuv420p -y "$out"
  else
    ffmpeg -hide_banner -loglevel error \
      -f lavfi -i "$vsrc=size=$size:rate=$rate:duration=2" \
      -f lavfi -i "$asrc=frequency=440:sample_rate=$srate:duration=2" \
      -c:v "$vcodec" -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest -y "$out"
  fi
}

declare -a CORPUS_IDS=(
  h264_4k_30 h264_1080_60 hevc_1080_30 silent_1080_30 mono_44k1_1080 portrait_9x16
)

make_fixture() {
  local id="$1" out="$2"
  case "$id" in
    h264_4k_30)     generate "$out" testsrc2 30 sine libx264 3840x2160 48000 ;;
    h264_1080_60)   generate "$out" testsrc2 60 sine libx264 1920x1080 48000 ;;
    hevc_1080_30)
      ffmpeg -hide_banner -loglevel error \
        -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=2" \
        -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=2" \
        -c:v libx265 -preset ultrafast -pix_fmt yuv420p -tag:v hvc1 \
        -c:a aac -shortest -y "$out"
      ;;
    silent_1080_30) generate "$out" testsrc2 30 -    libx264 1920x1080 - ;;
    mono_44k1_1080) generate "$out" testsrc2 30 sine libx264 1920x1080 44100 ;;
    portrait_9x16)  generate "$out" testsrc2 30 sine libx264 1080x1920 48000 ;;
    *) return 2 ;;
  esac
}

run_leg() {
  local id="$1" fixture="$2"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 2
  local out="$WORK/$id-out.mp4" result="$WORK/$id-result.txt"
  rm -f "$out" "$result"
  env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$fixture" \
    MOVIECUT_UITEST_EXPORT="$out" MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >"$WORK/$id-app.log" 2>&1 &
  local pid=$!
  ( sleep 240; kill "$pid" 2>/dev/null; true ) & local wd=$!
  for _ in $(seq 1 480); do
    grep -q "UITEST_DONE" "$result" 2>/dev/null && break
    sleep 0.5
  done
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true

  # Fail-closed: no result line at all is a hang/crash, never "unsupported".
  if ! grep -q "UITEST_DONE" "$result" 2>/dev/null; then
    echo "MEASURE $id FAILED — no UITEST_DONE (parked or crashed)" | tee -a "$LOG"
    cp "$WORK/$id-app.log" "/tmp/moviecut-qauto06-$id-fail.log" 2>/dev/null || true
    return 1
  fi

  if grep -q "error=none" "$result" 2>/dev/null; then
    # SUCCESS contract: artifact + video stream + duration ±0.2.
    [ -s "$out" ] || { echo "MEASURE $id FAILED — error=none but no artifact" | tee -a "$LOG"; return 1; }
    local dur vstreams
    dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out" 2>/dev/null || echo x)"
    vstreams="$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$out" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$dur" = "x" ] || [ -z "$dur" ] || [ "$vstreams" -lt 1 ]; then
      echo "MEASURE $id FAILED — probe failed dur=${dur:-?} vstreams=$vstreams" | tee -a "$LOG"
      return 1
    fi
    local ok
    ok="$(python3 -c "print(1 if abs(float('$dur')-2.0)<=0.2 else 0)")"
    if [ "$ok" != "1" ]; then
      echo "MEASURE $id FAILED — duration $dur outside 2.0±0.2" | tee -a "$LOG"
      return 1
    fi
    echo "MEASURE $id SUCCESS dur=${dur}s" | tee -a "$LOG"
    return 0
  fi

  # EXPLICIT-UNSUPPORTED: classified error surfaced while completing.
  local status
  status="$(grep -oE 'error=.*' "$result" | head -1)"
  echo "MEASURE $id EXPLICIT-UNSUPPORTED $status" | tee -a "$LOG"
  return 0
}

echo "=== QAUTO-06 media compatibility corpus (6 legs) ===" | tee -a "$LOG"
FAIL=0
for id in "${CORPUS_IDS[@]}"; do
  fixture="$WORK/$id.mp4"
  if ! make_fixture "$id" "$fixture"; then
    echo "MEASURE $id ERROR — fixture generation failed" | tee -a "$LOG"
    FAIL=1
    continue
  fi
  [ -s "$fixture" ] || { echo "MEASURE $id ERROR — empty fixture" | tee -a "$LOG"; FAIL=1; continue; }
  run_leg "$id" "$fixture" || FAIL=1
done

VERDICT=FAIL
[ "$FAIL" -eq 0 ] && VERDICT=PASS
echo "VERDICT: $VERDICT" | tee -a "$LOG"

RUN_ID="qauto06-corpus-$(date +%Y%m%d%H%M%S)-$$"
REC_RUN_ID="$RUN_ID" REC_PHASE=measurement REC_EXPECTED=PASS \
REC_OBSERVED_STATE="COMPLETED" REC_VERDICT_PRESENT=true REC_AUTHORIZED=true \
  bash "$ROOT/scripts/record_measurement_verdict.sh" qauto06_media_corpus "$VERDICT" "$LOG" "${BASH_SOURCE[0]}"

echo "MEDIA COMPATIBILITY CORPUS $VERDICT (record $RUN_ID)"
[ "$VERDICT" = "PASS" ] || exit 1
