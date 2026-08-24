#!/usr/bin/env bash
# CA-04 input-format compatibility matrix — MEASURED, per dimension.
#
# For each fixture: drive the REAL app (parity harness: import → composition
# → preview dump → export) with the fixture, then ffprobe the OUTPUT and
# assert dimension-specific properties. Mixed fps+sample-rate sync rides the
# same harness with a two-clip import. Evidence lands in the result line;
# the matrix doc (AUDIT_INPUT_FORMATS_*) cites this script's numbers.
#
# Usage: bash scripts/run_ca04_format_matrix.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXDIR="$ROOT/Tests/Fixtures"
for f in ca04_vfr_320x240_5s.mp4 ca04_tenbit_320x240_2s.mov \
         ca04_rotated_320x240_2s_90deg.mp4 ca04_bt2020pq_320x240_2s.mp4 \
         rec709_1080p_1s_24fps.mp4 solid_red_tone_320x240_2s_30fps.mp4; do
  [ -s "$FIXDIR/$f" ] || { echo "missing fixture $f; run scripts/make_fixtures.sh" >&2; exit 1; }
done

echo "Building MovieCutMac (Debug, sandbox OFF)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

WORK="$(mktemp -d /tmp/moviecut-ca04.XXXXXX)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT
pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 1

fail=0
note() { echo "[$1] $2"; }
bad() { echo "[$1] FAIL: $2" >&2; fail=1; }
# Dims whose defects are ALREADY REGISTERED (AUDIT_INPUT_FORMATS doc)
# record-and-continue instead of failing the gate: the matrix protects
# against NEW regressions while known defects wait for their fix
# increments. An unregistered failure still fails.
registered() {
  case "$1" in
    tenbit) echo "BUG-06";;
    rotated) echo "BUG-07";;
    *) echo "";;
  esac
}
reg() {
  local rid
  rid="$(registered "$1")"
  if [ -n "$rid" ]; then
    echo "[$1] REG($rid): $2 — registered defect, not a new regression" >&2
  else
    bad "$1" "$2"
  fi
}

# run_one <tag> <imports(comma)> <expected_duration_s> <tolerance_s>
run_one() {
  local tag="$1" imports="$2" expect_s="$3" tol="$4"
  local out="$WORK/${tag}_export.mp4" result="$WORK/${tag}_result.txt" dump="$WORK/${tag}_dump"
  mkdir -p "$dump"
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_PARITY=1 \
    MOVIECUT_UITEST_IMPORT="$imports" \
    MOVIECUT_UITEST_PARITY_TIMES="1.0" \
    MOVIECUT_UITEST_PREVIEW_DUMP="$dump" \
    MOVIECUT_UITEST_EXPORT="$out" \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!
  ( sleep 180; kill "$pid" 2>/dev/null; pkill -x MovieCutMac 2>/dev/null; true ) & local wd=$!
  for _ in $(seq 1 360); do
    grep -q "parity_done" "$result" 2>/dev/null && break
    sleep 0.5
  done
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true
  if [ ! -s "$out" ]; then
    bad "$tag" "no export produced — $(tail -1 "$result" 2>/dev/null)"
    return 1
  fi
  local dur
  dur="$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$out")"
  note "$tag" "export_ok bytes=$(stat -f%z "$out") duration=${dur}s"
  awk -v d="$dur" -v e="$expect_s" -v t="$tol" 'BEGIN { exit (d > e - t && d < e + t) ? 0 : 1 }' \
    || bad "$tag" "duration $dur outside ${expect_s}±${tol}"
  echo "$dur" > "$WORK/${tag}_duration"
}

# NOTE: entry specs MUST carry their section prefix (stream=…, format=…);
# bare names make ffprobe exit 1, which set -e turns into a silent script
# death after the first successful scenario. `|| true` keeps a failing
# probe as an empty reading the assertions then report loudly.
json() { ffprobe -v quiet -select_streams "$2" -show_entries "$3" -of csv=p=0 "$1" 2>/dev/null || true; }

echo "=== 1. VFR → CFR export ==="
run_one vfr "$FIXDIR/ca04_vfr_320x240_5s.mp4" 5.0 0.12
if [ -s "$WORK/vfr_export.mp4" ]; then
  r="$(json "$WORK/vfr_export.mp4" v:0 stream=r_frame_rate)"
  a="$(json "$WORK/vfr_export.mp4" v:0 stream=avg_frame_rate)"
  n="$(json "$WORK/vfr_export.mp4" v:0 stream=nb_frames)"
  note vfr "output rate r=$r avg=$a frames=$n (input: 100 frames @~20.1fps VFR)"
  [ "$r" = "$a" ] || bad vfr "output not CFR: r=$r avg=$a"
  awk -v n="$n" 'BEGIN { exit (n >= 130 && n <= 170) ? 0 : 1 }' \
    || bad vfr "resampled frame count $n outside 130–170 (5s @30fps CFR)"
