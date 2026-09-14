#!/usr/bin/env bash
# CA-18 measurement step (backlog §0.5.1 — measurement approved 2026-08-23):
# on-device 2-speaker diarization as a gated research item. Thresholds are
# PRE-REGISTERED in the backlog row (confusion ≤10% per fixture, RTF ≤0.5)
# and enforced by the Core measurement test — this driver only builds the
# fixtures and demands the verdict line.
#
# Fixtures (scratch, deterministic):
#   synth    Yuna(ko) / Daniel(en_GB) alternating, 12 utterances, 0.4s gaps
#            — known ground-truth speaker per utterance (2 maximally
#              distinct on-device voices)
#   perturb  the same schedule mixed with pink noise at ≈12dB SNR — the
#            SUBSTITUTED "실녹음" axis (real-human capture needs the user;
#            the substitution is reported, not silently passed)
#
# Usage: bash scripts/run_ca18_diarization.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

WORK="$(mktemp -d /tmp/moviecut-ca18.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
# One run id for every record of this invocation — control legs and the real
# measurement must be provably from the same run (stale-record reuse guard).
RUN_ID="$(date +%s)-$$"

VOICE_A="Yuna"
VOICE_B="Daniel"
GAP=0.4

dur() { ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$1"; }

# --- QAUTO-01 control preflight (2026-09-14, 3회차 피드백: known-invalid가
# 핵심) — 실측을 믿기 전에 게이트가 measurement-invalid 입력에서 반드시
# 발화하는지 증명한다. 프레임(25ms)보다 짧은 무음 파일은 0검출 — 어제 막은
# 거짓-PASS 경로 그 자체. 컨트롤 실패 시 실측을 거부하고 그 거부를 기록.
echo "Control preflight (known-invalid: sub-frame silent fixture)…"
ffmpeg -y -loglevel error -f lavfi -i "anullsrc=r=44100:cl=mono" -t 0.005 "$WORK/silence.wav"
[ -s "$WORK/silence.wav" ] || { echo "control fixture generation failed" >&2; exit 1; }
cat > "$WORK/control.json" <<EOF
[{"file": "$WORK/silence.wav", "class": "invalid_control", "segments": []}]
EOF
set +e
CA18_MANIFEST="$WORK/control.json" \
  swift test --filter "DiarizationMeasurementTests" 2>&1 | tee "$WORK/control.log"
crc=${PIPESTATUS[0]}
set -e
if [ "$crc" -ne 0 ] \
   && grep -q "degeneracy: 0 segments detected" "$WORK/control.log" \
   && grep -q "CA18 VERDICT: FAIL" "$WORK/control.log"; then
  echo "CONTROL OK — gate trips on measurement-invalid input (degeneracy forced FAIL observed)"
  REC_RUN_ID="$RUN_ID" REC_PHASE="control_preflight" REC_EXPECTED="FAIL_DEGENERACY" \
    REC_OBSERVED_STATE="SEMANTIC_FAIL_DEGENERACY" REC_AUTHORIZED="true" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca18 CONTROL_OK "$WORK/control.log" "${BASH_SOURCE[0]}" || true
else
  echo "CONTROL FAIL — gate did not trip as expected; real measurement REFUSED" >&2
  REC_RUN_ID="$RUN_ID" REC_PHASE="control_preflight" REC_EXPECTED="FAIL_DEGENERACY" \
    REC_AUTHORIZED="false" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca18 ERROR_CONTROL_BREACH "$WORK/control.log" "${BASH_SOURCE[0]}" || true
  exit 1
fi

# synth
build_synth() {
  local out="$1" noisy="$2"
  local t=0 sep="" gt="["
  local texts_a=("첫 번째 발화입니다" "두 번째 발화를 시작합니다" "세 번째 이야기입니다" "네 번째 발화입니다" "다섯 번째 이야기입니다" "여섯 번째 발화입니다")
  local texts_b=("This is utterance number one" "Here comes the second one" "Now the third utterance" "The fourth one follows" "Fifth utterance now" "And finally the sixth")
  local parts=()
  for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
    if [ $((i % 2)) -eq 0 ]; then v="Yuna"; txt="${texts_a[$((i / 2))]}"; else v="Daniel"; txt="${texts_b[$((i / 2))]}"; fi
    say -v "$v" -o "$WORK/u$i.aiff" "$txt"
    ffmpeg -y -loglevel error -i "$WORK/u$i.aiff" -ar 44100 -ac 1 "$WORK/u$i.wav"
    d="$(dur "$WORK/u$i.wav")"
    gt+="$sep{\"start\": $t, \"end\": $(python3 -c "print($t + $d)"), \"speaker\": $((i % 2))}"
    sep=","
    parts+=("$WORK/u$i.wav")
    t=$(python3 -c "print($t + $d + 0.4)")
    ffmpeg -y -loglevel error -f lavfi -i "anullsrc=r=44100:cl=mono" -t 0.4 "$WORK/g$i.wav"
    parts+=("$WORK/g$i.wav")
  done
  gt+="]"
  printf "file '%s'\n" "${parts[@]}" > "$WORK/list.txt"
  ffmpeg -y -loglevel error -f concat -safe 0 -i "$WORK/list.txt" -ar 44100 -ac 1 "$WORK/clean.wav"
  if [ "$noisy" = "1" ]; then
    ffmpeg -y -loglevel error -i "$WORK/clean.wav" -f lavfi -i "anoisesrc=color=pink:amplitude=0.012:sample_rate=44100" -filter_complex "[0:a][1:a]amix=inputs=2:duration=first[out]" -map "[out]" -ac 1 "$out"
  else
    cp "$WORK/clean.wav" "$out"
  fi
  echo "$gt"
}

echo "Building fixtures (say: Yuna/Daniel alternating, 12 utterances)…"
GT_SYNTH="$(build_synth "$WORK/synth.wav" 0)"
GT_PERTURB="$(build_synth "$WORK/perturb.wav" 1)"

cat > "$WORK/manifest.json" <<EOF
[
  {"file": "$WORK/synth.wav",   "class": "synth",   "segments": $GT_SYNTH},
  {"file": "$WORK/perturb.wav", "class": "perturb", "segments": $GT_PERTURB}
]
EOF
python3 -m json.tool "$WORK/manifest.json" >/dev/null || { echo "manifest JSON invalid" >&2; exit 1; }

echo "Running measurement (offline candidate: energy VAD + log-spectra + 2-means)…"
set +e
CA18_MANIFEST="$WORK/manifest.json" \
  swift test --filter "DiarizationMeasurementTests" 2>&1 | tee "$WORK/measure.log"
rc=${PIPESTATUS[0]}
set -e

grep -q "CA18 VERDICT:" "$WORK/measure.log" || {
  echo "CA18 GATE FAIL — verdict line absent (suite did not run)" >&2
  # QAUTO-01: retain even the absent-verdict evidence before discarding WORK.
  bash "$ROOT/scripts/record_measurement_verdict.sh" ca18 NO_VERDICT "$WORK/measure.log" "${BASH_SOURCE[0]}" || true
  KEEP="/tmp/moviecut-ca18-keep-$(date +%H%M%S)"
  cp -r "$WORK" "$KEEP" 2>/dev/null || true
  echo "evidence kept at: $KEEP" >&2
  exit 1
}
if grep -q "CA18 VERDICT: PASS" "$WORK/measure.log"; then
  # QAUTO-01: pin the verdict to app commit + harness sha before exit.
  REC_RUN_ID="$RUN_ID" REC_PHASE="measurement" REC_AUTHORIZED="true" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca18 PASS "$WORK/measure.log" "${BASH_SOURCE[0]}"
  echo "CA18 DIARIZATION MEASUREMENT PASS"
else
  REC_RUN_ID="$RUN_ID" REC_PHASE="measurement" REC_AUTHORIZED="true" \
    bash "$ROOT/scripts/record_measurement_verdict.sh" ca18 FAIL "$WORK/measure.log" "${BASH_SOURCE[0]}"
  echo "CA18 DIARIZATION MEASUREMENT FAIL (explicit failure recorded — no UI work without approval)" >&2
  exit "${rc:-1}"
fi
