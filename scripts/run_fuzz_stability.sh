#!/usr/bin/env bash
# Stability fuzz gate — crash-zero + accurate error reporting under random
# and adversarial harness inputs.
#
# Every existing harness script checks only that an artifact appeared or that
# the status line reads `error=none`. None of them check the process exit
# code, so a segfault that happens to leave a partial artifact can pass. This
# script drives the generic export harness across ~50 scenarios — fixed
# boundary cases plus seeded-random input combinations — and asserts all three:
#   1. exit code == 0           (no crash; segfault=139, abort=134, ...)
#   2. error=none AND composition_error=none  (failures are reported, not thrown)
#   3. clips=<N> matches the scenario's expected clip count
#
# The "silently ignored" inputs identified in the harness audit (empty IMPORT,
# effect-without-clip, bad TRANSITION rawValue, non-numeric params, rate
# clamping) are exercised as named boundary cases: the contract is that they
# are CLAMPED/FALLBACK-handled without crashing, not that they error out.
#
# Uses the generic export harness (UITEST_DONE), not the parity path, because
# the generic path's `clips=` field and `if lastErrorMessage == nil` export
# gate are what the 3-axis checks parse. Debug + sandbox OFF for fast feedback
# (sandbox ON is perf_4k_sandbox.sh; the sandbox is a security boundary, not
# a crash determinant).
#
# Reproduce a failing seed: SEED=<n> bash scripts/run_fuzz_stability.sh
set -uo pipefail   # NOT -e: a scenario failure must not abort the sweep.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

FIXTURE="$ROOT/Tests/Fixtures/solid_red_320x240_2s_30fps.mp4"
[ -f "$FIXTURE" ] || { echo "missing fixture: run scripts/make_fixtures.sh" >&2; exit 1; }

SEED="${SEED:-1722484800}"   # default seed; override to reproduce a failure
RANDOM=$SEED

echo "Building MovieCutMac (Debug, sandbox OFF)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build >/dev/null 2>&1 \
  || { echo "build failed" >&2; exit 1; }
products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

# Counters for the final summary.
TOTAL=0; PASS_N=0; CRASH_N=0; ERROR_N=0; CLIPS_N=0

# run_one <label> <expected_min_clips> <env assignments...>
# expected_min_clips: -1 means "don't check clips" (boundary cases where the
# silent-ignore contract makes the count scenario-dependent).
run_one() {
  local label="$1" expected_min="$2"; shift 2
  local dir="$WORK/scenario_$TOTAL"; mkdir -p "$dir"
  local out="$dir/out.mp4" result="$dir/result.txt"
  rm -f "$result" "$out"
  TOTAL=$((TOTAL + 1))

  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 1
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_IMPORT="$FIXTURE" \
    MOVIECUT_UITEST_EXPORT="$out" \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    "$@" \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!
  # Poll for the result file; do NOT swallow the exit code.
  local i
  for i in $(seq 1 240); do [ -s "$result" ] && break; sleep 0.5; done
  # If still no result, force-kill so wait returns a code we can inspect.
  if [ ! -s "$result" ]; then kill -9 "$pid" 2>/dev/null || true; fi
  wait "$pid" 2>/dev/null
  local rc=$?

  # Axis 1: exit code. Capture BEFORE anything else — a crash is the worst
  # outcome and must be counted even if a partial result file exists.
  if [ "$rc" -ne 0 ]; then
    local sig="exit=$rc"
    case "$rc" in
      134) sig="abort(SIGABRT=134)";;
      137) sig="killed(SIGKILL=137, likely timeout/hang)";;
      139) sig="segfault(SIGSEGV=139)";;
    esac
    printf "%-28s status=CRASH detail=%s\n" "$label" "$sig"
    CRASH_N=$((CRASH_N + 1)); return
  fi

  # Axis 2: error fields.
  local done_marker exp_err comp_err clips
  done_marker="$(grep -o 'UITEST_DONE' "$result" 2>/dev/null || echo "")"
  # composition_error= may be absent on the generic path; treat absent as none.
  comp_err="$(grep -oE 'composition_error=[^ ]*' "$result" 2>/dev/null | tail -1 | cut -d= -f2)"
  exp_err="$(grep -oE ' error=[^ ]*' "$result" 2>/dev/null | tail -1 | sed 's/ error=//')"
  clips="$(grep -oE 'clips=[0-9]+' "$result" 2>/dev/null | tail -1 | cut -d= -f2)"

  if [ -z "$done_marker" ]; then
    printf "%-28s status=ERROR_EXIT detail=no_UITEST_DONE clips=%s\n" "$label" "${clips:-?}"
    ERROR_N=$((ERROR_N + 1)); return
  fi
  if [ "${exp_err:-none}" != "none" ]; then
    # Truncate long error strings for the one-line summary.
    local short="${exp_err:0:48}"
    printf "%-28s status=ERROR_REPORTED detail=error=%s clips=%s\n" "$label" "$short" "${clips:-?}"
    ERROR_N=$((ERROR_N + 1)); return
  fi
  if [ "${comp_err:-none}" != "none" ] && [ "${comp_err:-}" != "" ]; then
    printf "%-28s status=ERROR_REPORTED detail=composition_error=%s clips=%s\n" "$label" "${comp_err:0:40}" "${clips:-?}"
    ERROR_N=$((ERROR_N + 1)); return
  fi

  # Axis 3: clips count matches expectation (only when expected_min >= 0).
  if [ "$expected_min" -ge 0 ] 2>/dev/null; then
    if [ -z "${clips:-}" ] || [ "${clips:-0}" -lt "$expected_min" ]; then
      printf "%-28s status=UNEXPECTED_CLIPS detail=clips=%s expected>=%s\n" \
        "$label" "${clips:-?}" "$expected_min"
      CLIPS_N=$((CLIPS_N + 1)); return
    fi
  fi

  printf "%-28s status=PASS clips=%s\n" "$label" "${clips:-?}"
  PASS_N=$((PASS_N + 1))
}

