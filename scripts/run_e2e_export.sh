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

echo "E2E check OK (import->export + freeze + noise reduction SNR + EQ spectrum + ducking RMS + color grade + scope + prores + hdr + autosave)"