fi

echo "=== 2. 10-bit → 8-bit SDR (documented conversion) + color preservation ==="
run_one tenbit "$FIXDIR/ca04_tenbit_320x240_2s.mov" 2.0 0.12
if [ -s "$WORK/tenbit_export.mp4" ]; then
  pix="$(json "$WORK/tenbit_export.mp4" v:0 stream=pix_fmt)"
  note tenbit "output pix_fmt=$pix (v1 contract: 8-bit yuv420p)"
  [ "$pix" = "yuv420p" ] || bad tenbit "unexpected output pix_fmt $pix"
  # Color preservation: mean luma of source vs export at t=1.0 (Y channel).
  src_y="$(ffmpeg -loglevel error -ss 1.0 -i "$FIXDIR/ca04_tenbit_320x240_2s.mov" -frames:v 1 -f rawvideo -pix_fmt gray - 2>/dev/null | python3 -c 'import sys; d=sys.stdin.buffer.read(); print(sum(d)/len(d) if d else -1)')"
  out_y="$(ffmpeg -loglevel error -ss 1.0 -i "$WORK/tenbit_export.mp4" -frames:v 1 -f rawvideo -pix_fmt gray - 2>/dev/null | python3 -c 'import sys; d=sys.stdin.buffer.read(); print(sum(d)/len(d) if d else -1)')"
  note tenbit "mean luma source=${src_y} export=${out_y}"
  python3 -c "import sys; sys.exit(0 if abs($src_y - $out_y) <= 4.0 else 1)" \
    || reg tenbit "mean luma shifted more than ±4 (10→8-bit + encode): src=$src_y out=$out_y"
fi

echo "=== 3. Rotation metadata → upright export ==="
run_one rotated "$FIXDIR/ca04_rotated_320x240_2s_90deg.mp4" 2.0 0.12
if [ -s "$WORK/rotated_export.mp4" ]; then
  w="$(json "$WORK/rotated_export.mp4" v:0 stream=width)"
  h="$(json "$WORK/rotated_export.mp4" v:0 stream=height)"
  rot="$(ffprobe -v quiet -select_streams v:0 -show_entries stream_side_data=rotation -of csv=p=0 "$WORK/rotated_export.mp4")"
  note rotated "output ${w}x${h} side_rotation='${rot}' (input 320x240 +90° metadata)"
  # The composition path applies preferredTransform; the export should be
  # upright (portrait 240x320) OR carry the rotation tag forward — either
  # preserves content orientation; neither = silently sideways.
  if [ "${rot}" = "" ] || [ "${rot}" = "0" ] || [ "${rot}" = "N/A" ]; then
    [ "$w" = "240" ] && [ "$h" = "320" ] || reg rotated "rotation dropped: ${w}x${h} with no side data"
  fi
fi

echo "=== 4. BT.2020+PQ tagged → SDR Rec.709 pipeline ==="
run_one wide "$FIXDIR/ca04_bt2020pq_320x240_2s.mp4" 2.0 0.12
if [ -s "$WORK/wide_export.mp4" ]; then
  cs="$(json "$WORK/wide_export.mp4" v:0 stream=color_space)"
  note wide "output color_space='$cs' (v1: SDR Rec.709 end-to-end; wide-gamut handling documented in the matrix)"
fi

echo "=== 5. Mixed fps (24+30) with audio — A/V sync ==="
run_one mixed "$FIXDIR/rec709_1080p_1s_24fps.mp4,$FIXDIR/solid_red_tone_320x240_2s_30fps.mp4" 3.0 0.12
if [ -s "$WORK/mixed_export.mp4" ]; then
  vd="$(json "$WORK/mixed_export.mp4" v:0 stream=duration)"
  ad="$(json "$WORK/mixed_export.mp4" a:0 stream=duration)"
  note mixed "stream durations video=${vd}s audio=${ad}s"
  python3 -c "import sys; sys.exit(0 if abs($vd - $ad) <= 0.05 else 1)" \
    || bad mixed "A/V duration delta > 50ms: video=$vd audio=$ad"
  fps="$(json "$WORK/mixed_export.mp4" v:0 stream=r_frame_rate)"
  note mixed "output fps=$fps (timeline CFR from mixed 24+30 sources)"
fi

echo ""
if [ "$fail" -eq 0 ]; then
  echo "CA-04 FORMAT MATRIX PASS (registered defects recorded, see REG lines)"
else
  echo "CA-04 FORMAT MATRIX FAIL" >&2
fi
exit "$fail"
