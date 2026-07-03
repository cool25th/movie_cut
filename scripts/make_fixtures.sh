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

# 2) Color-bars video — distinguishable second clip, 3.0s, 320x240, 30fps.
ffmpeg -y -loglevel error -f lavfi -i "testsrc2=s=320x240:r=30" \
  -t 3 "${COMMON_V[@]}" "$OUT/bars_320x240_3s_30fps.mp4"

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
