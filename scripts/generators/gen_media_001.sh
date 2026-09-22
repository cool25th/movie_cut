#!/usr/bin/env bash
# GEN_MEDIA_001 — the first REAL generated media fixture (29th-cycle).
# Minimal composition on purpose: the goal is GENERATOR DETERMINISM
# verification, not media-quality verification.
#   video: 1920x1080, 30fps, 2.0s, one fixed color (0x202040)
#   audio: 48kHz stereo, fixed 440Hz sine
#   container: mp4 (h264 + aac)
#
# Determinism contract (observed 2026-09-23): plain ffmpeg (Lavf62) without
# bitexact flags already produces byte-identical mp4 across processes —
# no creation_time tag is written unless explicitly requested, and the
# encoder tag is a fixed version string. The generation E2E asserts this
# with two clean-process builds (H1 == H2); a divergence is reported as
# NONDETERMINISTIC_GENERATION and STOPS the chain — it is never patched
# over with a rebaseline.
#
# Usage: gen_media_001.sh <output.mp4>
set -euo pipefail
OUT="${1:?output path required}"
mkdir -p "$(dirname "$OUT")"
# aevalsrc generates BOTH stereo channels directly (sine filter is mono —
# the first build exposed that as an audio-contract mismatch).
exec ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i "color=c=0x202040:s=1920x1080:r=30:d=2" \
  -f lavfi -i "aevalsrc=0.12*sin(2*PI*440*t)|0.12*sin(2*PI*440*t):s=48000:d=2" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$OUT"
