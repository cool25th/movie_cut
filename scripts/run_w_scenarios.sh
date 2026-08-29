#!/bin/bash
# W representative-job scenarios (development direction §1, plan §4's
# "대표 작업 성공률 90%+" measurement window) — each W is a real user job
# driven through the app's shipped feature paths by the in-app harness
# (MOVIECUT_UITEST_W_SCENARIO), finishing with its own export. This script
# runs W1-W5, reports per-step success + durations, and gates on:
#   - overall step success rate >= 90%
#   - every scenario produced a non-empty export
#
# W4 runs its Phase-1 variant: grading + audio mix + ProRes (the direction
# doc's adjustment layer is G-03, explicitly Phase-2 — reported as a delta).
#
# Usage: bash scripts/run_w_scenarios.sh [scenario ...]   # e.g. w1 w3
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIXTURES="$ROOT/Tests/Fixtures"
W_VOICE="$FIXTURES/noisy_voice_1k_hiss_8k_2s_mono.wav"
W_BGM="$FIXTURES/duck_bgm_220hz_4s_mono.wav"
W_VIDEO="$FIXTURES/solid_red_320x240_2s_30fps.mp4"
W_SUBJECT="$FIXTURES/moving_subject_320x240_2s_30fps.mp4"
W_IMAGE="$FIXTURES/swatch_blue_64x64.png"
for f in "$W_VOICE" "$W_BGM" "$W_VIDEO" "$W_SUBJECT" "$W_IMAGE"; do
  [ -s "$f" ] || { echo "missing fixture $f; run scripts/make_fixtures.sh" >&2; exit 1; }
done
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

