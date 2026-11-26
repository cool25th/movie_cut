#!/usr/bin/env bash
# QAUTO-03 — Export integrity gate (출력 무결성 게이트).
#
# The SAME project (import + color correction, so the custom compositor runs)
# is exported twice through the real app harness. The source fixture carries
# BOTH a video and an audio track (h264 + aac, 2.000s) so the A/V axes are
# meaningful — the first draft used a silent fixture and its own fail-closed
# guard caught the empty audio probe. The contract is judged on DECODED
# output, not the bitstream:
#
#   R1 repeatability — rep1 vs rep2 must be decoded-identical:
#        md5(png) of one frame at each of 3 probe times (head/mid/tail)
#        equal across reps, and md5(s16le PCM) of the whole audio track
#        equal across reps. Container byte equality is NOT asserted
#        (timestamps may differ); both sizes are recorded as observation.
#   R2 stream contract — ffprobe stream fields identical across reps and
#        equal to the pre-registered expectations: h264 + aac, container
#        duration 2.0s +/- 0.1 (the fixture contract; F1.5 export E2E
#        established the codec profile).
#        fps/geometry/pix_fmt/rotation are recorded and asserted
#        cross-rep-identical (values recorded as the first baseline).
#   R3 A/V sync drift — |video.duration - audio.duration| <= 0.010s in
#        every export (pre-registered).
#
# Fail-closed guards (the empty-pass lesson, QAUTO-01): a missing or empty
# probe value is an ERROR (exit 2), never a pass; any ffprobe/ffmpeg failure
# aborts the leg.
#
# Axis family (QAUTO-03 requirement: integrate with the existing axes):
#   determinism = this gate; disk-full ENOSPC = run_diskfull_gate.sh;
#   cancel = e2e cancel gate + iOS ExportCancelMidFlight CI. Pointers are
#   recorded in the verdict record so the three axes read as one family.
#
# Usage: bash scripts/run_export_integrity_gate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 2; }
command -v ffmpeg  >/dev/null || { echo "ffmpeg required" >&2;  exit 2; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }

# Disk guard preflight (QAUTO-07): BLOCK/STOP refuse to start (rc 2/3).
if [ -x "$ROOT/scripts/disk_guard.sh" ]; then
  "$ROOT/scripts/disk_guard.sh" >/dev/null 2>&1 || {
    rc=$?
    echo "ERROR: disk guard refuses new measurement (rc=$rc) — aborting" >&2
    exit 2
  }
fi

FIXTURE="$ROOT/Tests/Fixtures/solid_red_tone_320x240_2s_30fps.mp4"
[ -s "$FIXTURE" ] || { echo "missing fixture" >&2; exit 2; }

echo "Building MovieCutMac (Debug, sandbox OFF)..."
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
APP_BIN="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 2; }

WORK="$(mktemp -d /tmp/moviecut-qauto03.XXXXXX)"
LOG="$WORK/measure.log"
cleanup() {
  rm -rf "$WORK"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true
}
trap cleanup EXIT

# run_export <out-file>: one harness export of the fixed scenario.
run_export() {
  local out="$1"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 2
  rm -f "$out"
  env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$FIXTURE" \
    MOVIECUT_UITEST_COLOR=1 \
    MOVIECUT_UITEST_EXPORT="$out" MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >"$WORK/app-$(basename "$out").log" 2>&1 &
  local pid=$!
  ( sleep 180; kill "$pid" 2>/dev/null; true ) & local wd=$!
  for _ in $(seq 1 360); do
    [ -s "$out" ] && break
    sleep 0.5
  done
  if [ ! -s "$out" ]; then
    echo "MEASURE export artifact missing: $out" | tee -a "$LOG"
    return 1
  fi
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true
  return 0
}

