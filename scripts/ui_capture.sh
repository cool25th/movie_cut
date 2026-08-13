#!/bin/bash
# Capture a deterministic MovieCut macOS editor window for UI evidence.
#
# Generalized to capture NAMED editor states (import-only, +text, +color grade,
# +mask, …) so the dhash regression gate (ui_regression.sh) can cover more than
# one layout. Each state maps to a harness env-var set; the harness already
# drives ~30+ editor states via MOVIECUT_UITEST_* vars.
#
# Output policy:
#   - generated evidence: artifacts/ui/ (gitignored)
#   - committed goldens: Tests/UIEvidence/ (handled by ui_regression.sh)
#
# Usage:
#   scripts/ui_capture.sh [--state <name>] [--out-dir artifacts/ui] [--no-build]
#   scripts/ui_capture.sh --state with_color_grade
#
# The default state is "populated_editor" (the original single capture) for
# backward compatibility. Capture ALL states with --state all.
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
STATE="populated_editor"

usage() {
  sed -n '1,22p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      STATE="$2"
      shift 2
      ;;
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

# --- Named editor states → harness env-var sets ---------------------------
# Each state is a set of EXTRA harness vars applied on top of MOVIECUT_UITEST=1
# + MOVIECUT_UITEST_IMPORT. Only states that produce a VISUALLY DISTINCT editor
# are useful for the dhash gate — the harness must drive the UI far enough that
# a screenshot differs. As of this commit, only the import baseline and the
# text-applied state are visually distinct; grade/mask change pixels too
# subtly (or only inside an inspector sheet that the harness doesn't open), so
# dhash sees no change. Re-add with_text_extra/with_color_grade/with_mask once
# the harness opens the relevant inspector panel for them.
# Implemented with case statements (not associative arrays) for bash-3.2.
ALL_STATES="import_only populated_editor"

state_extra_env() {
  case "$1" in
    import_only) printf '' ;;
    populated_editor) printf 'MOVIECUT_UITEST_TEXT_TEMPLATE_NAME=Title' ;;
    *) return 1 ;;
  esac
}

# Build the app once (shared across all states when --state all).
APP_PATH="${MOVIECUT_UI_APP_PATH:-}"
build_app() {
  # A prebuilt app path takes precedence and skips the build entirely.
  if [[ -n "$APP_PATH" ]]; then
    return 0
  fi
  local derived_data="$OUT_DIR/DerivedData"
  APP_PATH="$derived_data/Build/Products/Debug/MovieCutMac.app"
  if [[ "$NO_BUILD" != "1" ]]; then
    echo "Building MovieCutMac for UI capture..."
    # ENABLE_APP_SANDBOX=NO: the shipping build is sandboxed (project.yml),
    # but the sandbox blocks the headless harness from reaching files passed
    # via MOVIECUT_UITEST_IMPORT (no security-scoped grant at launch), which
    # surfaces as NSCocoaErrorDomain:257 "permission denied" on import. The
    # sandbox is a security boundary, not a rendering cost, so disabling it
    # here doesn't change what the screenshot measures. Same approach as the
    # perf scripts (perf_4k.sh).
    xcodebuild \
      -project "$REPO_DIR/MovieCut.xcodeproj" \
      -scheme MovieCutMac \
      -configuration Debug \
      -destination 'platform=macOS' \
      -derivedDataPath "$derived_data" \
      ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO \
      build >"$LOG_DIR/xcodebuild-ui-capture.log" 2>&1
  fi
}

# capture_one <state_name>
capture_one() {
  local state="$1"
  local extra; extra="$(state_extra_env "$state")" || {
    echo "unknown state: $state" >&2
    echo "known states: all $ALL_STATES" >&2
    return 2
  }
  local app_bin="$APP_PATH/Contents/MacOS/MovieCutMac"
  if [[ ! -x "$app_bin" ]]; then
    echo "MovieCutMac executable not found: $app_bin" >&2
    exit 1
  fi

  local import_fixture="${MOVIECUT_UI_IMPORT:-$REPO_DIR/Tests/Fixtures/solid_red_tone_320x240_2s_30fps.mp4}"
  if [[ ! -f "$import_fixture" ]]; then
    echo "Import fixture missing: $import_fixture" >&2
    exit 1
  fi

  local raw_out="$OUT_DIR/moviecut_${state}_raw.png"
  local meta_out="$OUT_DIR/moviecut_${state}_capture.txt"
  local app_log="$LOG_DIR/moviecut-ui-${state}.log"
  local wait_seconds="${MOVIECUT_UI_WAIT_SECONDS:-5}"

  osascript -e 'tell application "MovieCutMac" to quit' >/dev/null 2>&1 || true
  sleep 1

  echo "Launching MovieCutMac harness state='${state}'..."
  set +m
  (
    cd "$REPO_DIR"
    export MOVIECUT_UITEST=1
    export MOVIECUT_UITEST_IMPORT="$import_fixture"
    # Apply the state's extra KEY=VAL vars.
    if [[ -n "$extra" ]]; then
      for kv in $extra; do export "$kv"; done
    fi
    "$app_bin"
  ) >"$app_log" 2>&1 &
  local app_pid=$!
  disown "$app_pid" 2>/dev/null || true

  cleanup() {
    if kill -0 "$app_pid" >/dev/null 2>&1; then
      kill "$app_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$app_pid" >/dev/null 2>&1 || true
    fi
  }

  sleep "$wait_seconds"

  local bounds; bounds="$(osascript <<'OSA' 2>/dev/null || true
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
OSA
)"
  if [[ -z "$bounds" ]]; then
    echo "MovieCutMac window not found for state='${state}'. Accessibility permission may be required for terminal/osascript." >&2
    echo "App log: $app_log" >&2
    cleanup
    return 1
  fi

  screencapture -x -R "$bounds" "$raw_out"
  if [[ ! -s "$raw_out" ]]; then
    echo "Capture failed or empty: $raw_out (state='${state}')" >&2
    cleanup
    return 1
  fi

  cat >"$meta_out" <<EOF
state=$state
raw_capture=$raw_out
bounds=$bounds
app=$APP_PATH
import_fixture=$import_fixture
extra_env=$extra
app_log=$app_log
EOF
  echo "  ${state}: OK -> $raw_out"
  cleanup
}

build_app

if [[ "$STATE" == "all" ]]; then
  fail=0
  for s in $ALL_STATES; do
    capture_one "$s" || fail=1
  done
  if [[ "$fail" -ne 0 ]]; then
    echo "one or more states failed to capture" >&2
    exit 1
  fi
else
  if ! state_extra_env "$STATE" >/dev/null; then
    echo "unknown state: $STATE" >&2
    echo "known states: all $ALL_STATES" >&2
    exit 2
  fi
  capture_one "$STATE"
fi

echo "UI capture OK"