SCENARIOS=("$@")
[ ${#SCENARIOS[@]} -eq 0 ] && SCENARIOS=(w1 w2 w3 w4 w5)


echo "Building MovieCutMac (Debug, sandbox OFF)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
PRODUCTS_DIR="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{sub(/\r/,"",$2); print $2; exit}')"
APP_BIN="$PRODUCTS_DIR/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

WORK="$(mktemp -d /tmp/moviecut-w.XXXXXX)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

# w2 needs music with actual onsets (the shipped BGM fixture is a steady
# 220 Hz sine — a real beat detector correctly finds nothing in it).
# Deterministic rhythmic fixture: 0.25s bursts at 4 Hz.
W_BEATS="$WORK/beats_4hz.wav"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "aevalsrc='0.8*sin(440*2*PI*t)*mod(floor(t*4)\,2)':d=4:s=44100" \
  "$W_BEATS" || { echo "beat fixture generation failed" >&2; exit 1; }

run_scenario() {
  local scenario="$1"
  local dir="$WORK/$scenario"
  mkdir -p "$dir"
  rm -f "$dir/status.txt" "$dir/w.json"

  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_W_SCENARIO="$scenario" \
    MOVIECUT_UITEST_W_EXPORT="$dir" \
    MOVIECUT_UITEST_W_RESULT="$dir/w.json" \
    MOVIECUT_UITEST_W_VOICE="$W_VOICE" \
    MOVIECUT_UITEST_W_BGM="$W_BGM" \
    MOVIECUT_UITEST_W_VIDEO="$W_VIDEO" \
    MOVIECUT_UITEST_W_SUBJECT="$W_SUBJECT" \
    MOVIECUT_UITEST_W_IMAGE="$W_IMAGE" \
    MOVIECUT_UITEST_W_BEATS="$W_BEATS" \
    MOVIECUT_UITEST_RESULT="$dir/status.txt" \
    MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!
  ( sleep 360; kill "$pid" 2>/dev/null; pkill -x MovieCutMac 2>/dev/null; true ) &
  local watchdog=$!
  # STAB-01: record the watchdog subshell's inner sleep PID while the
  # subshell is STILL ALIVE. After `kill $watchdog` the sleep re-parents to
  # launchd and `pkill -P` can no longer see it (the previous "remediation"
  # reaped nothing and left a 360s orphan per scenario). Held PIDs are the
  # canonical fix per the stabilization plan.
  local watchdog_sleep=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    watchdog_sleep="$(pgrep -P "$watchdog" -x sleep 2>/dev/null | head -1 || true)"
    if [ -n "$watchdog_sleep" ]; then break; fi
    sleep 0.05
  done
  for _ in $(seq 1 600); do
    grep -q "W_DONE" "$dir/status.txt" 2>/dev/null && break
    sleep 0.5
  done
  kill "$watchdog" 2>/dev/null || true
  if [ -n "$watchdog_sleep" ]; then
    kill "$watchdog_sleep" 2>/dev/null || true
  fi
  wait "$watchdog" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  # STAB-01 evidence: the recorded sleep must be gone after reaping — an
  # alive PID here means an orphan survived the cleanup.
  if [ -n "$watchdog_sleep" ] && kill -0 "$watchdog_sleep" 2>/dev/null; then
    echo "$scenario status=FAIL detail=watchdog_sleep_orphaned pid=$watchdog_sleep"
    return 1
  fi

  [ -s "$dir/w.json" ] || { echo "$scenario status=FAIL detail=no_result_json"; return 1; }
}

echo ""
declare -a SUMMARY
for scenario in "${SCENARIOS[@]}"; do
  echo "=== $scenario ==="
  run_scenario "$scenario" || { echo "W SCENARIOS FAIL ($scenario did not produce a result)" >&2; exit 1; }
  python3 - "$WORK/$scenario/w.json" "$scenario" <<'PY'
import json, sys

dump = json.load(open(sys.argv[1]))
scenario = sys.argv[2]
lines = []
for step in dump.get("steps", []):
    mark = "OK " if step["ok"] else "FAIL"
    detail = f" ({step['detail']})" if step.get("detail") else ""
    lines.append(f"  [{mark}] {step['name']}{detail}")
ok = sum(1 for s in dump.get("steps", []) if s["ok"])
total = len(dump.get("steps", []))
print("\n".join(lines))
print(f"  export_bytes={dump.get('exportBytes', 0)} elapsed={dump.get('elapsedSeconds', 0):.1f}s error={dump.get('error', 'none')}")
# Machine summary for the gate.
print(f"SUMMARY {scenario} {ok} {total} {dump.get('exportBytes', 0)}")
PY
done | tee "$WORK/all.log"

echo ""
python3 - "$WORK/all.log" <<'PY'
import re, sys

# Review P0: the direction doc's gate is the success rate of the five
# representative WORKFLOWS, not the average of their steps — a workflow whose
# required deliverable failed (e.g. W4 without its ProRes output) must count
# as a failed workflow even when its other steps passed. A workflow passes
# only when EVERY step succeeded AND it produced its export.
rate_fail = 0
totals = [0, 0]
workflows_passed = 0
workflows_total = 0
for line in open(sys.argv[1]):
    m = re.match(r"SUMMARY (\w+) (\d+) (\d+) (\d+)", line)
    if not m:
        continue
    name, ok, total, export_bytes = m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4))
    totals[0] += ok
    totals[1] += total
    workflows_total += 1
    steps_ok = ok == total
    export_ok = export_bytes > 0
    if steps_ok and export_ok:
        workflows_passed += 1
        print(f"WORKFLOW {name}: PASS (steps {ok}/{total}, export {export_bytes}B)")
    else:
        why = "no export" if not export_ok else f"steps {ok}/{total}"
        print(f"WORKFLOW {name}: FAIL ({why})")
        rate_fail = 1
if totals[1] == 0 or workflows_total == 0:
    print("FAIL: no steps recorded")
    sys.exit(1)
rate = 100.0 * workflows_passed / workflows_total
print(f"W SCENARIOS: workflows {workflows_passed}/{workflows_total} — success rate {rate:.1f}% (gate: >= 90%; step detail {totals[0]}/{totals[1]})")
if rate < 90.0:
    print("FAIL: workflow success rate below 90%")
    sys.exit(1)
sys.exit(rate_fail)
PY
echo "W SCENARIOS PASS"
