#!/usr/bin/env bash
# Long-form soak gate (review 2026-08-28 #6 — "장편 메모리·soak 검증").
#
# Runs N consecutive REAL-app exports of the 30-minute benchmark fixture and
# enforces the stability properties a long-form claim needs:
#   1. every run completes within the watchdog (no hang/teardown leak)
#   2. peak RSS growth across runs <= 15%  (accumulating-leak guard)
#   3. A/V start offset within one frame, duration within one frame of 1800s
#   4. cross-run output determinism: identical frame hashes at 9 sampled
#      timestamps (same project exported twice must produce the same pixels)
#   5. thermal + power conditions recorded with every number (§1.4)
#
# Uses the generic UITest harness (import → export; no preview dumps) and the
# ab_benchmark fixture set (regenerated on demand by make_ab_fixtures.sh).
#
# Usage:  bash scripts/run_longform_soak.sh [runs]   # default 2
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }

RUNS="${1:-2}"
WATCHDOG_S="${WATCHDOG_S:-2400}"
# 2400s: sustained-load realism. Measured 2026-08-28 — run 1 completes in
# ~873s, but the SECOND back-to-back run outran a 1500s watchdog (thermal
# throttling under sustained encode is exactly the condition this gate
# exists to observe, so the budget accommodates it instead of hiding it).
FIXTURE="$ROOT/artifacts/ab_benchmark/fixtures/ab04_interview_640x360_30min.mp4"
WORK="$(mktemp -d /tmp/soak.XXXXXX)"
trap 'rm -rf "$WORK"; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true' EXIT

bash "$ROOT/scripts/make_ab_fixtures.sh" >/dev/null
[ -s "$FIXTURE" ] || { echo "missing fixture" >&2; exit 1; }

echo "[soak] conditions:"
sysctl -n hw.model machdep.cpu.brand_string | tr '\n' ' '; echo
echo "os=$(sw_vers -productVersion) commit=$(git rev-parse --short HEAD) runs=$RUNS thermal=$(pmset -g therm | tail -1 | cut -c1-60)"

echo "[soak] building MovieCutMac (Debug, sandbox OFF)…"
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' ENABLE_APP_SDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
  -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')" || true
APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
[ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }

run_export() { # $1 = run index → writes $WORK/run$1.{mp4,rss,wall} + result
  local idx="$1"
  local out="$WORK/run$idx.mp4"
  local result="$WORK/run$idx.result"
  rm -f "$result" "$out"
  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true; sleep 2

  local start
  start=$(python3 -c 'import time; print(time.time())')
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_IMPORT="$FIXTURE" \
    MOVIECUT_UITEST_EXPORT="$out" \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!
  ( sleep "$WATCHDOG_S"; kill "$pid" 2>/dev/null; pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null; true ) &
  local wd=$!
  # STAB-01: record the watchdog subshell's inner sleep PID while the
  # subshell is alive — after `kill $wd` the sleep re-parents to launchd and
  # `pkill -P` sees nothing (worst case left a ${WATCHDOG_S}s orphan per
  # run). Canonical held-PID reaping per the stabilization plan.
  local wd_sleep=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    wd_sleep="$(pgrep -P "$wd" -x sleep 2>/dev/null | head -1 || true)"
    if [ -n "$wd_sleep" ]; then break; fi
    sleep 0.05
  done
  local maxrss=0 rss
  while kill -0 "$pid" 2>/dev/null; do
    rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    if [ -n "$rss" ] && [ "$rss" -gt "$maxrss" ] 2>/dev/null; then maxrss="$rss"; fi
    sleep 0.5
  done
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true
  if [ -n "$wd_sleep" ]; then
    kill "$wd_sleep" 2>/dev/null || true
  fi
  wait "$wd" 2>/dev/null || true
  # STAB-01 evidence: the recorded sleep must be gone after reaping.
  if [ -n "$wd_sleep" ] && kill -0 "$wd_sleep" 2>/dev/null; then
    echo "[soak] run $idx FAIL: watchdog sleep orphaned (pid $wd_sleep)"
    return 1
  fi
  local end
  end=$(python3 -c 'import time; print(time.time())')

  # Thermal between runs — the soak's sustained-load context (§1.4).
  echo "[soak] run $idx thermal: $(pmset -g therm | tail -1 | cut -c1-70)"
  echo "$maxrss" > "$WORK/run$idx.rss"
  python3 -c "print(round($end - $start, 1))" > "$WORK/run$idx.wall"
  [ -s "$out" ] || { echo "[soak] run $idx: NO EXPORT"; return 1; }
  grep -q "UITEST_DONE" "$result" 2>/dev/null || { echo "[soak] run $idx: harness incomplete"; return 1; }
  echo "[soak] run $idx: wall=$(cat "$WORK/run$idx.wall")s rss=$((maxrss / 1024))MB"
}

