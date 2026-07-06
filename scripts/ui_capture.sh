#!/bin/bash
# Capture a deterministic populated MovieCut macOS editor window for U-08 UI evidence.
#
# Output policy:
#   - generated evidence: artifacts/ui/ (gitignored)
#   - committed goldens: Tests/UIEvidence/ (handled by ui_regression.sh)
#
# Usage:
#   scripts/ui_capture.sh [--out-dir artifacts/ui] [--no-build]
#
# Environment overrides:
#   MOVIECUT_UI_OUT_DIR       output directory (default: artifacts/ui)
#   MOVIECUT_UI_APP_PATH      existing MovieCutMac.app to launch
#   MOVIECUT_UI_IMPORT        media fixture to import
#   MOVIECUT_UI_WAIT_SECONDS  wait after launch before capture (default: 5)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${MOVIECUT_UI_OUT_DIR:-$REPO_DIR/artifacts/ui}"
NO_BUILD=0

usage() {
  sed -n '1,18p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    --no-build)
      NO_BUILD=1
      shift
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

mkdir -p "$OUT_DIR"
LOG_DIR="$OUT_DIR/logs"
mkdir -p "$LOG_DIR"

APP_PATH="${MOVIECUT_UI_APP_PATH:-}"
if [[ -z "$APP_PATH" ]]; then
  DERIVED_DATA="$OUT_DIR/DerivedData"
  APP_PATH="$DERIVED_DATA/Build/Products/Debug/MovieCutMac.app"
  if [[ "$NO_BUILD" != "1" || ! -x "$APP_PATH/Contents/MacOS/MovieCutMac" ]]; then
    echo "Building MovieCutMac for UI capture..."
    xcodebuild \
      -project "$REPO_DIR/MovieCut.xcodeproj" \
      -scheme MovieCutMac \
      -configuration Debug \
      -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED_DATA" \
      build >"$LOG_DIR/xcodebuild-ui-capture.log" 2>&1
  fi
fi

APP_BIN="$APP_PATH/Contents/MacOS/MovieCutMac"
if [[ ! -x "$APP_BIN" ]]; then
  echo "MovieCutMac executable not found: $APP_BIN" >&2
  exit 1
fi

IMPORT_FIXTURE="${MOVIECUT_UI_IMPORT:-$REPO_DIR/Tests/Fixtures/solid_red_tone_320x240_2s_30fps.mp4}"
if [[ ! -f "$IMPORT_FIXTURE" ]]; then
  echo "Import fixture missing: $IMPORT_FIXTURE" >&2
  exit 1
fi

RAW_OUT="$OUT_DIR/moviecut_populated_editor_raw.png"
META_OUT="$OUT_DIR/moviecut_populated_editor_capture.txt"
APP_LOG="$LOG_DIR/moviecut-ui-capture-app.log"
WAIT_SECONDS="${MOVIECUT_UI_WAIT_SECONDS:-5}"

# Close any stale app window from a prior capture to avoid capturing the wrong process/window.
osascript -e 'tell application "MovieCutMac" to quit' >/dev/null 2>&1 || true
sleep 1

echo "Launching MovieCutMac populated harness..."
set +m
(
  cd "$REPO_DIR"
  MOVIECUT_UITEST=1 \
  MOVIECUT_UITEST_IMPORT="$IMPORT_FIXTURE" \
  MOVIECUT_UITEST_TEXT_TEMPLATE_NAME="Title" \
  "$APP_BIN"
) >"$APP_LOG" 2>&1 &
APP_PID=$!
disown "$APP_PID" 2>/dev/null || true

cleanup() {
  if kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    sleep 1
    kill -9 "$APP_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

sleep "$WAIT_SECONDS"

window_bounds() {
  osascript <<'EOF' 2>/dev/null || true
tell application "System Events"
  if not (exists process "MovieCutMac") then return ""
  tell process "MovieCutMac"
    if (count of windows) is 0 then return ""
    set frontmost to true
    set p to position of window 1
    set s to size of window 1
    return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
  end tell
end tell
EOF
}

BOUNDS="$(window_bounds)"
if [[ -z "$BOUNDS" ]]; then
  echo "MovieCutMac window not found. Accessibility permission may be required for terminal/osascript." >&2
  echo "App log: $APP_LOG" >&2
  exit 1
fi

screencapture -x -R "$BOUNDS" "$RAW_OUT"
if [[ ! -s "$RAW_OUT" ]]; then
  echo "Capture failed or empty: $RAW_OUT" >&2
  exit 1
fi

cat >"$META_OUT" <<EOF
raw_capture=$RAW_OUT
bounds=$BOUNDS
app=$APP_PATH
import_fixture=$IMPORT_FIXTURE
app_log=$APP_LOG
EOF

echo "UI capture OK"
echo "raw_capture=$RAW_OUT"
echo "metadata=$META_OUT"
