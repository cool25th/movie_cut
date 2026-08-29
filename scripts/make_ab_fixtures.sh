#!/usr/bin/env bash
# CA-12 A/B benchmark fixture set (COMPETITIVE_ANALYSIS Part 5 §3).
#
# Generates the 12 representative benchmark fixtures into
# artifacts/ab_benchmark/fixtures/ (gitignored — regenerable) and writes a
# manifest.json recording per-fixture ffmpeg parameters, SHA-256, size and
# probed metadata. Fixtures small enough to commit already live in
# Tests/Fixtures and are reused here; only the manifest pins them.
#
# The pinned SHA-256 table below IS the version control for the set: a
# regenerated fixture that does not match its pin fails the script, so
# benchmark numbers always name an exact fixture revision.
#
# Long-form fixtures (30 min / 2 h) are generated at reduced resolutions —
# every recorded number must be read with the fixture scale per §1.4, and
# the manifest records the exact geometry so this is mechanical.
#
# Usage:
#   bash scripts/make_ab_fixtures.sh            # generate missing + verify pins
#   bash scripts/make_ab_fixtures.sh --force    # regenerate everything
#   bash scripts/make_ab_fixtures.sh --print-pins  # pinned table as shell
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/artifacts/ab_benchmark/fixtures"
mkdir -p "$OUT"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1
if [ "${1:-}" = "--print-pins" ]; then
  grep -E '^#pin ' "$0" | awk '{print $2" "$3}'
  exit 0
fi

# --- pinned SHA-256 (fixture set version — regenerate & re-pin deliberately) --
#pin ab01_1080p30_10s.mp4 2c52262a660fde2610d29080cc288c3900b7eff57393c06c192ae67164599ee8
#pin ab02_2160p60_hevc_6s.mov 8721fdbfced49bb16a5e6bb12ff250f23a3283306f1b26ad470f815b1ab27678
#pin ab04_interview_640x360_30min.mp4 0a60a6787ba72e8b2936a2fe35bda3ff59221b4f82376a2c5dbcdedea9a0a986
#pin ab07_greenscreen_320x240_4s.mp4 d47ff2a2b88ab9c92de64272b7d833d448afcfeda5760177cc093734378769c3
#pin ab12_320x240_2h.mp4 a439b9129d32c67e866da29991c2b24d3a32c7b8f99593bda397ed302d12d2da

pin_for() {
  local line
  line="$(grep -E "^#pin $1 " "$0" | awk '{print $3}')"
  echo "${line:-}"
}

command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

GEN=()   # files this run generated (manifest entries)
REUSED=() # committed Tests/Fixtures files

gen() { # gen <filename> <ffmpeg args...>
  local name="$1"; shift
  if [ -f "$OUT/$name" ] && [ "$FORCE" -eq 0 ]; then
    echo "exists: $name"
  else
    echo "generating: $name"
    ffmpeg -v error -y "$@" "$OUT/$name"
  fi
  GEN+=("$name")
}

# ① 1080p30 single clip (10 s, motion + tone) — the base passthrough fixture.
gen ab01_1080p30_10s.mp4 \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=220:sample_rate=48000:duration=10" \
  -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p \
  -c:a aac -b:a 96k -shortest

# ② 4K60 HEVC (6 s) — heavy-codec import dimension.
gen ab02_2160p60_hevc_6s.mov \
  -f lavfi -i "testsrc2=size=3840x2160:rate=60:duration=6" \
  -c:v libx265 -preset ultrafast -crf 24 -pix_fmt yuv420p -tag:v hvc1

# ④ 30-minute interview stand-in (640x360, voice-like AM tone).
# Reduced resolution on purpose (disk + session budget); scale is a recorded
# condition field, not a hidden claim.
gen ab04_interview_640x360_30min.mp4 \
  -f lavfi -i "testsrc2=size=640x360:rate=30:duration=1800" \
  -f lavfi -i "sine=frequency=180:sample_rate=44100:duration=1800" \
  -af "tremolo=f=2:d=0.7,volume=0.5" \
  -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p \
  -c:a aac -b:a 48k -shortest

# ⑦ Green-screen + moving subject (chroma-key fixture; keyable moving box).
gen ab07_greenscreen_320x240_4s.mp4 \
  -f lavfi -i "color=c=0x00B140:s=320x240:r=30:d=4" \
  -vf "drawbox=x=mod(t*40\,220)+10:y=mod(t*25\,140)+10:w=80:h=80:color=0xC02040:t=fill" \
  -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p

# ⑫ 2-hour long-form (320x240@24) — stability/length dimension.
gen ab12_320x240_2h.mp4 \
  -f lavfi -i "testsrc2=size=320x240:rate=24:duration=7200" \
  -f lavfi -i "sine=frequency=200:sample_rate=44100:duration=7200" \
  -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p \
  -c:a aac -b:a 32k -shortest

