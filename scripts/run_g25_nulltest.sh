#!/bin/bash
# G-25 Inc 8 App half — preview↔export audio graph null test gate (spec §9).
#
# Launches the REAL app process (DEBUG harness) with
# MOVIECUT_UITEST_AUDIO_GRAPH_NULLTEST, which renders the SAME audio render
# graph through BOTH engine generators in-process:
#
#   (a) preview  — a real AVAudioEngine (offline manual rendering:
#                  source nodes → per-bus mixers → main mixer)
#   (b) export   — the encoder input (latency-compensated pure render)
#
# and judges them with the ONE shared comparator (AudioGraphNullTest): best
# alignment searched within ±1 sample, then max absolute deviation over the
# whole overlap must stay within one 16-bit LSB (§9.2·§9.3). It also performs
# the §9.4 MEASURED drift check: a 60-minute mixed-rate (48k graph + 44.1k
# source) tail rendered by both engines over the same absolute window — the
# tail alignment offset IS the end-point drift — plus the exact Int64
# round-trip of the 60-minute end position (172,800,000 samples at 48 kHz).
#
# The swift-test-level plumbing checks live in
# Tests/MovieCutCoreTests/AudioGraphEngineNullTests.swift; per spec §9.5 the
# MEASURED judgment is E2E-only — this script is that gate.
#
# Sources are deterministic synthetic sines generated in-app, so repeated
# runs must reproduce identical numbers (the JSON artifact is kept for
# comparison on failure).
#
# Usage: bash scripts/run_g25_nulltest.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WATCHDOG_SECONDS=180

# --- 1. Build (sandbox OFF, same rationale as run_e2e_export.sh) -----------
echo "Building MovieCutMac (Debug, sandbox OFF)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' \
  ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO \
  build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' \
  ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
APP="$PRODUCTS_DIR/MovieCutMac.app"
[[ -d "$APP" ]] || { echo "app not found at $APP" >&2; exit 1; }

WORK_DIR="$(mktemp -d /tmp/moviecut-g25-nulltest.XXXXXX)"
RESULT="$WORK_DIR/result.txt"
DUMP="$WORK_DIR/graph_nulltest.json"

# --- 2. Run the in-app null test --------------------------------------------
# The ducking-harness BGM/Voice project (two audio tracks with the real
# planner ducking applied) feeds the §9.1 REAL-PROJECT phase:
# AudioGraphProjectBuilder maps the actual mix to a graph, both engines
# render it, and the graph mix's loudness is compared against the preview
# audio-mix render (migration parity — LUFS tolerance, not a null gate).
# NO video import here, deliberately: video import + ducking tracks +
# AVAssetExportSession (the preview-mix render) is the KNOWN deadlock combo
# on record (LOOP_STATE 기존 결함), and the audio-less solid_red fixture
# contributes nothing to the graph — video-embedded-audio mapping stays
# covered by builder unit tests until the graph switchover structurally
# fixes that deadlock.
BGM="$ROOT/Tests/Fixtures/duck_bgm_220hz_4s_mono.wav"
VOICE="$ROOT/Tests/Fixtures/duck_voice_1000hz_1s_mono.wav"
echo "Running G-25 §9 null test (AVAudioEngine preview ↔ encoder input + real project)…"
open -n -W \
  --env MOVIECUT_UITEST=1 \
  --env MOVIECUT_UITEST_DUCKING_BGM="$BGM" \
  --env MOVIECUT_UITEST_DUCKING_VOICE="$VOICE" \
  --env MOVIECUT_UITEST_AUDIO_GRAPH_NULLTEST="$DUMP" \
  --env MOVIECUT_UITEST_RESULT="$RESULT" \
  --env MOVIECUT_UITEST_QUIT=1 \
  "$APP" &
OPEN_PID=$!
( sleep "$WATCHDOG_SECONDS"; kill "$OPEN_PID" >/dev/null 2>&1; \
  pkill -f "$APP/Contents/MacOS/MovieCutMac" >/dev/null 2>&1; true ) &
WATCHDOG_PID=$!
set +e
wait "$OPEN_PID"
OPEN_RC=$?
set -e
kill "$WATCHDOG_PID" >/dev/null 2>&1 || true
wait "$WATCHDOG_PID" 2>/dev/null || true

if [[ ! -s "$RESULT" ]]; then
  echo "FAIL: no result written (watchdog timeout? see $WORK_DIR)" >&2
  exit 1
fi
STATUS="$(cat "$RESULT")"
echo "status: $STATUS"

fail=0
grep -q "audio_graph_nulltest_done" <<<"$STATUS" || { echo "FAIL: null test did not complete" >&2; fail=1; }
grep -q "error=none" <<<"$STATUS" || { echo "FAIL: error reported in status" >&2; fail=1; }
GRAPHS="$(sed -n 's/.*graphs=\([0-9]*\) passed.*/\1/p' <<<"$STATUS")"
PASSED="$(sed -n 's/.*graphs=[0-9]* passed=\([0-9]*\).*/\1/p' <<<"$STATUS")"
if [[ -z "$GRAPHS" || "$GRAPHS" -lt 2 || "$PASSED" != "$GRAPHS" ]]; then
  echo "FAIL: expected all graphs to pass (graphs=$GRAPHS passed=$PASSED)" >&2
  fail=1