# Frame hashes at 9 evenly spaced interior timestamps (determinism probe).
hash_sample() { # $1 = mp4 → prints "<t>:<hash>" lines
  local t
  for t in 50 300 550 800 1050 1300 1550 1750 1790; do
    printf '%s:' "$t"
    ffmpeg -v error -ss "$t" -i "$1" -frames:v 1 -f framehash -hash md5 - 2>/dev/null | tail -1 | awk '{print $NF}'
  done
}

FAIL=0
declare -a PEAKS
for i in $(seq 1 "$RUNS"); do
  run_export "$i" || FAIL=1
done

echo "[soak] metrics:"
for i in $(seq 1 "$RUNS"); do
  av_start=$(ffprobe -v error -select_streams a -show_entries stream=start_time -of csv=p=0 "$WORK/run$i.mp4")
  v_start=$(ffprobe -v error -select_streams v -show_entries stream=start_time -of csv=p=0 "$WORK/run$i.mp4")
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/run$i.mp4")
  echo "  run$i: dur=${dur}s av_start_delta=$(python3 -c "print(round($av_start - $v_start, 6))") rss=$(( $(cat "$WORK/run$i.rss") / 1024 ))MB wall=$(cat "$WORK/run$i.wall")s"
  PEAKS+=("$(cat "$WORK/run$i.rss")")
done

# Gate 2: RSS growth across runs (first → max of the rest).
first="${PEAKS[0]}"
worst="$first"
for p in "${PEAKS[@]:1}"; do [ "$p" -gt "$worst" ] && worst="$p"; done
growth=$(python3 -c "print(round(100.0 * ($worst - $first) / max($first, 1), 1))")
echo "[soak] rss growth first→worst: ${growth}% (gate <= 15%)"
python3 -c "import sys; sys.exit(0 if $growth <= 15.0 else 1)" || FAIL=1

# Gate 3: duration within one frame of 1800s (30fps = 0.0333s), A/V start within one frame.
for i in $(seq 1 "$RUNS"); do
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/run$i.mp4")
  python3 -c "import sys; sys.exit(0 if abs($dur - 1800.0) <= 0.034 else 1)" \
    || { echo "[soak] run $i duration drift: $dur"; FAIL=1; }
  av_start=$(ffprobe -v error -select_streams a -show_entries stream=start_time -of csv=p=0 "$WORK/run$i.mp4")
  v_start=$(ffprobe -v error -select_streams v -show_entries stream=start_time -of csv=p=0 "$WORK/run$i.mp4")
  python3 -c "import sys; sys.exit(0 if abs($av_start - $v_start) <= 0.034 else 1)" \
    || { echo "[soak] run $i A/V start delta: $av_start vs $v_start"; FAIL=1; }
done

# Gate 4: cross-run determinism — identical frame hashes at the sample points.
if [ "$RUNS" -ge 2 ]; then
  hash_sample "$WORK/run1.mp4" > "$WORK/run1.hashes"
  hash_sample "$WORK/run2.mp4" > "$WORK/run2.hashes"
  if diff -q "$WORK/run1.hashes" "$WORK/run2.hashes" >/dev/null; then
    echo "[soak] determinism: 9/9 sampled frame hashes identical across runs"
  else
    echo "[soak] determinism FAIL — sampled frames differ:"
    diff "$WORK/run1.hashes" "$WORK/run2.hashes" | head -6
    FAIL=1
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  echo "LONGFORM SOAK GATE: PASS"
else
  echo "LONGFORM SOAK GATE: FAIL" >&2
  exit 1
fi
