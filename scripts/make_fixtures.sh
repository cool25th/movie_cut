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
# Color tags are added per-fixture where the test cares (see the color-matrix
# block below); the default COMMON_V leaves color untagged so the original
# tiny fixtures stay byte-identical to their committed forms.
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

# 2c) Moving subject behind an occluding wall — same textured box and
# trajectory, 3s clip, with a mid-gray full-height wall at x=120..216 drawn ON
# TOP. Box path [32+80t, 104+80t]: first touches the wall at t=0.2, fully
# occluded t=[1.1, 1.4], fully emerged again from t=2.3 — the window the T2-M
# occlusion-reacquisition measurement uses (dip + recovery).
ffmpeg -y -loglevel error \
  -f lavfi -i "color=c=black:s=320x240:r=30:d=3" \
  -f lavfi -i "color=c=white:s=72x64:r=30:d=3" \
  -f lavfi -i "color=c=0x808080:s=96x240:r=30:d=3" \
  -filter_complex "[1:v]drawbox=x=8:y=8:w=56:h=48:color=black@1:t=4,drawbox=x=30:y=0:w=12:h=64:color=black@1:t=fill,drawbox=x=0:y=24:w=72:h=8:color=black@1:t=fill,drawbox=x=4:y=4:w=12:h=12:color=white@1:t=fill,drawbox=x=56:y=48:w=12:h=12:color=white@1:t=fill[obj];[0:v][obj]overlay=x='32+80*t':y=88:eval=frame[boxed];[boxed][2:v]overlay=x=120:y=0" \
  -t 3 "${COMMON_V[@]}" "$OUT/moving_subject_occluded_320x240_3s_30fps.mp4"

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

# 5) Color-space matrix — minimal 1080p clips for import-side resolution/parity
# coverage. Deliberately SHORT (1s) and solid-color so they stay small, but real
# 1080p/720p so the harness exercises a representative resolution.
#
# NOTE on color-tag verification: ffmpeg's libx264 ultrafast preset does NOT
# reliably write the VUI color-primaries/transfer tags into these fixtures
# (ffprobe shows primaries/transfer as None, matrix as bt709). So these clips
# are valid IMPORT inputs but they are NOT a ground-truth for
# verify_export_color_metadata.py. That script must be run against a file
# produced by MovieCut's own AVAssetWriter path (which writes
# AVVideoColorPropertiesKey explicitly per the v1 Rec.709 contract). The 4K
# matrix + real camera-origin fixtures (rotation metadata, DisplayP3/HDR) are
# deferred per the render-reliability plan.
COLOR_V=(-pix_fmt yuv420p -c:v libx264 -preset ultrafast -map_metadata -1
  -movflags +faststart -fflags +bitexact
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 -color_range tv)

# 5a) 1080p 30fps Rec.709-tagged — the v1 contract baseline.
ffmpeg -y -loglevel error -f lavfi -i "color=c=0x804020:s=1920x1080:r=30" \
  -t 1 "${COLOR_V[@]}" "$OUT/rec709_1080p_1s_30fps.mp4"

# 5b) 1080p 24fps Rec.709-tagged — cinema frame-rate parity input.
ffmpeg -y -loglevel error -f lavfi -i "color=c=0x208040:s=1920x1080:r=24" \
  -t 1 "${COLOR_V[@]}" "$OUT/rec709_1080p_1s_24fps.mp4"

# 5c) 720p portrait Rec.709-tagged — 9:16 short-edge fixture.
ffmpeg -y -loglevel error -f lavfi -i "color=c=0x402080:s=720x1280:r=30" \
  -t 1 "${COLOR_V[@]}" "$OUT/rec709_720p_portrait_1s_30fps.mp4"

echo ""
echo "Generated:"
for f in "$OUT"/*; do
  [ "$(basename "$f")" = "README.md" ] && continue
  size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f")
  printf "  %-36s %6s bytes\n" "$(basename "$f")" "$size"
done
# --- G-24 P2-G24-6b: REAL wobble fixture ------------------------------------------
# High-contrast scene cut over a STATIC blurred-noise texture with multi-
# frequency handheld jitter. Four #9 real-render lessons baked in:
# 1) A gentle 1Hz sway is NOT representative shake — its deviation from a
#    window-7 smoothed path (~0.6px) sits below the registration noise
#    floor. Two sine components per axis put the true jitter ~5px.
# 2) The texture must be APERIODIC (testsrc2's periodic grid made SAD
#    registration lock onto grid periods: 19.5px readback errors).
# 3) The texture must be STATIC (mandelbrot is an animated zoom — its
#    apparent radial motion biased registrations by up to ~5px per frame).
# 4) The frame is 16:9 (640×360): the export path renders at preset
#    resolutions (short edge ≥720) with the canvas aspect, and an
#    identity-transform clip lands 1:1 in the corner. With a 16:9 source
#    on the default 16:9 canvas, extracting at source-native size brings
#    the content back to exactly 1:1 — the DoD measures the compositor's
#    warp at native scale regardless of export preset. Scene cut: eq
#    brightness −0.3 → +0.3 keeps the luminance jump detectable.
STAB="$OUT/stab_wobble_640x360_4s_30fps.mp4"
if [ ! -f "$STAB" ]; then
  NOISE="$(mktemp -u /tmp/stab_noise.XXXXXX).png"
  SEG_A="$(mktemp -u /tmp/stab_a.XXXXXX).mp4"
  SEG_B="$(mktemp -u /tmp/stab_b.XXXXXX).mp4"
  ffmpeg -y -loglevel error \
    -f lavfi -i "color=c=black:s=800x450:d=1" -frames:v 1 \
    -vf "geq=lum='random(1)*255':cb=128:cr=128,boxblur=4:1" "$NOISE"
  ffmpeg -y -loglevel error \
    -loop 1 -framerate 30 -t 2 -i "$NOISE" \
    -vf "eq=brightness=-0.3:contrast=1.3,crop=640:360:x='30+8*sin(2*PI*2.2*t)+4*sin(2*PI*6.7*t+1.3)':y='20+6*sin(2*PI*1.7*t+0.5)+3*sin(2*PI*5.3*t+2.1)',format=yuv420p" \
    -c:v libx264 -preset veryfast -crf 18 "$SEG_A"
  ffmpeg -y -loglevel error \
    -loop 1 -framerate 30 -t 2 -i "$NOISE" \
    -vf "eq=brightness=0.3:contrast=1.3,crop=640:360:x='30+8*sin(2*PI*2.2*t)+4*sin(2*PI*6.7*t+1.3)':y='20+6*sin(2*PI*1.7*t+0.5)+3*sin(2*PI*5.3*t+2.1)',format=yuv420p" \
    -c:v libx264 -preset veryfast -crf 18 "$SEG_B"
  ffmpeg -y -loglevel error -i "$SEG_A" -i "$SEG_B" \
    -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0[out]" \
    -map "[out]" -c:v libx264 -preset veryfast -crf 18 "$STAB"
  rm -f "$NOISE" "$SEG_A" "$SEG_B"
  echo "generated: stab_wobble_640x360_4s_30fps.mp4 (dark→bright static-noise multi-frequency jitter)"
fi
