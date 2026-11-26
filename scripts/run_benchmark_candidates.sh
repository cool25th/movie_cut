#!/usr/bin/env bash
# Benchmark expansion (OpenCut comparison point ④): a CANDIDATE REGISTRY
# contract + a reproducible ffmpeg reference axis for the CA-12 A/B harness.
#
# The first CA-12 baseline discarded MovieCut export outputs, and competitor
# product outputs (CapCut / OpenCut / Palmier) are acquired manually — so the
# expansion that unblocks the blind/pair comparison NOW is:
#
#   1. `--register <id> --name <label> --version <v>`
#        Records a candidate in qa/baselines/benchmark-candidates.json.
#        Outputs slot in at artifacts/ab_benchmark/candidates/<id>/
#        (<fixture_id>.mp4 per fixture) — zero harness changes later.
#
#   2. `--generate-ffmpeg-reference`
#        Produces the reference axis: matched-parameter transcodes of the
#        pinned 12 fixtures (scale 1920x1080 — the app's default canvas,
#        h264 yuv420p CRF 23 preset veryfast, fps passthrough, aac 48k when
#        audio is present) with per-fixture RTF. This is an industry-standard
#        pipeline line, NOT a competitor product; it gives MovieCut's numbers
#        a stable third-party reference today.
#
#   3. `--measure <id>`
#        Measures a candidate's outputs against the SOURCE fixtures with the
#        same pair-metric machinery the baseline used (frames sampled at the
#        runner's timestamps), appending per-fixture results to the registry.
#        Outputs are hashed; large transcodes are deleted after measuring
#        (regeneration is deterministic from the pinned parameters).
#
# Usage:
#   bash scripts/run_benchmark_candidates.sh --register ffmpeg-reference \
#     --name "ffmpeg" --version "$(ffmpeg -version | head -1)"
#   bash scripts/run_benchmark_candidates.sh --generate-ffmpeg-reference
#   bash scripts/run_benchmark_candidates.sh --measure ffmpeg-reference
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
command -v ffprobe >/dev/null || { echo "ffprobe required" >&2; exit 2; }
command -v ffmpeg  >/dev/null || { echo "ffmpeg required" >&2;  exit 2; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }

FIXDIR="$ROOT/artifacts/ab_benchmark/fixtures"
MANIFEST="$FIXDIR/manifest.json"
REGISTRY="$ROOT/qa/baselines/benchmark-candidates.json"
CANDROOT="$ROOT/artifacts/ab_benchmark/candidates"
[ -s "$MANIFEST" ] || { echo "fixture manifest missing; run make_ab_fixtures.sh" >&2; exit 2; }

MODE=""
CAND_ID=""
CAND_NAME=""
CAND_VERSION=""
while [ $# -ge 1 ]; do
  case "$1" in
    --register) MODE="register"; CAND_ID="${2:?id required}"; shift 2 ;;
    --generate-ffmpeg-reference) MODE="gen"; shift 1 ;;
    --measure) MODE="measure"; CAND_ID="${2:?id required}"; shift 2 ;;
    --name) CAND_NAME="$2"; shift 2 ;;
    --version) CAND_VERSION="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { grep -m1 "Usage:" "$0" >&2; exit 2; }

registry_read() {
  [ -s "$REGISTRY" ] || echo '{"schema_version":1,"candidates":{}}' | tee "$REGISTRY" >/dev/null
}
registry_write_python() {
  python3 - "$@" <<'EOF'
import json, sys, datetime
path = "qa/baselines/benchmark-candidates.json"
reg = json.load(open(path))
action = sys.argv[1]
if action == "register":
    cid, name, version = sys.argv[2], sys.argv[3], sys.argv[4]
    reg["candidates"][cid] = {
        "name": name or cid,
        "version": version or "unknown",
        "registered_at": datetime.datetime.now().isoformat(timespec="seconds"),
        "measurements": {},
    }
elif action == "record":
    cid = sys.argv[2]
    entry = json.loads(sys.argv[3])
    reg["candidates"].setdefault(cid, {"name": cid, "version": "unknown",
                                       "registered_at": None, "measurements": {}})
    reg["candidates"][cid]["measurements"][entry["measured_at"]] = entry
json.dump(reg, open(path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
open(path, "a").write("\n")
EOF
}

case "$MODE" in
  register)
    registry_read
    registry_write_python register "$CAND_ID" "$CAND_NAME" "$CAND_VERSION"
    echo "registered candidate: $CAND_ID (outputs → $CANDROOT/$CAND_ID/)"
    ;;

  gen)
    registry_read
    OUT="$CANDROOT/ffmpeg-reference"
    mkdir -p "$OUT"
    echo "=== generating ffmpeg reference transcodes (1920x1080, h264 crf23 veryfast) ==="
    python3 - <<'EOF' > "$OUT/.gen.plan"
import json
m = json.load(open("artifacts/ab_benchmark/fixtures/manifest.json"))
for fid, info in sorted(m["fixtures"].items()):
    print(f"{fid}\t{info['path']}\t{info.get('duration_s', 0)}")
