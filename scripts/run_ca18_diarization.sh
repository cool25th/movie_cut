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

VOICE_A="Yuna"
VOICE_B="Daniel"
GAP=0.4

dur() { ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$1"; }

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
  KEEP="/tmp/moviecut-ca18-keep-$(date +%H%M%S)"
  cp -r "$WORK" "$KEEP" 2>/dev/null || true
  echo "evidence kept at: $KEEP" >&2
  exit 1
}
grep -q "CA18 VERDICT: PASS" "$WORK/measure.log" && echo "CA18 DIARIZATION MEASUREMENT PASS" || {
  echo "CA18 DIARIZATION MEASUREMENT FAIL (explicit failure recorded — no UI work without approval)" >&2
  exit "${rc:-1}"
}
