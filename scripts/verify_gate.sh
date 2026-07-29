#!/usr/bin/env bash
# Verification gate for autonomous work. Run from repo root.
# Exits 0 (PASS) only if all three checks succeed:
#   1. swift build
#   2. swift test (full, unfiltered — baseline 984 tests, 0 failures)
#   3. xcodebuild MovieCutMac Debug macOS
# Writes a short status line to stdout for the runner to parse.
set -uo pipefail

cd /Users/cool-mini4/MyDev/automation/movie_cut

LOG=/Users/cool-mini4/MyDev/automation/movie_cut/.build-check/last_gate.log
: > "$LOG"

pass=true

# --- step 1: swift build ---
echo "[gate] step 1/3: swift build" | tee -a "$LOG"
if swift build >>"$LOG" 2>&1; then
  echo "[gate] swift build: OK" | tee -a "$LOG"
else
  echo "[gate] swift build: FAIL" | tee -a "$LOG"
  pass=false
fi

# --- step 2: swift test ---
echo "[gate] step 2/3: swift test (full)" | tee -a "$LOG"
TEST_OUT=$(swift test 2>&1)
TEST_RC=$?
echo "$TEST_OUT" >>"$LOG"
# The definitive summary line looks like:
#   "✔ Test run with 984 tests in 162 suites passed after 6.0 seconds."  (PASS)
#   "✘ Test run with 984 tests in 162 suites failed after 6.0 seconds."  (FAIL)
# Match the EXACT tail keyword on the summary line, and require exit code 0.
# (Naive `grep failed` would false-positive on test NAMES like "A failed save...".)
SUMMARY_LINE=$(echo "$TEST_OUT" | grep -E "Test run with [0-9]+ tests in [0-9]+ suites" | tail -1)
echo "[gate] swift test summary: ${SUMMARY_LINE:-<no summary line>}" | tee -a "$LOG"
if [ "$TEST_RC" -eq 0 ] && echo "$SUMMARY_LINE" | grep -q " suites passed "; then
  echo "[gate] swift test: OK" | tee -a "$LOG"
else
  echo "[gate] swift test: FAIL (rc=$TEST_RC)" | tee -a "$LOG"
  pass=false
fi

# --- step 3: xcodebuild ---
echo "[gate] step 3/3: xcodebuild MovieCutMac" | tee -a "$LOG"
if xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build >>"$LOG" 2>&1; then
  echo "[gate] xcodebuild: OK" | tee -a "$LOG"
else
  echo "[gate] xcodebuild: FAIL" | tee -a "$LOG"
  pass=false
fi

if $pass; then
  echo "GATE_PASS ${TEST_LINE:-}" | tee -a "$LOG"
  exit 0
else
  echo "GATE_FAIL" | tee -a "$LOG"
  exit 1
fi
