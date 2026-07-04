#!/usr/bin/env bash
# Headless import → timeline → export end-to-end check (Phase 0.1c).
#
# Drives the real app pipeline via the DEBUG launch harness (env vars), without
# needing XCUITest's Accessibility/Automation permission. Asserts a genuine
# movie file is produced with the expected duration. Complements
# App/MovieCutMacUITests (which needs an interactive Accessibility grant).
#
# Usage:  bash scripts/run_e2e_export.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
[ -s "$FIXTURE" ] || { echo "missing fixture; run scripts/make_fixtures.sh" >&2; exit 1; }

echo "Building MovieCutMac (Debug)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' build >/dev/null

PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found at $APP_BIN" >&2; exit 1; }

# Kill any lingering harness instance so sequential launches don't interfere.
pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true
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
for _ in $(seq 1 120); do [ -s "$FREEZE_OUT" ] && break; sleep 0.5; done
wait "$FP" 2>/dev/null || true
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
for _ in $(seq 1 240); do [ -s "$OF_OUT" ] && break; sleep 0.5; done
wait "$OFP" 2>/dev/null || true
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

# Noise reduction must run the real AVAudioEngine DSP in the app context without
# crashing (the offline-render path aborts under `swift test`).
TONE="$ROOT/Tests/Fixtures/tone_440hz_2s_mono.wav"
NR_RESULT="$(mktemp -d)/nr.txt"
MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$TONE" MOVIECUT_UITEST_DENOISE=1 \
  MOVIECUT_UITEST_RESULT="$NR_RESULT" MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
NP=$!
for _ in $(seq 1 120); do [ -s "$NR_RESULT" ] && break; sleep 0.5; done
wait "$NP" 2>/dev/null || true
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
  for _ in $(seq 1 240); do [ -s "$out" ] && break; sleep 0.5; done
  wait "$pp" 2>/dev/null || true

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

# HDR master must export as 10-bit HEVC with Rec.2020 + HLG tags.
HDR_OUT="$(mktemp -d)/hdr.mov"
env MOVIECUT_UITEST=1 MOVIECUT_UITEST_IMPORT="$BARS" MOVIECUT_UITEST_EXPORT_HDR="$HDR_OUT" \
  MOVIECUT_UITEST_QUIT=1 "$APP_BIN" >/dev/null 2>&1 &
HP=$!; for _ in $(seq 1 180); do [ -s "$HDR_OUT" ] && break; sleep 0.5; done; wait "$HP" 2>/dev/null || true
HDR_TAGS="$(ffprobe -v error -select_streams v -show_entries stream=pix_fmt,color_transfer,color_primaries -of csv=p=0 "$HDR_OUT" 2>/dev/null)"
rm -rf "$(dirname "$HDR_OUT")"
case "$HDR_TAGS" in
  *yuv420p10le*arib-std-b67*bt2020*) echo "PASS: HDR master exported (10-bit HLG Rec.2020: $HDR_TAGS)" ;;
  *) echo "FAIL: HDR export missing 10-bit/HLG/Rec.2020 tags ($HDR_TAGS)" >&2; exit 1 ;;
esac

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

echo "E2E check OK (import->export + freeze + optical-flow slow motion + noise reduction SNR + EQ spectrum + audio extraction + ducking RMS + platform presets + color grade + scope + prores + hdr + autosave)"
