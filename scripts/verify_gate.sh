#!/usr/bin/env bash
# Verification gate for autonomous work. Run from repo root.
# Exits 0 (PASS) only if all five checks succeed:
#   1. swift build
#   2. swift test (full, unfiltered)
#   3. xcodebuild MovieCutMac Debug macOS
#   4. xcodebuild MovieCutiOS Debug generic/iOS (W4 / kiro 9.3)
#   5. high-signal lint gate (scripts/lint_gate.sh allow-list)
# Writes a short status line to stdout for the runner to parse.
set -uo pipefail

# Resolve the repo root from the script location so this gate runs on any
# developer machine, not just the original author's home path.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

LOG="$REPO_ROOT/.build-check/last_gate.log"
: > "$LOG"

pass=true

# --- step 1: swift build ---
echo "[gate] step 1/5: swift build" | tee -a "$LOG"
if swift build >>"$LOG" 2>&1; then
  echo "[gate] swift build: OK" | tee -a "$LOG"
else
  echo "[gate] swift build: FAIL" | tee -a "$LOG"
  pass=false
fi

# --- step 2: swift test ---
# Streams output as it runs (tee into the gate log) instead of buffering via
# command substitution, and runs under a watchdog so a hung test process cannot
# stall the gate indefinitely. macOS ships no `timeout(1)`, so poll a background
# job and kill it (plus its children) when the budget is breached. Override the
# budget with SWIFT_TEST_TIMEOUT_S (default 900s, matching CI's 15 minutes).
SWIFT_TEST_TIMEOUT_S="${SWIFT_TEST_TIMEOUT_S:-900}"
echo "[gate] step 2/5: swift test (full, timeout ${SWIFT_TEST_TIMEOUT_S}s)" | tee -a "$LOG"
SWIFT_TEST_OUT="$REPO_ROOT/.build-check/last_swift_test.out"
: > "$SWIFT_TEST_OUT"
swift test > >(tee -a "$SWIFT_TEST_OUT" | tee -a "$LOG") 2>&1 &
TEST_PID=$!
TEST_RC=0
SECONDS=0
while kill -0 "$TEST_PID" 2>/dev/null; do
  if [ "$SECONDS" -ge "$SWIFT_TEST_TIMEOUT_S" ]; then
    echo "[gate] swift test: TIMEOUT after ${SECONDS}s — killing pid $TEST_PID and children" | tee -a "$LOG"
    pkill -P "$TEST_PID" 2>/dev/null
    kill -TERM "$TEST_PID" 2>/dev/null
    sleep 5
    pkill -9 -P "$TEST_PID" 2>/dev/null
    kill -9 "$TEST_PID" 2>/dev/null
    TEST_RC=124
    break
  fi
  sleep 5
done
if [ "$TEST_RC" -ne 124 ]; then
  wait "$TEST_PID"
  TEST_RC=$?
fi
# The definitive summary line looks like:
#   "✔ Test run with 984 tests in 162 suites passed after 6.0 seconds."  (PASS)
#   "✘ Test run with 984 tests in 162 suites failed after 6.0 seconds."  (FAIL)
# Match the EXACT tail keyword on the summary line, and require exit code 0.
# (Naive `grep failed` would false-positive on test NAMES like "A failed save...".)
SUMMARY_LINE=$(grep -E "Test run with [0-9]+ tests in [0-9]+ suites" "$SWIFT_TEST_OUT" | tail -1)
echo "[gate] swift test summary: ${SUMMARY_LINE:-<no summary line>}" | tee -a "$LOG"
if [ "$TEST_RC" -eq 0 ] && echo "$SUMMARY_LINE" | grep -q " suites passed "; then
  echo "[gate] swift test: OK" | tee -a "$LOG"
else
  echo "[gate] swift test: FAIL (rc=$TEST_RC)" | tee -a "$LOG"
  pass=false
fi

# --- step 3: xcodebuild (Mac) ---
echo "[gate] step 3/5: xcodebuild MovieCutMac" | tee -a "$LOG"
if xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build >>"$LOG" 2>&1; then
  echo "[gate] xcodebuild (Mac): OK" | tee -a "$LOG"
else
  echo "[gate] xcodebuild (Mac): FAIL" | tee -a "$LOG"
  pass=false
fi

# --- step 4: xcodebuild (iOS) ---
# This is the gate that would have caught the 7 IOSMaskCanvasView compile
# errors that hid behind the "iOS platform not installed" block for two weeks
# (fixed in cd1458f). The generic destination needs only the iOS SDK shipped
# with Xcode; CODE_SIGNING_ALLOWED=NO avoids any signing requirement.
echo "[gate] step 4/5: xcodebuild MovieCutiOS" | tee -a "$LOG"
if xcodebuild -project MovieCut.xcodeproj -scheme MovieCutiOS \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build >>"$LOG" 2>&1; then
  echo "[gate] xcodebuild (iOS): OK" | tee -a "$LOG"
else
  echo "[gate] xcodebuild (iOS): FAIL" | tee -a "$LOG"
  pass=false
fi

if $pass; then
  # --- step 5: high-signal lint gate (force_cast / force_try /
  # shorthand_operator — correctness-risk allow-list; see lint_gate.sh).
  # Runs LAST and only when the build/test stages passed, so a lint failure
  # is never masked by a compile failure. Missing SwiftLint is a hard fail:
  # the gate must not silently pass.
  echo "[gate] step 5/5: lint gate" | tee -a "$LOG"
  if bash "$REPO_ROOT/scripts/lint_gate.sh" >>"$LOG" 2>&1; then
    echo "[gate] lint gate: OK" | tee -a "$LOG"
  else
    echo "[gate] lint gate: FAIL" | tee -a "$LOG"
    pass=false
  fi
fi

# STAB-08: record this run's per-step verdicts into the history ledger the
# LOOP_STATE report generator reads (scripts/gen_loop_state_report.py).
# History is append-only JSON — the report table is generated, never edited.
record_gate_history() {
  local overall="GATE_FAIL"
  if $pass; then overall="GATE_PASS"; fi
  local step_line
  step_line=$(grep -oE "\[gate\] [A-Za-z /()]+: (OK|FAIL)" "$LOG" \
    | sed -E 's/\[gate\] //; s/ \(.*\)//; s/: /:/' \
    | awk -F: '{steps[$1]=$2} END {for (s in steps) printf "\"%s\":\"%s\",", s, steps[s]}')
  mkdir -p "$REPO_ROOT/.build-check/history"
  python3 - "$overall" "$step_line" <<'PYEOF'
import json, sys, time, re
overall, raw = sys.argv[1], sys.argv[2]
steps = {}
for pair in raw.split(","):
    if ":" in pair:
        k, v = pair.split(":", 1)
        k = k.strip().strip('"')
        v = v.strip().strip('"')
        if k and v in ("OK", "FAIL"):
            steps[k] = v
out = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
    "steps": steps,
    "overall": overall,
}
with open(f".build-check/history/gate-{int(time.time())}.json", "w") as f:
    json.dump(out, f)
PYEOF
}
record_gate_history

if $pass; then
  echo "GATE_PASS ${TEST_LINE:-}" | tee -a "$LOG"
  exit 0
else
  echo "GATE_FAIL" | tee -a "$LOG"
  exit 1
fi
