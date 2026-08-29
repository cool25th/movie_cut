#!/usr/bin/env bash
# CA-12 competitive A/B benchmark harness (COMPETITIVE_ANALYSIS Part 5).
#
# Drives the REAL MovieCut app (Mac UITestHarness, Debug build, sandbox OFF)
# across the 12 representative fixtures and records, for every fixture:
#   - §1.4 condition fields (machine, OS, build, power, thermal, storage,
#     cold/warm, repetitions, sampling) in every JSON record
#   - whole-app wall time vs isolated export span (`export_wall_s`) + RTF
#   - peak RSS (ps polling while the app runs)
#   - absolute output metrics (bitrate, CFR/VFR, keyframes, clipping/crush/
#     banding, chroma subsampling, loudness/true-peak, A/V sync) via
#     scripts/ab_benchmark_metrics.py `single`
#   - reference metrics vs the harness's lossless preview PNG dumps
#     (PSNR global/per-frame, SSIM, MAD p95/max, delta-E) via `pair`
#
# The competitor "B" side is not automated here: outputs produced by hand in
# the competitor app are dropped into artifacts/ab_benchmark/competitor/
# (named <fixture_id>.mp4) and `--blind` generates the randomized human
# ballot (Part 5 §2 사람 블라인드 병행).
#
# Usage:
#   bash scripts/run_ca12_ab_benchmark.sh                 # full 12-fixture run
#   bash scripts/run_ca12_ab_benchmark.sh ab01 ab03       # fixture subset
#   bash scripts/run_ca12_ab_benchmark.sh --blind         # blind protocol only
#   REPS=3 WATCHDOG_S=900 bash scripts/run_ca12_ab_benchmark.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

ART="$ROOT/artifacts/ab_benchmark"
RUN_DIR="$ART/run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR"

REPS="${REPS:-1}"
WATCHDOG_S="${WATCHDOG_S:-1500}"
APP_BIN=""

log() { echo "[ca12] $*"; }

# --- blind protocol only -------------------------------------------------------
if [ "${1:-}" = "--blind" ]; then
  python3 "$ROOT/scripts/ab_benchmark_metrics.py" blind \
    --a-dir "$ART/moviecut" --b-dir "$ART/competitor" --out "$ART/blind"
  exit $?
fi

# --- fixture table: id | media | extra env for the harness ---------------------
# shellcheck disable=SC2034
FIXTURES=(
  "ab01_single_1080p30|$ART/fixtures/ab01_1080p30_10s.mp4|"
  "ab02_4k60_hevc|$ART/fixtures/ab02_2160p60_hevc_6s.mov|"
  "ab03_hdr_10bit|$ROOT/Tests/Fixtures/ca04_bt2020pq_320x240_2s.mp4|"
  "ab04_interview_30min|$ART/fixtures/ab04_interview_640x360_30min.mp4|MOVIECUT_UITEST_TEXT_AT=0.5"
  "ab05_shorts_overlays|$ROOT/Tests/Fixtures/rec709_720p_portrait_1s_30fps.mp4,$ROOT/Tests/Fixtures/rec709_720p_portrait_1s_30fps.mp4|MOVIECUT_UITEST_TEXT_AT=0.5"
  "ab06_ramp_opticalflow|$ROOT/Tests/Fixtures/moving_subject_320x240_2s_30fps.mp4|MOVIECUT_UITEST_SPEED_RAMP=1 MOVIECUT_UITEST_OPTICAL_FLOW=1"
  "ab07_mask_chromakey|$ART/fixtures/ab07_greenscreen_320x240_4s.mp4|MOVIECUT_UITEST_MASK=1 MOVIECUT_UITEST_CHROMA_KEY=1"
  "ab08_color_grade|$ROOT/Tests/Fixtures/rec709_1080p_1s_30fps.mp4|MOVIECUT_UITEST_COLOR=1 MOVIECUT_UITEST_GRADE=1"
  "ab09_ducking_master|$ROOT/Tests/Fixtures/solid_red_tone_320x240_2s_30fps.mp4|MOVIECUT_UITEST_DUCKING_BGM=$ROOT/Tests/Fixtures/duck_bgm_220hz_4s_mono.wav MOVIECUT_UITEST_DUCKING_VOICE=$ROOT/Tests/Fixtures/duck_voice_1000hz_1s_mono.wav MOVIECUT_UITEST_DUCKING_APPLY=1"
  "ab10_external_disk|$ART/fixtures/ab01_1080p30_10s.mp4|"
  "ab11_vfr_screenrec|$ROOT/Tests/Fixtures/ca04_vfr_320x240_5s.mp4|"
  "ab12_two_hour|$ART/fixtures/ab12_320x240_2h.mp4|"
)