fi
grep -q "project_graph=1" <<<"$STATUS" || { echo "FAIL: real-project graph phase did not run" >&2; fail=1; }
grep -q "project_graph_passed=1" <<<"$STATUS" || { echo "FAIL: real-project graph engines disagree" >&2; fail=1; }
PARITY="$(sed -n 's/.*project_parity_lufs=\(-\{0,1\}[0-9.]*\).*/\1/p' <<<"$STATUS")"
if [[ -z "$PARITY" ]]; then
  echo "FAIL: project parity LUFS missing (silent mix?)" >&2; fail=1
elif python3 -c "import sys; sys.exit(0 if abs(float('$PARITY')) <= 1.0 else 1)"; then
  :
else
  echo "FAIL: graph↔preview-mix parity |ΔLUFS|=$PARITY exceeds 1.0 LU" >&2; fail=1
fi
grep -q "drift_passed=1" <<<"$STATUS" || { echo "FAIL: drift_passed=1 missing" >&2; fail=1; }
grep -q "drift_roundtrip=1" <<<"$STATUS" || { echo "FAIL: exact 60-minute round trip missing" >&2; fail=1; }
grep -q "drift_timeline_end=172800000" <<<"$STATUS" || { echo "FAIL: 60-minute end is not exactly 172,800,000 samples" >&2; fail=1; }
DRIFT_OFFSET="$(sed -n 's/.*drift_offset=\(-\{0,1\}[0-9]*\).*/\1/p' <<<"$STATUS")"
if [[ -z "$DRIFT_OFFSET" || "$DRIFT_OFFSET" -gt 1 || "$DRIFT_OFFSET" -lt -1 ]]; then
  echo "FAIL: measured 60-minute drift offset $DRIFT_OFFSET exceeds ±1 sample (spec §9.4 budget: ≤1 video frame)" >&2
  fail=1
fi

# --- 3. JSON artifact cross-check --------------------------------------------
if [[ -s "$DUMP" ]]; then
  /usr/bin/python3 - "$DUMP" <<'PY' || fail=1
import json, sys

dump = json.load(open(sys.argv[1]))
problems = []
if dump.get("error", "none") != "none":
    problems.append("dump error: %s" % dump["error"])
for graph in dump.get("graphs", []):
    if not graph["passed"]:
        problems.append("graph %s failed (offset=%d maxDev=%g lsb=%g)"
                        % (graph["name"], graph["bestOffsetSamples"],
                           graph["maxAbsoluteDeviation"], graph["lsb16"]))
    if graph["maxAbsoluteDeviation"] > graph["lsb16"]:
        problems.append("graph %s exceeds one 16-bit LSB" % graph["name"])
    print("graph %-12s frames=%-5d offset=%d maxDev=%.3e lsb=%.3e passed=%s"
          % (graph["name"], graph["frames"], graph["bestOffsetSamples"],
             graph["maxAbsoluteDeviation"], graph["lsb16"], graph["passed"]))
print("drift: timeline_end=%d tail_frames=%d offset=%d roundtrip=%s passed=%s elapsed=%.2fs"
      % (dump["driftTimelineEndSamples"], dump["driftTailFrames"],
         dump["driftBestOffsetSamples"], dump["driftRoundTripExact"],
         dump["driftPassed"], dump["elapsedSeconds"]))
if len(dump.get("graphs", [])) < 3:
    problems.append("expected at least 3 graphs (incl. the real project)")
if not dump.get("projectGraphRendered"):
    problems.append("real-project graph phase did not run")
elif not dump.get("projectGraphPassed"):
    problems.append("real-project graph engines disagree")
parity = dump.get("projectParityDeltaLufs")
if parity is None:
    problems.append("project parity LUFS missing")
elif abs(parity) > 1.0:
    problems.append("graph↔preview-mix parity %.2f LU exceeds 1.0" % parity)
else:
    print("project: frames=%d engines-null=%s parity=%.2f LU" % (
        dump.get("projectGraphFrames", 0), dump.get("projectGraphPassed"), parity))
if not dump["driftPassed"]:
    problems.append("drift measurement failed")
if problems:
    print("FAIL: " + "; ".join(problems))
    sys.exit(1)
PY
else
  echo "FAIL: JSON artifact missing: $DUMP" >&2
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  echo "G-25 NULL TEST GATE FAIL (artifacts preserved in $WORK_DIR)" >&2
  exit 1
fi

rm -rf "$WORK_DIR"
echo "G-25 NULL TEST GATE PASS (graphs=$PASSED passed incl. real project, parity=$PARITY LU, drift offset=$DRIFT_OFFSET sample, 60min end exact)"
