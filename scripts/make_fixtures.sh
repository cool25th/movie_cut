#!/usr/bin/env bash
# Generate the deterministic media fixture set used by behavioral / golden /
# E2E tests (Phase 0.1a). Tiny, known-property clips so tests do not depend on
# ffmpeg at run time — the generated artifacts are committed under Tests/Fixtures/.
#
# Re-run this only when intentionally changing the fixtures. Requires ffmpeg.
#
# Usage:  bash scripts/make_fixtures.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/Tests/Fixtures"
mkdir -p "$OUT"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg not found. Install with: brew install ffmpeg" >&2
  exit 1
fi

# bit-exact-ish flags + stripped metadata keep output reproducible run-to-run.
COMMON_V=(-pix_fmt yuv420p -c:v libx264 -preset ultrafast -map_metadata -1 -movflags +faststart -fflags +bitexact)

echo "Generating fixtures into $OUT"

# 1) Solid red video — known duration 2.0s, 320x240, 30fps (import metadata probe).
ffmpeg -y -loglevel error -f lavfi -i "color=c=red:s=320x240:r=30" \
  -t 2 "${COMMON_V[@]}" "$OUT/solid_red_320x240_2s_30fps.mp4"

# 1b) Solid red video with a 440Hz mono audio stream — same video envelope as
# the import fixture, but with deterministic audio for Extract Audio E2E.
ffmpeg -y -loglevel error \
  -f lavfi -i "color=c=red:s=320x240:r=30" \
  -f lavfi -i "sine=frequency=440:sample_rate=44100" \
  -map 0:v:0 -map 1:a:0 -t 2 "${COMMON_V[@]}" \
  -c:a aac -b:a 96k -ac 1 "$OUT/solid_red_tone_320x240_2s_30fps.mp4"

# 2) Color-bars video — distinguishable second clip, 3.0s, 320x240, 30fps.
ffmpeg -y -loglevel error -f lavfi -i "testsrc2=s=320x240:r=30" \
  -t 3 "${COMMON_V[@]}" "$OUT/bars_320x240_3s_30fps.mp4"

# 2b) Moving high-contrast subject — black background with a textured white box
# moving left-to-right for Vision motion-tracking IoU verification.
ffmpeg -y -loglevel error \
  -f lavfi -i "color=c=black:s=320x240:r=30:d=2" \
  -f lavfi -i "color=c=white:s=72x64:r=30:d=2" \
  -filter_complex "[1:v]drawbox=x=8:y=8:w=56:h=48:color=black@1:t=4,drawbox=x=30:y=0:w=12:h=64:color=black@1:t=fill,drawbox=x=0:y=24:w=72:h=8:color=black@1:t=fill,drawbox=x=4:y=4:w=12:h=12:color=white@1:t=fill,drawbox=x=56:y=48:w=12:h=12:color=white@1:t=fill[obj];[0:v][obj]overlay=x='32+80*t':y=88:eval=frame" \
  -t 2 "${COMMON_V[@]}" "$OUT/moving_subject_320x240_2s_30fps.mp4"

# 3) Sine tone — audio import, 2.0s, 44100Hz mono.
ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=440:sample_rate=44100" \
  -t 2 -ac 1 -map_metadata -1 -fflags +bitexact "$OUT/tone_440hz_2s_mono.wav"

# 3b) Equalizer sweep pair — simultaneous low/high tones for deterministic
# spectrum-ratio E2E checks. 110Hz is in the bass shelf; 4kHz is in the treble
# shelf, and both start at equal amplitude so bassBoost/trebleBoost diverge.
ffmpeg -y -loglevel error \
  -f lavfi -i "sine=frequency=110:sample_rate=44100" \
  -f lavfi -i "sine=frequency=4000:sample_rate=44100" \
  -filter_complex "[0:a][1:a]amix=inputs=2:duration=shortest:normalize=0,volume=0.5" \
  -t 2 -ac 1 -map_metadata -1 -fflags +bitexact "$OUT/eq_low_high_2s_mono.wav"

# 3c) Noise reduction fixture — 1kHz voice-band carrier plus 8kHz hiss-like
# deterministic tone. The NR E2E checks that the app path lowers 8kHz/1kHz
# energy while preserving the voice-band component.
ffmpeg -y -loglevel error \
  -f lavfi -i "sine=frequency=1000:sample_rate=44100" \
  -f lavfi -i "sine=frequency=8000:sample_rate=44100" \
  -filter_complex "[0:a]volume=0.7[voice];[1:a]volume=0.35[hiss];[voice][hiss]amix=inputs=2:duration=shortest:normalize=0" \
  -t 2 -ac 1 -map_metadata -1 -fflags +bitexact "$OUT/noisy_voice_1k_hiss_8k_2s_mono.wav"

# 3d) Ducking pair — continuous 220Hz BGM under a 1kHz voice cue. The E2E
# measures only the 220Hz component, so the voice cue does not contaminate the
# BGM attenuation proof.
ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=220:sample_rate=44100" \
  -t 4 -ac 1 -af "volume=0.6" -map_metadata -1 -fflags +bitexact "$OUT/duck_bgm_220hz_4s_mono.wav"
ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=1000:sample_rate=44100" \
  -t 1 -ac 1 -af "volume=0.45" -map_metadata -1 -fflags +bitexact "$OUT/duck_voice_1000hz_1s_mono.wav"

# 4) Solid blue still — image import, 64x64 PNG.
ffmpeg -y -loglevel error -f lavfi -i "color=c=blue:s=64x64" \
  -frames:v 1 -map_metadata -1 -fflags +bitexact "$OUT/swatch_blue_64x64.png"

echo ""
echo "Generated:"
for f in "$OUT"/*; do
  [ "$(basename "$f")" = "README.md" ] && continue
  size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f")
  printf "  %-36s %6s bytes\n" "$(basename "$f")" "$size"
done
