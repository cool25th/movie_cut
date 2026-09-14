#!/usr/bin/env bash
# CA-21 measurement step (backlog §0.5.1 — measurement approved 2026-08-23):
# Edit Detection (SceneChangeProvider) precision/recall against
# PRE-REGISTERED thresholds (see SceneChangeDetectionMeasurementTests —
# fixed before any measurement run).
#
# Fixtures are generated to a scratch dir (ffmpeg lavfi, deterministic):
#   no_cut   10s single solid gray              — T3 specificity control
#   hard     5x2s distinct-luminance solids     — 4 hard cuts at 2/4/6/8
#   real1    testsrc2 3s + smptebars 3s + mandelbrot 3s
#            — real-content segments (motion/texture within a scene) with
#              known concat cuts at 3/6
#   real2    mandelbrot 4s + noise 4s + testsrc2 4s — cuts at 4/8
# Ground truth is the generation command itself, so P/R is exact.
#
# The driver FAILS if the measurement verdict line is absent (the 0-tests
# fake-green trap) or the test fails.
#
# Usage: bash scripts/run_ca21_scene_detection.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }

WORK="$(mktemp -d /tmp/moviecut-ca21.XXXXXX)"
# One run id for every record of this invocation — control legs and the real
# measurement must be provably from the same run (stale-record reuse guard).
RUN_ID="$(date +%s)-$$"
RUN_START="$(date +%Y-%m-%dT%H:%M:%S)"
SCRIPT_PATH="${BASH_SOURCE[0]}"
# QAUTO-01 hardening: assemble the run's immutable provenance manifest
# BEFORE the scratch fixtures are removed (dataset SHA capture).
trap 'bash "$ROOT/scripts/build_run_manifest.sh" "$RUN_ID" ca21 "$WORK" "$RUN_START" "$SCRIPT_PATH" || true; rm -rf "$WORK"' EXIT

gen() { # gen <out> <lavfi-source> <seconds>
  ffmpeg -y -loglevel error -f lavfi -i "$2" -t "$3" -r 30 -pix_fmt yuv420p "$1"
}

# --- QAUTO-01 control preflight (2026-09-14, 3회차 피드백: known-invalid가
# 핵심) — 손상 픽스처가 게이트를 거부시키는지 실측 전에 증명한다. 판정은
# ① rc≠0 ② 스위트 실실행 표식(0-tests 가짜그린 함정은 아무것도 출력하지
# 않는다) ③ PASS 판정 부재 — 셋 다여야 한다. 실패 시 실측 거부+기록.
echo "Control preflight (known-invalid: corrupt fixture)…"
printf 'this is not an mp4 file — QAUTO known-invalid control' > "$WORK/control.mp4"
cat > "$WORK/control.json" <<EOF
[{"file": "$WORK/control.mp4", "class": "invalid_control", "expected_cuts": []}]
EOF
set +e
CA21_MANIFEST="$WORK/control.json" \
  swift test --filter "SceneChangeDetectionMeasurementTests" 2>&1 | tee "$WORK/control.log"
crc=${PIPESTATUS[0]}
set -e
if [ "$crc" -ne 0 ] \
   && grep -q 'Suite "CA-21 scene-change measurement" started' "$WORK/control.log" \
   && ! grep -q "CA21 VERDICT: PASS" "$WORK/control.log"; then
  echo "CONTROL OK — gate refuses a corrupt fixture (no PASS verdict, suite executed)"
  REC_RUN_ID="$RUN_ID" REC_PHASE="control_preflight" REC_EXPECTED="ABORT_BEFORE_VERDICT" \
    REC_OBSERVED_STATE="ABORT_BEFORE_VERDICT" REC_VERDICT_PRESENT="false" REC_AUTHORIZED="true" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca21 CONTROL_OK "$WORK/control.log" "${BASH_SOURCE[0]}" || true
