#!/usr/bin/env bash
# Actual-app integration proof for task 3.7. It applies vocal separation through
# EditorViewModel, renders Preview's installed composition/audio mix, exports the
# project audio, decodes both to stereo PCM, and verifies mid/side RMS behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }

DERIVED_DATA="${MOVIECUT_VOCAL_DERIVED_DATA:-/tmp/MovieCutVocalIntegrationDerivedData}"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
  ENABLE_DEBUG_DYLIB=NO build >/dev/null

PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
  ENABLE_DEBUG_DYLIB=NO -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BUNDLE="$PRODUCTS_DIR/MovieCutMac.app"
APP_BIN="$APP_BUNDLE/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found at $APP_BIN" >&2; exit 1; }

APP_TMP="$HOME/Library/Containers/com.moviecut.mac/Data/tmp/moviecut-vocal-integration"
mkdir -p "$APP_TMP"
WORK_DIR="$(mktemp -d "$APP_TMP/run.XXXXXX")"
INPUT_WAV="$WORK_DIR/center-side.wav"
PREVIEW_M4A="$WORK_DIR/preview.m4a"
EXPORT_M4A="$WORK_DIR/export.m4a"
RESULT_TXT="$WORK_DIR/result.txt"
trap 'rm -rf "$WORK_DIR"' EXIT

python3 - "$INPUT_WAV" <<'PY'
import math
import struct
import sys
import wave

path = sys.argv[1]
sample_rate = 44100
duration = 2.0
center_amplitude = 0.35
side_amplitude = 0.30
with wave.open(path, "wb") as output:
    output.setnchannels(2)
    output.setsampwidth(2)
    output.setframerate(sample_rate)
    frames = bytearray()
    for index in range(int(sample_rate * duration)):
        t = index / sample_rate
        center = center_amplitude * math.sin(2 * math.pi * 440 * t)
        side = side_amplitude * math.sin(2 * math.pi * 988 * t)
        left = max(-1.0, min(1.0, center + side))
        right = max(-1.0, min(1.0, center - side))
        frames.extend(struct.pack("<hh", round(left * 32767), round(right * 32767)))
    output.writeframes(frames)
PY

open -n -W \
  --env "MOVIECUT_UITEST=1" \
  --env "MOVIECUT_UITEST_IMPORT=$INPUT_WAV" \
  --env "MOVIECUT_UITEST_VOCAL_SEPARATION=removeVocals" \
  --env "MOVIECUT_UITEST_PREVIEW_AUDIO=$PREVIEW_M4A" \
  --env "MOVIECUT_UITEST_EXPORT_AUDIO=$EXPORT_M4A" \
  --env "MOVIECUT_UITEST_RESULT=$RESULT_TXT" \
  --env "MOVIECUT_UITEST_QUIT=1" \
  "$APP_BUNDLE" >/dev/null 2>&1 &
APP_WAITER=$!

for _ in $(seq 1 360); do
  if [ -s "$RESULT_TXT" ] && [ -s "$PREVIEW_M4A" ] && [ -s "$EXPORT_M4A" ]; then
    break
  fi
  sleep 0.5
done
wait "$APP_WAITER" 2>/dev/null || true

STATUS="$(cat "$RESULT_TXT" 2>/dev/null || echo MISSING)"
case "$STATUS" in
  *"error=none"*"vocal_mode=removeVocals"*"vocal_applied=1"*"preview_audio=1"*) ;;
  *) echo "FAIL: vocal harness did not complete successfully: $STATUS" >&2; exit 1 ;;
esac
[ -s "$PREVIEW_M4A" ] || { echo "FAIL: preview composition audio missing" >&2; exit 1; }
[ -s "$EXPORT_M4A" ] || { echo "FAIL: export audio missing" >&2; exit 1; }

METRICS="$(python3 - "$INPUT_WAV" "$PREVIEW_M4A" "$EXPORT_M4A" <<'PY'
import math
import struct
import subprocess
import sys


def decode(path):
    raw = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-ac", "2", "-ar", "44100", "-f", "f32le", "-"
    ])
    values = struct.unpack("<" + "f" * (len(raw) // 4), raw)
    if len(values) < 4:
        raise SystemExit(f"no stereo PCM decoded from {path}")
    left = values[0::2]
    right = values[1::2]
    mid = [(l + r) * 0.5 for l, r in zip(left, right)]
    side = [(l - r) * 0.5 for l, r in zip(left, right)]
    rms = lambda samples: math.sqrt(sum(value * value for value in samples) / len(samples))
    return rms(mid), rms(side)

input_mid, input_side = decode(sys.argv[1])
preview_mid, preview_side = decode(sys.argv[2])
export_mid, export_side = decode(sys.argv[3])

if input_mid <= 0.05 or input_side <= 0.05:
    raise SystemExit(f"invalid fixture energy mid={input_mid:.6f} side={input_side:.6f}")
for label, mid, side in [
    ("preview", preview_mid, preview_side),
    ("export", export_mid, export_side),
]:
    if mid >= input_mid / 10:
        raise SystemExit(f"{label} center not reduced enough: {mid:.6f} vs input {input_mid:.6f}")
    side_delta = abs(side - input_side) / input_side
    if side_delta >= 0.25:
        raise SystemExit(f"{label} side changed too much: {side:.6f} vs input {input_side:.6f}")

if abs(preview_side - export_side) / max(preview_side, 1e-9) >= 0.10:
    raise SystemExit(
        f"preview/export side mismatch: preview={preview_side:.6f} export={export_side:.6f}"
    )

print(
    f"input_mid={input_mid:.6f} input_side={input_side:.6f} "
    f"preview_mid={preview_mid:.6f} preview_side={preview_side:.6f} "
    f"export_mid={export_mid:.6f} export_side={export_side:.6f}"
)
PY
)" || { echo "FAIL: vocal PCM metrics failed" >&2; exit 1; }

echo "PASS: vocal separation preview/export PCM integration ($METRICS)"