EOF
    while IFS=$'\t' read -r fid path dur; do
      src="$FIXDIR/$path"
      dst="$OUT/$fid.mp4"
      [ -s "$src" ] || { echo "  SKIP $fid — fixture missing"; continue; }
      rm -f "$dst"
      start=$(python3 -c 'import time; print(time.time())')
      ffmpeg -hide_banner -loglevel error -i "$src" \
        -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2" \
        -c:v libx264 -preset veryfast -crf 23 -pix_fmt yuv420p \
        -c:a aac -ar 48000 -ac 2 -y "$dst" </dev/null
      end=$(python3 -c 'import time; print(time.time())')
      rtf=$(python3 -c "print(round(($end-$start)/max(float('$dur'),0.001),3))")
      size=$(stat -f%z "$dst" 2>/dev/null || echo 0)
      echo "  GEN $fid rtf=$rtf size=$size"
    done < "$OUT/.gen.plan"
    echo "reference outputs: $OUT"
    ;;

  measure)
    registry_read
    CANDDIR="$CANDROOT/$CAND_ID"
    [ -d "$CANDDIR" ] || { echo "no outputs for candidate $CAND_ID" >&2; exit 2; }
    echo "=== measuring candidate $CAND_ID against source fixtures (pair machinery) ==="
    WORK="$(mktemp -d /tmp/moviecut-bench-cand.XXXXXX)"
    trap 'rm -rf "$WORK"' EXIT
    RESULTS_JSON="$WORK/entry.json"
    python3 - "$CAND_ID" "$CANDDIR" "$WORK" "$RESULTS_JSON" <<'EOF'
import json, os, subprocess, sys, hashlib, datetime, time
cand_id, cand_dir, work, out_path = sys.argv[1:5]
manifest = json.load(open("artifacts/ab_benchmark/fixtures/manifest.json"))
fixtures = {}
for fid, info in sorted(manifest["fixtures"].items()):
    out = os.path.join(cand_dir, f"{fid}.mp4")
    if not os.path.isfile(out) or os.path.getsize(out) == 0:
        print(f"  SKIP {fid} — no candidate output")
        continue
    # Reference frames from the SOURCE at the runner's 9-point sampling.
    refdir = os.path.join(work, fid, "refs")
    os.makedirs(refdir, exist_ok=True)
    dur = float(info.get("duration_s") or 0)
    if dur <= 0:
        dur = float(subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", info["path"]], capture_output=True, text=True).stdout.strip() or 0)
    times = ",".join(str(round(dur * (k + 0.5) / 9, 3)) for k in range(9))
    # Extract the 9 reference frames (one seek per timestamp, deterministic)
    # named to the pair tool's preview_t<t>.png contract.
    # Reference frames pass through the SAME scale/pad as candidate
    # generation, so the comparison happens at the delivery canvas (the
    # pair tool's parity convention).
    ref_vf = ("scale=1920:1080:force_original_aspect_ratio=decrease,"
              "pad=1920:1080:(ow-iw)/2:(oh-ih)/2")
    for t in times.split(","):
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error",
                        "-ss", t, "-i", os.path.join("artifacts/ab_benchmark/fixtures", info["path"]),
                        "-vf", ref_vf,
                        "-frames:v", "1", os.path.join(refdir, f"preview_t{float(t):.3f}.png"), "-y"],
                       capture_output=True)
    metrics_path = os.path.join(work, fid, "metrics_pair.json")
    subprocess.run(
        ["python3", "scripts/ab_benchmark_metrics.py", "pair",
         "--reference-dir", refdir, "--export", out, "--times", times,
         "-o", metrics_path], capture_output=True, text=True)
    metrics = json.load(open(metrics_path)) if os.path.isfile(metrics_path) else None
    sha = hashlib.sha256(open(out, "rb").read()).hexdigest()
    outdur = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", out], capture_output=True, text=True).stdout.strip()
    print(f"  MEASURE {fid} dur={outdur} sha256={sha[:12]} metrics={'yes' if metrics else 'FAILED'}")
    fixtures[fid] = {"duration_s": outdur, "output_sha256": sha, "metrics": metrics}
    # Disk discipline: outputs over 100 MB are deleted after measuring
    # (regeneration is deterministic from the pinned parameters).
    if os.path.getsize(out) > 100 * 1024 * 1024:
        os.remove(out)
        fixtures[fid]["output_deleted_after_measure"] = True
entry = {
    "candidate": cand_id,
    "measured_at": datetime.datetime.now().isoformat(timespec="seconds"),
    "app_commit": subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                                 capture_output=True, text=True).stdout.strip(),
    "pair_contract": "9-point sampling vs source frames, CA-12 pair machinery",
    "fixtures": fixtures,
}
json.dump(entry, open(out_path, "w"), ensure_ascii=False, indent=2)
EOF
    [ -s "$RESULTS_JSON" ] || { echo "no measurements recorded" >&2; exit 1; }
    ENTRY=$(python3 -c "import json,sys; print(json.dumps(json.load(open('$RESULTS_JSON'))))")
    registry_write_python record "$CAND_ID" "$ENTRY"
    echo "recorded → $REGISTRY"
    ;;
esac