else
  echo "CONTROL FAIL — corrupt fixture did not trip the gate; real measurement REFUSED" >&2
  REC_RUN_ID="$RUN_ID" REC_PHASE="control_preflight" REC_EXPECTED="ABORT_BEFORE_VERDICT" \
    REC_AUTHORIZED="false" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca21 ERROR_CONTROL_BREACH "$WORK/control.log" "${BASH_SOURCE[0]}" || true
  exit 1
fi

# --- QAUTO-01 positive smoke control (2026-09-14, 4회차): a negative-only
# preflight would bless an always-rejecting broken gate. The hard fixture's
# cuts are exact by construction (lavfi concat at 2/4/6/8), so a
# single-fixture manifest MUST earn a PASS verdict — proving the gate can
# issue one, on the same code path. Failure ⇒ refuse the real measurement.
echo "Control preflight (positive smoke: exact-cut known-good fixture)…"
gen "$WORK/pc_a.mp4" "color=c=0x101010:s=320x240:r=30" 2
gen "$WORK/pc_b.mp4" "color=c=0xf0f0f0:s=320x240:r=30" 2
gen "$WORK/pc_c.mp4" "color=c=0x303030:s=320x240:r=30" 2
gen "$WORK/pc_d.mp4" "color=c=0xc0c0c0:s=320x240:r=30" 2
gen "$WORK/pc_e.mp4" "color=c=0x600000:s=320x240:r=30" 2
printf "file '%s/pc_a.mp4'\nfile '%s/pc_b.mp4'\nfile '%s/pc_c.mp4'\nfile '%s/pc_d.mp4'\nfile '%s/pc_e.mp4'\n" "$WORK" "$WORK" "$WORK" "$WORK" "$WORK" > "$WORK/pc.txt"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$WORK/pc.txt" -r 30 "$WORK/positive.mp4"
[ -s "$WORK/positive.mp4" ] || { echo "positive control fixture generation failed" >&2; exit 1; }
cat > "$WORK/positive.json" <<EOF
[{"file": "$WORK/positive.mp4", "class": "positive_control", "expected_cuts": [2, 4, 6, 8]}]
EOF
set +e
CA21_MANIFEST="$WORK/positive.json" \
  swift test --filter "SceneChangeDetectionMeasurementTests" 2>&1 | tee "$WORK/positive.log"
prc=${PIPESTATUS[0]}
set -e
if [ "$prc" -eq 0 ] && grep -q "CA21 VERDICT: PASS" "$WORK/positive.log"; then
  echo "CONTROL POSITIVE OK — gate issues PASS on an exact-cut known-good fixture"
  REC_RUN_ID="$RUN_ID" REC_PHASE="control_preflight" REC_EXPECTED="PASS" \
    REC_OBSERVED_STATE="SEMANTIC_PASS" REC_AUTHORIZED="true" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca21 CONTROL_POSITIVE_OK "$WORK/positive.log" "${BASH_SOURCE[0]}" || true
else
  echo "CONTROL POSITIVE FAIL — gate cannot issue PASS on known-good input; real measurement REFUSED" >&2
  REC_RUN_ID="$RUN_ID" REC_PHASE="control_preflight" REC_EXPECTED="PASS" \
    REC_AUTHORIZED="false" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca21 ERROR_CONTROL_BREACH "$WORK/positive.log" "${BASH_SOURCE[0]}" || true
  exit 1
fi

echo "Generating fixtures (scratch)…"
gen "$WORK/no_cut.mp4"  "color=c=0x808080:s=320x240:r=30" 10
gen "$WORK/seg_a.mp4"   "color=c=0x101010:s=320x240:r=30" 2
gen "$WORK/seg_b.mp4"   "color=c=0xf0f0f0:s=320x240:r=30" 2
gen "$WORK/seg_c.mp4"   "color=c=0x303030:s=320x240:r=30" 2
gen "$WORK/seg_d.mp4"   "color=c=0xc0c0c0:s=320x240:r=30" 2
gen "$WORK/seg_e.mp4"   "color=c=0x600000:s=320x240:r=30" 2
printf "file '%s/seg_a.mp4'\nfile '%s/seg_b.mp4'\nfile '%s/seg_c.mp4'\nfile '%s/seg_d.mp4'\nfile '%s/seg_e.mp4'\n" "$WORK" "$WORK" "$WORK" "$WORK" "$WORK" > "$WORK/hard.txt"
# Re-encode at concat (NOT -c copy): stream-copying independently encoded
# files produces broken timestamps and AVAssetImageGenerator fails every
# frame — measured as det=0 with rtf=0.000 on the first run.
ffmpeg -y -loglevel error -f concat -safe 0 -i "$WORK/hard.txt" -r 30 "$WORK/hard.mp4"

