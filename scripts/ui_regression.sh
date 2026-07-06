#!/bin/bash
# U-08 UI screenshot regression harness for MovieCut.
#
# Usage:
#   scripts/ui_regression.sh                 # capture + compare against committed goldens
#   scripts/ui_regression.sh --update-golden # capture + refresh Tests/UIEvidence goldens
#
# Generated artifacts live in artifacts/ui/. Committed evidence lives in Tests/UIEvidence/.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${MOVIECUT_UI_OUT_DIR:-$REPO_DIR/artifacts/ui}"
GOLDEN_DIR="$REPO_DIR/Tests/UIEvidence"
UPDATE_GOLDEN=0
THRESHOLD="${MOVIECUT_UI_DHASH_THRESHOLD:-4}"

usage() {
  sed -n '1,10p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-golden)
      UPDATE_GOLDEN=1
      shift
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

"$REPO_DIR/scripts/ui_capture.sh" --out-dir "$OUT_DIR"
RAW_CAPTURE="$OUT_DIR/moviecut_populated_editor_raw.png"
CURRENT_NORMALIZED="$OUT_DIR/moviecut_populated_editor_normalized.png"
GOLDEN="$GOLDEN_DIR/golden_populated_editor.png"
REPORT="$OUT_DIR/ui_regression_report.txt"

if [[ ! -s "$RAW_CAPTURE" ]]; then
  echo "raw capture missing: $RAW_CAPTURE" >&2
  exit 1
fi

# Normalize the image before hashing/committing so minor display-size changes do not
# churn goldens. ffmpeg is already a project test dependency via run_e2e_export.sh.
ffmpeg -v error -y -i "$RAW_CAPTURE" -vf "scale=512:-1" "$CURRENT_NORMALIZED"

if [[ "$UPDATE_GOLDEN" == "1" ]]; then
  cp "$CURRENT_NORMALIZED" "$GOLDEN"
  echo "updated_golden=$GOLDEN" | tee "$REPORT"
  echo "current_normalized=$CURRENT_NORMALIZED" | tee -a "$REPORT"
  echo "UI regression golden updated"
  exit 0
fi

if [[ ! -s "$GOLDEN" ]]; then
  echo "missing UI golden: $GOLDEN" >&2
  echo "Run scripts/ui_regression.sh --update-golden after reviewing the generated capture." >&2
  exit 1
fi

python3 - "$CURRENT_NORMALIZED" "$GOLDEN" "$THRESHOLD" "$REPORT" <<'PY'
import subprocess
import sys
from pathlib import Path

current, golden, threshold_raw, report = sys.argv[1:5]
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
text = "\n".join([
    f"current={current}",
    f"golden={golden}",
    f"current_dhash={current_hash:016x}",
    f"golden_dhash={golden_hash:016x}",
    f"distance={distance}",
    f"threshold={threshold}",
]) + "\n"
Path(report).write_text(text, encoding="utf-8")
print(text, end="")
if distance > threshold:
    raise SystemExit(1)
PY

echo "UI regression PASS (report=$REPORT)"