# Reused committed fixtures (③⑤⑥⑧⑨⑪ + ducking audio).
REUSED+=(
  "ca04_bt2020pq_320x240_2s.mp4"
  "rec709_720p_portrait_1s_30fps.mp4"
  "moving_subject_320x240_2s_30fps.mp4"
  "rec709_1080p_1s_30fps.mp4"
  "solid_red_tone_320x240_2s_30fps.mp4"
  "ca04_vfr_320x240_5s.mp4"
  "duck_bgm_220hz_4s_mono.wav"
  "duck_voice_1000hz_1s_mono.wav"
)
for f in "${REUSED[@]}"; do
  [ -f "$ROOT/Tests/Fixtures/$f" ] || { echo "missing committed fixture: $f" >&2; exit 1; }
done

# --- manifest + pin verification ------------------------------------------------
MANIFEST="$OUT/manifest.json"
{
  echo '{'
  echo '  "generated_by": "scripts/make_ab_fixtures.sh",'
  echo '  "fixtures": {'
  entries=()
  emit_entry() { # <key> <path> <note>
    local key="$1" path="$2" note="$3" sha size dur res fps vcodec
    sha="$(shasum -a 256 "$path" | awk '{print $1}')"
    size="$(stat -f%z "$path")"
    if [[ "$path" == *.wav ]]; then
      dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$path")"
      entries+=("    \"$key\": {\"path\": \"$(basename "$path")\", \"sha256\": \"$sha\", \"size_bytes\": $size, \"duration_s\": $dur, \"note\": \"$note\"}")
    else
      dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$path")"
      res="$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$path")"
      fps="$(ffprobe -v error -select_streams v -show_entries stream=r_frame_rate -of csv=p=0 "$path")"
      vcodec="$(ffprobe -v error -select_streams v -show_entries stream=codec_name -of csv=p=0 "$path")"
      entries+=("    \"$key\": {\"path\": \"$(basename "$path")\", \"sha256\": \"$sha\", \"size_bytes\": $size, \"duration_s\": $dur, \"geometry\": \"$res\", \"fps\": \"$fps\", \"codec\": \"$vcodec\", \"note\": \"$note\"}")
    fi
  }

  emit_entry ab01_single_1080p30 "$OUT/ab01_1080p30_10s.mp4" "① single 1080p30 (10s)"
  emit_entry ab02_4k60_hevc "$OUT/ab02_2160p60_hevc_6s.mov" "② 4K60 HEVC"
  emit_entry ab03_hdr_10bit "$ROOT/Tests/Fixtures/ca04_bt2020pq_320x240_2s.mp4" "③ 10-bit BT.2020+PQ (committed)"
  emit_entry ab04_interview_30min "$OUT/ab04_interview_640x360_30min.mp4" "④ 30-min interview (640x360 reduced scale)"
  emit_entry ab05_shorts_overlays "$ROOT/Tests/Fixtures/rec709_720p_portrait_1s_30fps.mp4" "⑤ 9:16 shorts base (imported 2x + text)"
  emit_entry ab06_ramp_opticalflow "$ROOT/Tests/Fixtures/moving_subject_320x240_2s_30fps.mp4" "⑥ speed ramp + optical flow (committed)"
  emit_entry ab07_mask_chromakey "$OUT/ab07_greenscreen_320x240_4s.mp4" "⑦ mask + chroma key"
  emit_entry ab08_color_grade "$ROOT/Tests/Fixtures/rec709_1080p_1s_30fps.mp4" "⑧ color correction + grade (committed)"
  emit_entry ab09_ducking_master "$ROOT/Tests/Fixtures/solid_red_tone_320x240_2s_30fps.mp4" "⑨ ducking + master chain (committed)"
  emit_entry ab10_external_disk "$OUT/ab01_1080p30_10s.mp4" "⑩ external-disk axis: reuses ① media; storage is a condition field"
  emit_entry ab11_vfr_screenrec "$ROOT/Tests/Fixtures/ca04_vfr_320x240_5s.mp4" "⑪ VFR screen recording (committed)"
  emit_entry ab12_two_hour "$OUT/ab12_320x240_2h.mp4" "⑫ 2-hour long-form (320x240@24 reduced scale)"
  emit_entry duck_bgm "$ROOT/Tests/Fixtures/duck_bgm_220hz_4s_mono.wav" "⑨ BGM (committed)"
  emit_entry duck_voice "$ROOT/Tests/Fixtures/duck_voice_1000hz_1s_mono.wav" "⑨ voice (committed)"

  printf '%s\n' "${entries[@]}" | paste -sd, -
  echo '  }'
  echo '}'
} > "$MANIFEST"
echo "manifest: $MANIFEST"

# Verify pins for the generated set (committed fixtures are pinned by their
# committed checksums in git; the generated set pins here).
FAIL=0
for name in ab01_1080p30_10s.mp4 ab02_2160p60_hevc_6s.mov ab04_interview_640x360_30min.mp4 ab07_greenscreen_320x240_4s.mp4 ab12_320x240_2h.mp4; do
  pin="$(pin_for "$name")"
  [ -z "$pin" ] || [ "$pin" = "PIN_ME" ] && continue
  actual="$(shasum -a 256 "$OUT/$name" | awk '{print $1}')"
  if [ "$actual" != "$pin" ]; then
    echo "PIN MISMATCH: $name (expected $pin, got $actual)" >&2
    FAIL=1
  fi
done
if [ "$FAIL" -eq 1 ]; then
  echo "Fixture set changed — re-pin deliberately in this script's #pin table." >&2
  exit 1
fi
echo "fixture set OK"
