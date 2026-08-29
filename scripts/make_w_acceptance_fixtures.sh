#!/bin/bash
# STAB-04: representative-length W acceptance fixtures — generated on
# demand into a work directory (never committed; multi-minute media).
#
#   w1_voice_60s.wav     60 s REAL speech (macOS `say`, short sentences for
#                        natural pauses) — STT must transcribe it and the
#                        ducking analysis must find the gaps.
#   w1_portrait_60s.mp4  60 s 720x1280 vertical video (deterministic).
#   w1_bgm_60s.wav       60 s continuous BGM bed.
#   w2_beats_60s.wav     60 s deterministic 120 BPM onsets (~120 beats).
#   w2_video_60s.mp4     60 s video for the beat-sync job.
#   w4_video_300s.mp4    5-minute 1280x720 master video.
#   w4_voice_300s.wav    5-minute speech (the 60 s take x5).
#   w4_bgm_300s.wav      5-minute BGM bed.
#
# Usage: bash scripts/make_w_acceptance_fixtures.sh [out-dir]
set -euo pipefail

OUT="${1:?usage: make_w_acceptance_fixtures.sh <out-dir>}"
mkdir -p "$OUT"

command -v say >/dev/null || { echo "macOS 'say' is required for real-speech fixtures" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }

# ~75 s of short sentences — pauses between sentences give the ducking
# analysis real gaps; the take is trimmed/padded to exactly 60 s below.
TEXT="$(cat <<'EOF'
This is a short video about making movies on a small budget. Today we will
edit a one minute clip together. First we import the footage. Then we clean
up the background noise. Next we add background music. The music gets
quieter whenever someone is speaking. We also add subtitles automatically.
Subtitles help people watching without sound. After that we pick a title
style. A bright highlight color keeps the text readable. Then we check the
vertical framing. Phones show video upright. Finally we export the project.
The export takes a moment. The result is ready to post. Making short videos
should feel quick. A good editor stays out of the way. Thanks for watching
this short clip. See you in the next one. Goodbye for now. Hello again.
This sentence exists to add a little more speaking time. And one more line.
EOF
)"

say -o "$OUT/_voice_take.aiff" "$TEXT" \
  || { echo "say fixture generation failed" >&2; exit 1; }

# 60 s exact: pad the take to at least 60 s, then trim to 60 s.
ffmpeg -hide_banner -loglevel error -y -i "$OUT/_voice_take.aiff" \
  -af "apad" -t 60 -ar 44100 "$OUT/w1_voice_60s.wav"
ffmpeg -hide_banner -loglevel error -y -stream_loop 4 \
  -i "$OUT/w1_voice_60s.wav" -c copy -t 300 "$OUT/w4_voice_300s.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "sine=frequency=220:duration=60" -ar 44100 "$OUT/w1_bgm_60s.wav"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "sine=frequency=196:duration=300" -ar 44100 "$OUT/w4_bgm_300s.wav"
# w2 beats: 120 BPM (2 Hz onsets) — a realistic tempo; 60 s should yield
# ~120 detectable beats (v1 assert: >= 60). The earlier 4 Hz draft (240 BPM)
# is musically unrealistic and the detector deduped it down to 6 markers.
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "aevalsrc='0.8*sin(440*2*PI*t)*mod(floor(t*2)\,2)':d=60:s=44100" \
  "$OUT/w2_beats_60s.wav"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=720x1280:rate=30" -t 60 \
  -pix_fmt yuv420p -c:v libx264 -preset veryfast -crf 28 "$OUT/w1_portrait_60s.mp4"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1280x720:rate=30" -t 60 \
  -pix_fmt yuv420p -c:v libx264 -preset veryfast -crf 28 "$OUT/w2_video_60s.mp4"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1280x720:rate=30" -t 300 \
  -pix_fmt yuv420p -c:v libx264 -preset veryfast -crf 28 "$OUT/w4_video_300s.mp4"

rm -f "$OUT/_voice_take.aiff"
echo "W ACCEPTANCE FIXTURES: $OUT"
for f in "$OUT"/w*_60s.* "$OUT"/w*_300s.*; do
  printf '  %-22s %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
done
