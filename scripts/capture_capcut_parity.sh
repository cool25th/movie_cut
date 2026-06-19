#!/bin/bash
# Capture window-content screenshots of MovieCut (and optionally CapCut) for
# CapCut visual parity comparison, then run the region metrics.
#
# IMPORTANT: capture a POPULATED editor. Before running, load a project whose
# timeline has video + audio + text clips. Comparing empty near-black editors
# scores ~0.97 and hides the real gap (see docs/CAPCUT_UI_SHOWCASE_HANDOFF.md §4).
#
# Captures the window rect non-interactively via System Events (needs
# Accessibility permission for the terminal running this script:
# System Settings > Privacy & Security > Accessibility).
#
# Usage:
#   scripts/capture_capcut_parity.sh                 # MovieCut only
#   scripts/capture_capcut_parity.sh --with-capcut   # MovieCut + CapCut, then metrics
#
# Output: /tmp/moviecut-ui-evidence/*_window.png and side_by_side_metrics_populated.json

set -euo pipefail

OUT_DIR="${MOVIECUT_EVIDENCE_DIR:-/tmp/moviecut-ui-evidence}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_CAPCUT=0
[[ "${1:-}" == "--with-capcut" ]] && WITH_CAPCUT=1

mkdir -p "$OUT_DIR"

# Echo "x,y,w,h" bounds of window 1 for a process, or empty if not found.
window_bounds() {
  local proc="$1"
  osascript <<EOF 2>/dev/null || true
tell application "System Events"
  if not (exists process "$proc") then return ""
  tell process "$proc"
    if (count of windows) is 0 then return ""
    set p to position of window 1
    set s to size of window 1
    return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
  end tell
end tell
EOF
}

capture_window() {
  local proc="$1" label="$2"
  osascript -e "tell application \"System Events\" to set frontmost of process \"$proc\" to true" >/dev/null 2>&1 || true
  sleep 1
  local bounds
  bounds="$(window_bounds "$proc")"
  if [[ -z "$bounds" ]]; then
    echo "  ! $proc window not found — open it and load a populated project first." >&2
    return 1
  fi
  local out="$OUT_DIR/${label}_window.png"
  echo "  capturing $proc rect [$bounds] -> $out"
  screencapture -x -R "$bounds" "$out"
}

echo "Capturing MovieCut window..."
capture_window "MovieCutMac" "moviecut_current"

if [[ "$WITH_CAPCUT" == "1" ]]; then
  echo "Capturing CapCut window..."
  if capture_window "CapCut" "capcut_reference"; then
    echo "Computing region parity metrics..."
    python3 "$REPO_DIR/scripts/capcut_parity_metrics.py" \
      --capcut "$OUT_DIR/capcut_reference_window.png" \
      --moviecut "$OUT_DIR/moviecut_current_window.png" \
      --out "$OUT_DIR/side_by_side_metrics_populated.json" \
      --check
  fi
else
  echo
  echo "MovieCut captured. To compare against a CapCut reference, run:"
  echo "  python3 scripts/capcut_parity_metrics.py \\"
  echo "    --capcut $OUT_DIR/capcut_reference_window.png \\"
  echo "    --moviecut $OUT_DIR/moviecut_current_window.png \\"
  echo "    --out $OUT_DIR/side_by_side_metrics_populated.json --check"
fi