gen "$WORK/r1a.mp4" "testsrc2=size=320x240:r=30"    3
gen "$WORK/r1b.mp4" "smptebars=size=320x240:r=30"   3
gen "$WORK/r1c.mp4" "mandelbrot=size=320x240:r=30"  3
printf "file '%s/r1a.mp4'\nfile '%s/r1b.mp4'\nfile '%s/r1c.mp4'\n" "$WORK" "$WORK" "$WORK" > "$WORK/real1.txt"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$WORK/real1.txt" -r 30 "$WORK/real1.mp4"

gen "$WORK/r2a.mp4" "mandelbrot=size=320x240:r=30" 4
gen "$WORK/r2b.mp4" "nullsrc=s=320x240:r=30,geq=random(1)*255:128:128" 4
gen "$WORK/r2c.mp4" "testsrc2=size=320x240:r=30"   4
printf "file '%s/r2a.mp4'\nfile '%s/r2b.mp4'\nfile '%s/r2c.mp4'\n" "$WORK" "$WORK" "$WORK" > "$WORK/real2.txt"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$WORK/real2.txt" -r 30 "$WORK/real2.mp4"

for f in no_cut hard real1 real2; do
  [ -s "$WORK/$f.mp4" ] || { echo "fixture $f generation failed" >&2; exit 1; }
done

cat > "$WORK/manifest.json" <<EOF
[
  {"file": "$WORK/no_cut.mp4", "class": "no_cut", "expected_cuts": []},
  {"file": "$WORK/hard.mp4",   "class": "hard",   "expected_cuts": [2, 4, 6, 8]},
  {"file": "$WORK/real1.mp4",  "class": "real1",  "expected_cuts": [3, 6]},
  {"file": "$WORK/real2.mp4",  "class": "real2",  "expected_cuts": [4, 8]}
]
EOF

echo "Running measurement (SceneChangeProvider, product defaults)…"
set +e
CA21_MANIFEST="$WORK/manifest.json" \
  swift test --filter "SceneChangeDetectionMeasurementTests" 2>&1 | tee "$WORK/measure.log"
rc=${PIPESTATUS[0]}
set -e

# Fake-green guard: the verdict line MUST have been printed by an actual
# test execution (a filtered-out suite prints nothing and exits 0).
grep -q "CA21 VERDICT:" "$WORK/measure.log" || {
  echo "CA21 GATE FAIL — measurement verdict line absent (suite did not run — the 0-tests fake-green trap)" >&2
  # QAUTO-01: retain even the absent-verdict evidence before discarding WORK.
  bash "$ROOT/scripts/record_measurement_verdict.sh" ca21 NO_VERDICT "$WORK/measure.log" "${BASH_SOURCE[0]}" || true
  exit 1
}
if grep -q "CA21 VERDICT: PASS" "$WORK/measure.log"; then
  # QAUTO-01: pin the verdict to app commit + harness sha before exit.
  REC_RUN_ID="$RUN_ID" REC_PHASE="measurement" REC_AUTHORIZED="true" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca21 PASS "$WORK/measure.log" "${BASH_SOURCE[0]}"
  echo "CA21 SCENE-DETECTION MEASUREMENT PASS"
else
  REC_RUN_ID="$RUN_ID" REC_PHASE="measurement" REC_AUTHORIZED="true" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca21 FAIL "$WORK/measure.log" "${BASH_SOURCE[0]}"
  echo "CA21 SCENE-DETECTION MEASUREMENT FAIL" >&2
  exit "${rc:-1}"
fi
