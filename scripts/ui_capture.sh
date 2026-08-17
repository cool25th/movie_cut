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
# are useful for the dhash gate. The inspector states rely on
# MOVIECUT_UITEST_INSPECTOR_TAB, which the harness applies AFTER all
# selection-changing gates (the inspector resets the tab on selection change),
# so opening the Adjustment / Mask sections is what makes these states visibly
# different from the import baseline.
# Implemented with case statements (not associative arrays) for bash-3.2.
ALL_STATES="import_only populated_editor with_color_grade with_mask"

state_extra_env() {
  case "$1" in
    import_only) printf '' ;;
    populated_editor) printf 'MOVIECUT_UITEST_TEXT_TEMPLATE_NAME=Title' ;;
    with_color_grade) printf 'MOVIECUT_UITEST_GRADE=1 MOVIECUT_UITEST_INSPECTOR_TAB=Adjustment' ;;
    with_mask) printf 'MOVIECUT_UITEST_MASK=1 MOVIECUT_UITEST_INSPECTOR_TAB=Mask' ;;
    # Manual-inspection states: captured on demand (--state basic_inspector)
    # but excluded from ALL_STATES so the regression gate is unchanged until a
    # golden is deliberately committed for them.
    basic_inspector) printf 'MOVIECUT_UITEST_GRADE=1 MOVIECUT_UITEST_INSPECTOR_TAB=Basic' ;;
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

  # Preflight (diagnosis doc §7.1/§13-P0): hard-clear stale instances and
  # verify the GUI console session belongs to the current user — an app
  # launched into a non-interactive/switched session can come up windowless
  # and every downstream step would conflate that with a permission failure.
  pkill -9 -x MovieCutMac >/dev/null 2>&1 || true
  sleep 1
  local console_user
  console_user="$(stat -f '%Su' /dev/console 2>/dev/null || true)"
  if [[ -n "$console_user" && "$console_user" != "$(id -un)" ]]; then
    echo "PREFLIGHT_FAIL: console user is '${console_user}' but harness runs as '$(id -un)' (switched/locked session) — refusing state='${state}'" >&2
    return 1
  fi
  local preexisting_pids
  preexisting_pids="$(pgrep -x MovieCutMac 2>/dev/null | tr '\n' ' ')"

  echo "Launching MovieCutMac harness state='${state}'..."
  # Launch through Launch Services (`open`), not a bare executable: the
  # parity/E2E harnesses that launch this way never showed the windowless
  # failure the direct-exec path did intermittently (diagnosis doc §12 —
  # strongest single clue). `open` hands the app a proper GUI bootstrap
  # context; env vars ride the documented --env flags.
  local -a open_env=(--env "MOVIECUT_UITEST=1" --env "MOVIECUT_UITEST_IMPORT=$import_fixture")
  if [[ -n "$extra" ]]; then
    local kv
    for kv in $extra; do open_env+=(--env "$kv"); done
  fi
  open -n "${open_env[@]}" "$APP_PATH" >/dev/null 2>&1 &
  local open_pid=$!
  disown "$open_pid" 2>/dev/null || true

  # Resolve the NEW app PID (not name-based: multiple/stale instances must
  # never be confused for ours — diagnosis doc §7.2).
  local app_pid=""
  for _ in $(seq 1 30); do
    local candidate found=0
    for candidate in $(pgrep -x MovieCutMac 2>/dev/null); do
      if [[ " $preexisting_pids " != *" $candidate "* ]]; then
        app_pid="$candidate"; found=1; break
      fi
    done
    [[ "$found" == 1 ]] && break
    sleep 0.5
  done
  if [[ -z "$app_pid" ]]; then
    echo "LAUNCH_FAIL: no new MovieCutMac process appeared within 15s for state='${state}'" >&2
    echo "App log: $app_log" >&2
    return 1
  fi

  cleanup() {
    if kill -0 "$app_pid" >/dev/null 2>&1; then
      kill "$app_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -9 "$app_pid" >/dev/null 2>&1 || true
    fi
  }

  # Bounded polling for the window (replaces the fixed sleep): distinguishes
  # the failure classes the old script collapsed into "window not found" —
  # process missing / window count 0 / query error — and records the
  # osascript stderr verbatim for later diagnosis (doc §10).
  local bounds="" osa_status="WINDOW_NOT_FOUND" osa_err=""
  for _ in $(seq 1 40); do
    local osa_out
    osa_out="$(osascript - "$app_pid" 2>/tmp/moviecut-ui-osa.err <<'OSA'
on run (argv)
  set targetPID to (item 1 of argv) as integer
  tell application "System Events"
    set procList to (every process whose unix id is targetPID)
    if (count of procList) is 0 then return "PROCESS_MISSING"
    tell item 1 of procList
      if (count of windows) is 0 then return "WINDOW_COUNT_0"
      set frontmost to true
      delay 0.2
      set p to position of window 1
      set s to size of window 1
      return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
    end tell
  end tell
end run
OSA
)" || true
    if [[ "$osa_out" =~ ^[0-9]+,[0-9]+,[0-9]+,[0-9]+$ ]]; then
      bounds="$osa_out"; osa_status="WINDOW_FOUND"; break
    fi
    if [[ -n "$osa_out" ]]; then osa_status="$osa_out"; fi
    osa_err="$(cat /tmp/moviecut-ui-osa.err 2>/dev/null)"
    # Process gone or query error will not heal by waiting.
    if [[ "$osa_status" == "PROCESS_MISSING" || -n "$osa_err" ]]; then break; fi
    sleep 0.5
  done
  # Persist the structured diagnosis next to the state log.
  printf 'status=%s pid=%s osa_err=%s\n' "$osa_status" "$app_pid" "$osa_err" \
    >"$LOG_DIR/moviecut-ui-${state}-window.txt"
  if [[ -z "$bounds" ]]; then
    echo "WINDOW_NOT_FOUND: state='${state}' status='${osa_status}' pid=${app_pid} (osascript stderr: ${osa_err:-none})" >&2
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