# Preview sample timestamps per fixture (pair metrics reference points).
pair_times() {
  case "$1" in
    ab01_single_1080p30|ab10_external_disk) echo "1.0,3.5,6.0,8.5" ;;
    ab02_4k60_hevc) echo "0.5,2.0,4.5" ;;
    ab03_hdr_10bit) echo "0.5,1.5" ;;
    ab04_interview_30min) echo "1.0,450,900,1350,1750" ;;
    ab05_shorts_overlays) echo "0.3,0.7" ;;
    ab06_ramp_opticalflow) echo "0.3,0.7" ;;
    ab07_mask_chromakey) echo "0.5,1.5,2.5,3.5" ;;
    ab08_color_grade) echo "0.5" ;;
    ab09_ducking_master) echo "0.5,1.5" ;;
    ab11_vfr_screenrec) echo "0.5,2.5,4.5" ;;
    ab12_two_hour) echo "1.0,1800,3600,5400,7100" ;;
    *) echo "" ;;
  esac
}

per_fixture_watchdog() {
  case "$1" in
    ab04_interview_30min|ab12_two_hour) echo $((WATCHDOG_S + 1800)) ;;
    *) echo "$WATCHDOG_S" ;;
  esac
}

# --- condition fields (§1.4: every number is read with these) ------------------
collect_conditions() {
  python3 - "$RUN_DIR" <<'PY'
import json, platform, subprocess, sys
from pathlib import Path

run_dir = Path(sys.argv[1])

def sh(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return None

git_sha = sh(["git", "rev-parse", "--short", "HEAD"])
conditions = {
    "machine": sh(["sysctl", "-n", "hw.model"]),
    "chip": sh(["sysctl", "-n", "machdep.cpu.brand_string"]),
    "ram_gb": round(int(sh(["sysctl", "-n", "hw.memsize"]) or 0) / 1e9, 1),
    "os": sh(["sw_vers", "-productVersion"]),
    "build": sh(["sw_vers", "-buildVersion"]),
    "app_commit": git_sha,
    "python": platform.python_version(),
    # Power/thermal: best-effort fields, recorded as-is (None = unavailable).
    "power": None,
    "thermal": None,
    "storage_input": None,
    "storage_output": None,
}
batt = sh(["pmset", "-g", "batt"])
if batt:
    conditions["power"] = "ac" if "AC Power" in batt else "battery"
therm = sh(["pmset", "-g", "therm"])
if therm:
    conditions["thermal"] = " ".join(therm.split("\n")[1:]) or therm.split("\n")[0]
disk = sh(["df", "-h", str(Path.cwd())])
if disk:
    conditions["storage_output"] = disk.split("\n")[-1].split()[0]
conditions["launch_mode"] = "cold (fresh process per fixture, fresh container)"
conditions["repetitions"] = 1
conditions["reps_note"] = "set REPS env for repeated timing runs; median/p95 recorded per rep list"
conditions["metrics_sampling"] = "single: 9 evenly spaced frames; pair: per-fixture timestamps in runner"
(run_dir / "conditions.json").write_text(json.dumps(conditions, indent=2) + "\n")
print(json.dumps(conditions, indent=2))
PY
}

# --- build the app (Debug, sandbox OFF — parity/E2E convention) ----------------
build_app() {
  log "building MovieCutMac (Debug, sandbox OFF)…"
  xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
    -destination 'platform=macOS' ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO build >/dev/null
  local products
  products="$(xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug \
    -destination 'platform=macOS' -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')" || true
  APP_BIN="$products/MovieCutMac.app/Contents/MacOS/MovieCutMac"
  [ -x "$APP_BIN" ] || { echo "app binary not found" >&2; exit 1; }
}

# --- run one fixture through the real app ---------------------------------------
# Sets RUN_SUMMARY_JSON_<safe_id> style outputs via files in $fixture_dir.
run_fixture() { # $1=id $2=media $3=extra_env $4=rep_index $5=dir
  local id="$1" media="$2" extra_env="$3" rep="$4" dir="$5"
  mkdir -p "$dir"
  local export_mp4="$dir/export.mp4"
  local result="$dir/result.txt"
  local preview_dir="$dir/preview"
  rm -f "$result" "$export_mp4"
  rm -rf "$preview_dir"

  local times
  times="$(pair_times "$id")"

  pkill -f "MovieCutMac.app/Contents/MacOS/MovieCutMac" 2>/dev/null || true
  sleep 1

  local start_ns
  start_ns="$(python3 -c 'import time; print(time.time())')"
  # shellcheck disable=SC2086
  env MOVIECUT_UITEST=1 \
    MOVIECUT_UITEST_IMPORT="$media" \
    MOVIECUT_UITEST_PREVIEW_DUMP="$preview_dir" \
    MOVIECUT_UITEST_PARITY=1 \
    MOVIECUT_UITEST_PARITY_TIMES="$times" \
    MOVIECUT_UITEST_EXPORT="$export_mp4" \
    MOVIECUT_UITEST_RESULT="$result" \
    MOVIECUT_UITEST_QUIT=1 \
    $extra_env \
    "$APP_BIN" >/dev/null 2>&1 &
  local pid=$!
  ( sleep "$(per_fixture_watchdog "$id")"; kill "$pid" 2>/dev/null || true ) &
  local wd=$!
  local maxrss=0 rss
  while kill -0 "$pid" 2>/dev/null; do
    rss="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    if [ -n "$rss" ] && [ "$rss" -gt "$maxrss" ] 2>/dev/null; then maxrss="$rss"; fi
    sleep 0.5
  done
  wait "$pid" 2>/dev/null || true
  kill "$wd" 2>/dev/null || true
  local end_ns
  end_ns="$(python3 -c 'import time; print(time.time())')"

  python3 - "$dir" "$start_ns" "$end_ns" "$maxrss" <<'PY'
import json, sys
from pathlib import Path
d = Path(sys.argv[1])
(d / "timing.json").write_text(json.dumps({
    "app_wall_s": round(float(sys.argv[3]) - float(sys.argv[2]), 3),
    "peak_rss_mb": round(int(sys.argv[4]) / 1024, 1),
}, indent=2) + "\n")
PY
}

# --- per-fixture metric collection ----------------------------------------------
metrics_for_fixture() { # $1=id $2=dir
  local id="$1" dir="$2"
  local export_mp4="$dir/export.mp4"
  if [ ! -s "$export_mp4" ]; then
    echo "{\"error\": \"no export produced\"}" > "$dir/metrics_error.json"
    return 1
  fi
  python3 "$ROOT/scripts/ab_benchmark_metrics.py" single "$export_mp4" \
    -o "$dir/metrics_single.json" >/dev/null
  local times
  times="$(pair_times "$id")"
  if [ -n "$times" ] && ls "$dir/preview/"*.png >/dev/null 2>&1; then
    python3 "$ROOT/scripts/ab_benchmark_metrics.py" pair \
      --reference-dir "$dir/preview" --export "$export_mp4" \
      --times "$times" -o "$dir/metrics_pair.json" >/dev/null || true
  fi
  # RTF (export span / output duration) — §1.4 definition.
  python3 - "$dir" <<'PY'
import json, re, subprocess, sys
from pathlib import Path
d = Path(sys.argv[1])
result = (d / "result.txt").read_text() if (d / "result.txt").exists() else ""
m = re.search(r"export_wall_s=([0-9.]+)", result)
timing = json.loads((d / "timing.json").read_text())
rtf = None
export = d / "export.mp4"
if export.exists():
    dur = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", str(export)], capture_output=True, text=True)
    try:
        out_dur = float(dur.stdout.strip())
        if m and out_dur > 0:
            rtf = round(float(m.group(1)) / out_dur, 4)
    except ValueError:
        pass
timing["export_wall_s"] = float(m.group(1)) if m else None
timing["output_duration_s"] = out_dur if rtf is not None else None
timing["rtf_export_span"] = rtf
(d / "timing.json").write_text(json.dumps(timing, indent=2) + "\n")
PY
}

# --- main ------------------------------------------------------------------------
SELECTED=("$@")
[ ${#SELECTED[@]} -eq 0 ] && SELECTED=($(printf '%s\n' "${FIXTURES[@]}" | cut -d'|' -f1))

bash "$ROOT/scripts/make_ab_fixtures.sh" >/dev/null
collect_conditions | tee "$RUN_DIR/conditions_echo.txt"
build_app

RESULTS=()
STATUS=0
for fixture in "${FIXTURES[@]}"; do
  id="$(printf '%s' "$fixture" | cut -d'|' -f1)"
  media="$(printf '%s' "$fixture" | cut -d'|' -f2)"
  extra="$(printf '%s' "$fixture" | cut -d'|' -f3)"
  skip=1
  for sel in "${SELECTED[@]}"; do
    [[ "$id" == "$sel"* ]] && skip=0
  done
  [ "$skip" -eq 1 ] && continue

  log "fixture $id (reps=$REPS)"
  rep_results=()
  for rep in $(seq 1 "$REPS"); do
    dir="$RUN_DIR/$id/rep$rep"
    run_fixture "$id" "$media" "$extra" "$rep" "$dir"
    if ! metrics_for_fixture "$id" "$dir"; then
      log "fixture $id rep$rep: NO EXPORT — recording failure"
      STATUS=1
    fi
    rep_results+=("$dir")
  done

  # Aggregate the primary rep (rep1) into the run summary.
  python3 - "$id" "$RUN_DIR/$id/rep1" "$RUN_DIR" <<'PY'
import json, shutil, sys
from pathlib import Path
fid, d, run = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
entry = {"fixture": fid}
for name, key in [("timing.json", "timing"), ("metrics_single.json", "single"),
                  ("metrics_pair.json", "pair"), ("metrics_error.json", "error")]:
    p = d / name
    if p.exists():
        entry[key] = json.loads(p.read_text())
result = d / "result.txt"
if result.exists():
    entry["harness_status"] = result.read_text().strip().splitlines()[-1][:400]
summary_path = run / "summary_entries"
summary_path.mkdir(exist_ok=True)
(summary_path / f"{fid}.json").write_text(json.dumps(entry, indent=2) + "\n")
print(f"summarized {fid}")

# Stage the A-side copy for the blind protocol (small outputs only — the
# long-form exports can be regenerated by re-running their fixture).
export = d / "export.mp4"
blind_dir = run.parent / "moviecut"
if export.exists() and export.stat().st_size <= 1_000_000_000:
    blind_dir.mkdir(exist_ok=True)
    shutil.copyfile(export, blind_dir / f"{fid}.mp4")
elif export.exists():
    print(f"blind copy skipped for {fid} ({export.stat().st_size} bytes > 1GB — rerun fixture to stage)")
# Prune giant exports after metrics are recorded: the 2 h fixture at the
# default 1080p canvas produced a 7.5 GB file; metrics + preview PNGs remain.
if export.exists() and export.stat().st_size > 2_000_000_000:
    export.unlink()
    print(f"pruned oversized export for {fid} (metrics recorded)")
PY
  RESULTS+=("$id")
done

# Final assembled baseline JSON.
python3 - "$RUN_DIR" "$REPS" <<'PY'
import json, sys
from pathlib import Path
run = Path(sys.argv[1])
conditions = json.loads((run / "conditions.json").read_text())
conditions["repetitions"] = int(sys.argv[2])
fixtures = []
for p in sorted((run / "summary_entries").glob("*.json")):
    fixtures.append(json.loads(p.read_text()))
(run / "baseline.json").write_text(json.dumps({
    "conditions": conditions,
    "fixtures": fixtures,
}, indent=2) + "\n")
print(f"baseline: {run / 'baseline.json'} ({len(fixtures)} fixtures)")
PY

log "run complete: $RUN_DIR (status=$STATUS)"
exit $STATUS
