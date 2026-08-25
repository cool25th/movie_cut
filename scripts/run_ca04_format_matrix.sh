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
         ca04_rotated_asym_320x240_2s_90deg.mp4 ca04_bt2020pq_320x240_2s.mp4 \
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
  # Color preservation (BUG-06 fixed 2026-08-25): the 4:3 source is
  # pillarboxed into the 16:9 canvas, so the FULL-FRAME export mean is the
  # content mean scaled by the content fraction (1440/1920 = 0.75). Compare
  # the export's CENTER CONTENT REGION to the source instead.
  src_y="$(ffmpeg -loglevel error -ss 1.0 -i "$FIXDIR/ca04_tenbit_320x240_2s.mov" -frames:v 1 -f rawvideo -pix_fmt gray - 2>/dev/null | python3 -c 'import sys; d=sys.stdin.buffer.read(); print(sum(d)/len(d) if d else -1)')"
  out_y="$(ffmpeg -loglevel error -ss 1.0 -i "$WORK/tenbit_export.mp4" -frames:v 1 -vf "crop=1440:1080:240:0" -f rawvideo -pix_fmt gray - 2>/dev/null | python3 -c 'import sys; d=sys.stdin.buffer.read(); print(sum(d)/len(d) if d else -1)')"
  note tenbit "mean luma source=${src_y} export(content region)=${out_y}"
  python3 -c "import sys; sys.exit(0 if abs($src_y - $out_y) <= 6.0 else 1)" \
    || bad tenbit "content-region luma shifted more than ±6 (10→8-bit + encode): src=$src_y out=$out_y"
fi

echo "=== 3. Rotation metadata → upright export ==="
run_one rotated "$FIXDIR/ca04_rotated_asym_320x240_2s_90deg.mp4" 2.0 0.12
if [ -s "$WORK/rotated_export.mp4" ]; then
  # BUG-07 fixed (2026-08-25): the asymmetric fixture (left=red, right=blue
  # in storage orientation) makes orientation MEASURABLE. Upright handling
  # pillarboxes the 240×320 display content into the 16:9 canvas at
  # 810×1080 centered (x=555): top half red, bottom half blue, black side
  # margins. Any sideways/missing rotation fails loudly.
  ffmpeg -loglevel error -ss 1.0 -i "$WORK/rotated_export.mp4" -frames:v 1 \
    -f rawvideo -pix_fmt rgb24 "$WORK/rotated_frame.rgb" 2>/dev/null
  if ! python3 - "$WORK/rotated_frame.rgb" <<'PYEOF'
import sys
buf = open(sys.argv[1], 'rb').read()
W, H = 1920, 1080
def region(x, y, w, h):
    px = [buf[(r*W+c)*3:(r*W+c)*3+3] for r in range(y, y+h, 4) for c in range(x, x+w, 4)]
    n = len(px)
    return (sum(p[0] for p in px)/n, sum(p[1] for p in px)/n, sum(p[2] for p in px)/n)
checks = {
    "content_top_is_red":   region(600, 100, 600, 380),
    "content_bottom_is_blue": region(1150, 620, 160, 380),
    "left_margin_black":    region(200, 400, 200, 280),
    "right_margin_black":   region(1500, 400, 200, 280),
}
failed = []
r, g, b = checks["content_top_is_red"]
if not (r > 140 and b < 90): failed.append(f"content_top_is_red (R={r:.0f},B={b:.0f})")
r, g, b = checks["content_bottom_is_blue"]
if not (b > 140 and r < 90): failed.append(f"content_bottom_is_blue (R={r:.0f},B={b:.0f})")
for name in ("left_margin_black", "right_margin_black"):
    r, g, b = checks[name]
    if max(r, g, b) >= 40: failed.append(f"{name} (R={r:.0f},G={g:.0f},B={b:.0f})")
print(f"[rotated] orientation: top(R,B)=({checks['content_top_is_red'][0]:.0f},{checks['content_top_is_red'][2]:.0f}) "
      f"bottom(R,B)=({checks['content_bottom_is_blue'][0]:.0f},{checks['content_bottom_is_blue'][2]:.0f})")
if failed:
    print(f"[rotated] FAIL: orientation checks failed: {', '.join(failed)}", file=sys.stderr)
    sys.exit(1)
PYEOF
  then
    bad rotated "rotation metadata not applied upright (see orientation check above)"
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