# probe <rep-name> <file> <out-keyfile>: emits key=value probe facts.
probe() {
  local name="$1" f="$2" keys="$3"
  local ff
  ff="$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,r_frame_rate,width,height,pix_fmt \
    -of default=noprint_wrappers=1 "$f" 2>/dev/null)" || return 2
  local v_codec v_fps v_dim v_pix v_w v_h
  v_codec="$(echo "$ff" | awk -F= '/^codec_name=/{print $2; exit}')"
  v_fps="$(echo "$ff"   | awk -F= '/^r_frame_rate=/{print $2; exit}')"
  v_w="$(echo "$ff"     | awk -F= '/^width=/{print $2; exit}')"
  v_h="$(echo "$ff"     | awk -F= '/^height=/{print $2; exit}')"
  v_dim="${v_w}x${v_h}"
  v_pix="$(echo "$ff"   | awk -F= '/^pix_fmt=/{print $2; exit}')"
  local a_codec a_rate a_ch
  a_codec="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f" 2>/dev/null)"
  a_rate="$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$f" 2>/dev/null)"
  a_ch="$(ffprobe   -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$f" 2>/dev/null)"
  local v_dur a_dur f_dur
  v_dur="$(ffprobe -v error -select_streams v:0 -show_entries stream=duration -of csv=p=0 "$f" 2>/dev/null)"
  a_dur="$(ffprobe -v error -select_streams a:0 -show_entries stream=duration -of csv=p=0 "$f" 2>/dev/null)"
  f_dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)"
  local rot
  rot="$(ffprobe -v error -select_streams v:0 -show_entries side_data=rotation -of csv=p=0 "$f" 2>/dev/null | tr -d '[:space:]')"

  # Fail-closed: every asserted field must be non-empty BEFORE any comparison
  # (an empty value compared equal would be the empty-pass class).
  local k
  for k in v_codec v_fps v_dim v_pix a_codec a_rate a_ch v_dur a_dur f_dur; do
    eval "val=\${$k}"
    if [ -z "$val" ]; then
      echo "MEASURE $name probe field $k is empty — fail-closed" | tee -a "$LOG"
      return 2
    fi
  done

  # Probe frames: head=0, mid=dur/2, tail=dur-0.1 (clamped). Output seeking
  # (decode-and-drop) keeps frame selection precise for a 2s file.
  local t_mid t_tail
  t_mid="$(python3 -c "print(round($f_dur/2, 3))")"
  t_tail="$(python3 -c "print(round(max(0.0, $f_dur-0.1), 3))")"
  local fh fm ft ah
  fh="$(ffmpeg -v error -i "$f" -ss 0     -frames:v 1 -f image2pipe -c:v png pipe:1 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  fm="$(ffmpeg -v error -i "$f" -ss "$t_mid" -frames:v 1 -f image2pipe -c:v png pipe:1 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  ft="$(ffmpeg -v error -i "$f" -ss "$t_tail" -frames:v 1 -f image2pipe -c:v png pipe:1 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  ah="$(ffmpeg -v error -i "$f" -map 0:a:0 -vn -f s16le -acodec pcm_s16le pipe:1 2>/dev/null | shasum -a 256 | awk '{print $1}')"
  for k in fh fm ft ah; do
    eval "val=\${$k}"
    # sha256 of the EMPTY string: a failed ffmpeg decode piped to shasum
    # still emits this digest — that must never count as a probe value.
    if [ -z "$val" ] || [ "$val" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then
      echo "MEASURE $name decoded probe $k is empty — fail-closed" | tee -a "$LOG"
      return 2
    fi
  done

  {
    echo "v_codec=$v_codec"
    echo "v_fps=$v_fps"
    echo "v_dim=$v_dim"
    echo "v_pix=$v_pix"
    echo "a_codec=$a_codec"
    echo "a_rate=$a_rate"
    echo "a_ch=$a_ch"
    echo "v_dur=$v_dur"
    echo "a_dur=$a_dur"
    echo "f_dur=$f_dur"
    echo "rot=${rot:-none}"
    echo "md5_head=$fh"
    echo "md5_mid=$fm"
    echo "md5_tail=$ft"
    echo "md5_audio=$ah"
    echo "size=$(stat -f%z "$f")"
  } > "$keys"
}

# get <keyfile> <key>
get() { awk -F= -v k="$2" '$1==k{print $2; exit}' "$1"; }

echo "=== QAUTO-03 export integrity (rep1 + rep2, decoded identity) ==="
run_export "$WORK/rep1.mp4" || { echo "VERDICT: ERROR rep1 export did not produce an artifact" | tee -a "$LOG"; exit 2; }
run_export "$WORK/rep2.mp4" || { echo "VERDICT: ERROR rep2 export did not produce an artifact" | tee -a "$LOG"; exit 2; }

probe rep1 "$WORK/rep1.mp4" "$WORK/rep1.keys" || { echo "VERDICT: ERROR rep1 probe failed" | tee -a "$LOG"; exit 2; }
probe rep2 "$WORK/rep2.mp4" "$WORK/rep2.keys" || { echo "VERDICT: ERROR rep2 probe failed" | tee -a "$LOG"; exit 2; }

fail=0

# R1 — decoded identity across reps (frames + audio PCM).
for k in md5_head md5_mid md5_tail md5_audio; do
  if [ "$(get "$WORK/rep1.keys" "$k")" = "$(get "$WORK/rep2.keys" "$k")" ]; then
    echo "  R1 $k identical across reps" | tee -a "$LOG"
  else
    echo "  R1 $k DIFFERS across reps (decoded output not deterministic)" | tee -a "$LOG"
    fail=1
  fi
done

# R2 — stream contract: cross-rep identity + pre-registered expectations.
for k in v_codec v_fps v_dim v_pix a_codec a_rate a_ch rot; do
  if [ "$(get "$WORK/rep1.keys" "$k")" != "$(get "$WORK/rep2.keys" "$k")" ]; then
    echo "  R2 stream field $k differs across reps" | tee -a "$LOG"
    fail=1
  fi
done
echo "  R2 stream contract: v=$(get "$WORK/rep1.keys" v_codec)/$(get "$WORK/rep1.keys" v_dim)/$(get "$WORK/rep1.keys" v_fps)/$(get "$WORK/rep1.keys" v_pix) a=$(get "$WORK/rep1.keys" a_codec)/$(get "$WORK/rep1.keys" a_rate)Hz/$(get "$WORK/rep1.keys" a_ch)ch rot=$(get "$WORK/rep1.keys" rot)" | tee -a "$LOG"
if [ "$(get "$WORK/rep1.keys" v_codec)" != "h264" ] || [ "$(get "$WORK/rep1.keys" a_codec)" != "aac" ]; then
  echo "  R2 codec expectation h264+aac NOT met" | tee -a "$LOG"
  fail=1
fi
for rep in rep1 rep2; do
  ok="$(python3 -c "d=float('$(get "$WORK/$rep.keys" f_dur)'); print(1 if abs(d-2.0)<=0.1 else 0)")"
  if [ "$ok" = "1" ]; then
    echo "  R2 $rep container duration $(get "$WORK/$rep.keys" f_dur)s within 2.0±0.1" | tee -a "$LOG"
  else
    echo "  R2 $rep container duration $(get "$WORK/$rep.keys" f_dur)s OUTSIDE 2.0±0.1" | tee -a "$LOG"
    fail=1
  fi
done

# R3 — A/V sync drift per export (<= 0.010s, pre-registered).
for rep in rep1 rep2; do
  drift="$(python3 -c "print(round(abs(float('$(get "$WORK/$rep.keys" v_dur)')-float('$(get "$WORK/$rep.keys" a_dur)')),6))")"
  ok="$(python3 -c "print(1 if $drift<=0.010 else 0)")"
  if [ "$ok" = "1" ]; then
    echo "  R3 $rep A/V drift ${drift}s <= 0.010" | tee -a "$LOG"
  else
    echo "  R3 $rep A/V drift ${drift}s > 0.010 — FAIL" | tee -a "$LOG"
    fail=1
  fi
done

echo "  observation: sizes rep1=$(get "$WORK/rep1.keys" size) rep2=$(get "$WORK/rep2.keys" size) (byte equality not asserted)" | tee -a "$LOG"
echo "  axis family: determinism=this gate · ENOSPC=run_diskfull_gate.sh · cancel=e2e cancel gate + iOS ExportCancelMidFlight CI" | tee -a "$LOG"

VERDICT=FAIL
[ "$fail" -eq 0 ] && VERDICT=PASS
echo "VERDICT: $VERDICT" | tee -a "$LOG"

# QAUTO-01 recorder: bind the verdict to app commit + harness sha.
RUN_ID="qauto03-$(date +%Y%m%d%H%M%S)-$$"
REC_RUN_ID="$RUN_ID" REC_PHASE=measurement REC_EXPECTED=PASS \
REC_OBSERVED_STATE="COMPLETED" REC_VERDICT_PRESENT=true REC_AUTHORIZED=true \
  bash "$ROOT/scripts/record_measurement_verdict.sh" qauto03_export_integrity "$VERDICT" "$LOG" "${BASH_SOURCE[0]}"

echo "EXPORT INTEGRITY GATE $VERDICT (record $RUN_ID)"
[ "$VERDICT" = "PASS" ] || exit 1