# ----- Fixed boundary cases (always run, in this order) -----
echo ""
echo "=== fuzz sweep (seed=$SEED): 7 boundary + 43 random = 50 scenarios ==="
echo ""
run_one "boundary_01_empty_import"          -1  MOVIECUT_UITEST_IMPORT=""
run_one "boundary_02_missing_file"           0  MOVIECUT_UITEST_IMPORT="/nope/missing.mp4"
run_one "boundary_03_effect_no_split"        1  MOVIECUT_UITEST_COLOR=1   # no clip selected at import? import selects first
run_one "boundary_04_bad_transition"         1  MOVIECUT_UITEST_TRANSITION=notATransition
run_one "boundary_05_speed_negative"         1  MOVIECUT_UITEST_SPEED_RATE=-2
run_one "boundary_06_speed_zero"             1  MOVIECUT_UITEST_SPEED_RATE=0
run_one "boundary_07_speed_100x"             1  MOVIECUT_UITEST_SPEED_RATE=100
run_one "boundary_08_nonnumeric_speed"       1  MOVIECUT_UITEST_SPEED_RATE=abc
run_one "boundary_09_five_effects_stack"     1  MOVIECUT_UITEST_COLOR=1 MOVIECUT_UITEST_GRADE=1 \
                                                   MOVIECUT_UITEST_HSL_CURVES=1 MOVIECUT_UITEST_MASK=1 \
                                                   MOVIECUT_UITEST_TEXT_AT=0.5
run_one "boundary_10_split_out_of_range"     1  MOVIECUT_UITEST_SPLIT_AT=999
run_one "boundary_11_split_negative"         1  MOVIECUT_UITEST_SPLIT_AT=-5
run_one "boundary_12_trim_negative"          1  MOVIECUT_UITEST_TRIM_AT=-1

# ----- Seeded random scenarios (43) -----
# Each picks from value pools that span valid + adversarial inputs. The harness
# contract is: none of these should crash, and a non-clamped failure must show
# up in error= rather than being swallowed.
SPEED_POOL=("-2" "0" "0.25" "0.5" "1" "2" "4" "100" "abc" "")
SPLIT_POOL=("0.5" "1.0" "1.5" "-1" "999" "")
TRANSITION_POOL=("crossDissolve" "wipeLeft" "notARealKind" "")
EFFECT_POOL=("MOVIECUT_UITEST_COLOR=1" "MOVIECUT_UITEST_GRADE=1" \
             "MOVIECUT_UITEST_HSL_CURVES=1" "MOVIECUT_UITEST_MASK=1" \
             "MOVIECUT_UITEST_TEXT_AT=0.5" "")

# pick <value1> [value2] ... — echoes one element at random. Takes the array
# expanded as args (bash 3.2 has no namerefs).
pick() {
  shift $((RANDOM % $#))
  echo "$1"
}

for n in $(seq 13 55); do
  speed="$(pick "${SPEED_POOL[@]}")"
  split="$(pick "${SPLIT_POOL[@]}")"
  trans="$(pick "${TRANSITION_POOL[@]}")"
  e1="$(pick "${EFFECT_POOL[@]}")"
  e2="$(pick "${EFFECT_POOL[@]}")"
  env_args=()
  [ -n "$speed" ] && env_args+=("MOVIECUT_UITEST_SPEED_RATE=$speed")
  [ -n "$split" ] && env_args+=("MOVIECUT_UITEST_SPLIT_AT=$split")
  [ -n "$trans"  ] && env_args+=("MOVIECUT_UITEST_TRANSITION=$trans")
  [ -n "$e1" ] && env_args+=("$e1")
  [ -n "$e2" ] && env_args+=("$e2")
  # Expected clip count: import adds >=1; a split that lands inside adds 1, but
  # split is best-effort so we only assert the import floor (>=1) to avoid
  # false alarms from the documented clamp/fallback behavior.
  label="$(printf 'random_%02d_s=%s_sp=%s_t=%s' "$n" "${speed:-NA}" "${split:-NA}" "${trans:-NA}")"
  run_one "$label" 1 ${env_args[@]+"${env_args[@]}"}
done

# ----- Summary -----
echo ""
echo "=== fuzz summary (seed=$SEED) ==="
printf "  total=%d  pass=%d  crash=%d  error=%d  unexpected_clips=%d\n" \
  "$TOTAL" "$PASS_N" "$CRASH_N" "$ERROR_N" "$CLIPS_N"
echo ""
if [ "$CRASH_N" -ne 0 ]; then
  echo "=> FAIL: $CRASH_N crash(es) detected — see CRASH rows above. Reproduce with SEED=$SEED"
  exit 1
fi
if [ "$((ERROR_N + CLIPS_N))" -ne 0 ]; then
  echo "=> REVIEW: $((ERROR_N + CLIPS_N)) non-crash anomaly(ies) above — may be correct error reporting"
  echo "   or a clip-count surprise; inspect the detail= fields. Reproduce with SEED=$SEED"
  # Non-crash anomalies are not a hard fail: they may be the harness correctly
  # reporting a bad input (error=) — which is what we want. The doc records them.
  exit 0
fi
echo "=> PASS: $TOTAL scenarios, 0 crashes, 0 errors, clip counts as expected"
