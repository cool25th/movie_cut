#!/bin/bash
# UI screenshot regression harness for MovieCut.
#
# Generalized to compare every committed golden under Tests/UIEvidence/ against
# a freshly captured editor state of the same name. The dhash + Hamming
# comparison is layout-sensitive (catches a panel moving/disappearing) but
# text-blind, so this complements — not replaces — the accessibility-label /
# copy behavior tests.
#
# Usage:
#   scripts/ui_regression.sh                  # capture all states + compare vs goldens
#   scripts/ui_regression.sh --update-golden  # capture all states + refresh all goldens
#   scripts/ui_regression.sh --state with_color_grade   # one state only
#
# Generated artifacts live in artifacts/ui/. Committed evidence lives in Tests/UIEvidence/.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${MOVIECUT_UI_OUT_DIR:-$REPO_DIR/artifacts/ui}"
GOLDEN_DIR="$REPO_DIR/Tests/UIEvidence"
UPDATE_GOLDEN=0
THRESHOLD="${MOVIECUT_UI_DHASH_THRESHOLD:-4}"
STATE_ARG=""

usage() {
  sed -n '1,13p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-golden)
      UPDATE_GOLDEN=1
      shift
      ;;
    --state)
      STATE_ARG="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUT_DIR" "$GOLDEN_DIR"

# Clear stale captures from a prior run so only the states captured THIS run
# are considered goldens/comparisons. Without this, a removed state's old raw
# lingered in artifacts/ui/ and --update-golden re-committed it, or it got
# compared against nothing and confusingly SKIPped.
rm -f "$OUT_DIR"/moviecut_*_raw.png "$OUT_DIR"/moviecut_*_normalized.png

# Capture the requested state(s). --state all (default) produces one raw per state.
CAPTURE_ARGS=(--out-dir "$OUT_DIR")
if [[ -n "$STATE_ARG" ]]; then
  CAPTURE_ARGS+=(--state "$STATE_ARG")
else
  CAPTURE_ARGS+=(--state all)
fi
"$REPO_DIR/scripts/ui_capture.sh" "${CAPTURE_ARGS[@]}"

REPORT="$OUT_DIR/ui_regression_report.txt"

# Compare each captured state against its committed golden (or create it).
compare_state() {
  local state="$1"
  local raw="$OUT_DIR/moviecut_${state}_raw.png"
  local normalized="$OUT_DIR/moviecut_${state}_normalized.png"
  local golden="$GOLDEN_DIR/golden_${state}.png"

  if [[ ! -s "$raw" ]]; then
    echo "  ${state}: SKIP (no capture; capture may have failed for this state)"
    return 0
  fi

  # Normalize before hashing so display-size changes don't churn goldens.
  ffmpeg -v error -y -i "$raw" -vf "scale=512:-1" "$normalized"

  if [[ "$UPDATE_GOLDEN" == "1" ]]; then
    cp "$normalized" "$golden"
    echo "  ${state}: GOLDEN UPDATED -> $golden"
    return 0
  fi

  if [[ ! -s "$golden" ]]; then
    echo "  ${state}: SKIP (no committed golden; run with --update-golden to create golden_${state}.png)"
    return 0
  fi

  python3 - "$normalized" "$golden" "$THRESHOLD" "$REPORT" "$state" <<'PY'
import subprocess
import sys
from pathlib import Path

current, golden, threshold_raw, report, state = sys.argv[1:6]
threshold = int(threshold_raw)

def dhash(path: str) -> int:
    data = subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", path,
        "-vf", "scale=9:8,format=gray",
        "-f", "rawvideo", "-pix_fmt", "gray", "-"
    ])
    if len(data) != 72:
        raise SystemExit(f"expected 72 hash bytes for {path}, got {len(data)}")
    bits = 0
    for row in range(8):
        for col in range(8):
            left = data[row * 9 + col]
            right = data[row * 9 + col + 1]
            bits = (bits << 1) | (1 if left > right else 0)
    return bits

current_hash = dhash(current)
golden_hash = dhash(golden)
distance = bin(current_hash ^ golden_hash).count("1")
verdict = "PASS" if distance <= threshold else "FAIL"
print(f"  {state}: {verdict}  distance={distance} threshold={threshold}")
# Append per-state line to the rolling report.
with open(report, "a", encoding="utf-8") as f:
    f.write(f"{state}\tcurrent_dhash={current_hash:016x}\tgolden_dhash={golden_hash:016x}\tdistance={distance}\tthreshold={threshold}\t{verdict}\n")
if distance > threshold:
    raise SystemExit(1)
PY
}

# Build the list of states to compare: the captured raw files define the set.
shopt -s nullglob
states=()
for raw in "$OUT_DIR"/moviecut_*_raw.png; do
  # moviecut_<state>_raw.png -> <state>
  base="$(basename "$raw")"            # moviecut_<state>_raw.png
  state="${base#moviecut_}"            # <state>_raw.png
  state="${state%_raw.png}"            # <state>
  states+=("$state")
done
shopt -u nullglob

if [[ ${#states[@]} -eq 0 ]]; then
  echo "no captures produced; capture likely failed (Accessibility permission? GUI session?)" >&2
  exit 1
fi

: > "$REPORT"
echo "" && echo "=== UI regression (dhash, threshold=${THRESHOLD}) ==="
fail=0
for s in "${states[@]}"; do
  compare_state "$s" || fail=1
done

if [[ "$UPDATE_GOLDEN" == "1" ]]; then
  echo "" && echo "UI regression goldens updated (review and commit Tests/UIEvidence/)"
  exit 0
fi

echo "" && echo "report=$REPORT"
if [[ "$fail" -ne 0 ]]; then
  echo "=> UI REGRESSION FAILED (see FAIL rows above)" >&2
  exit 1
fi
echo "=> UI REGRESSION PASS"
