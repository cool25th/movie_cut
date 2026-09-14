#!/usr/bin/env bash
# QAUTO-01 CLOSED-state hardening (6th-cycle feedback): run-level immutable
# provenance manifest. Aggregates every qauto record of one run_id plus
# toolchain identity and the exact input bytes (fixture SHA256 map) into a
# WRITE-ONCE file — if the manifest already exists it is never rewritten.
# Called from the driver's EXIT trap BEFORE its scratch dir is removed, so
# fixture hashes are computed while the inputs still exist.
#
# Usage: build_run_manifest.sh <run_id> <measurement> [work_dir] [started_at] [driver_path]
set -euo pipefail
RUN_ID="${1:?run id required}"
MEASUREMENT="${2:?measurement id required}"
WORK_DIR="${3:-}"
START_TS="${4:-}"
DRIVER="${5:-}"
[ -n "$RUN_ID" ] || exit 0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HISTORY="$ROOT/.build-check/history"
OUT="$HISTORY/runs/${MEASUREMENT}-${RUN_ID}.json"
mkdir -p "$HISTORY/runs"
if [ -e "$OUT" ]; then
  echo "run manifest immutable — already present: ${OUT#"$ROOT"/}"
  exit 0
fi

APP_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$DRIVER" ]; then
  DRIVER_SHA="$(shasum -a 256 "$DRIVER" 2>/dev/null | awk '{print $1}' || echo unknown)"
else
  DRIVER_SHA="unknown"
fi
SWIFT_VER="$(swift --version 2>/dev/null | head -1 || echo unknown)"
FFMPEG_VER="$(ffmpeg -version 2>/dev/null | head -1 || echo unknown)"

RUN_ID="$RUN_ID" MEASUREMENT="$MEASUREMENT" RECORDS_DIR="$HISTORY" WORK_DIR="$WORK_DIR" \
START_TS="$START_TS" APP_COMMIT="$APP_COMMIT" DRIVER_SHA="$DRIVER_SHA" \
SWIFT_VER="$SWIFT_VER" FFMPEG_VER="$FFMPEG_VER" OUT_PATH="$OUT" \
python3 - <<'PY'
import hashlib, json, os

records_dir = os.environ["RECORDS_DIR"]
run_id = os.environ["RUN_ID"]
control_legs, measurement = [], None
for name in sorted(os.listdir(records_dir)):
    if not (name.startswith("qauto-") and name.endswith(".json")):
        continue
    try:
        rec = json.load(open(os.path.join(records_dir, name)))
    except Exception:
        continue
    if rec.get("run_id") != run_id:
        continue
    if rec.get("phase") == "control_preflight":
        control_legs.append({"verdict": rec.get("verdict"),
                             "expected": rec.get("expected_verdict"),
                             "observed_execution": rec.get("observed_execution"),
                             "measurement_authorized": rec.get("measurement_authorized")})
    elif rec.get("phase") == "measurement" and measurement is None:
        measurement = {"verdict": rec.get("verdict"),
                       "measurement_authorized": rec.get("measurement_authorized")}

fixtures = {}
work = os.environ.get("WORK_DIR", "")
if work and os.path.isdir(work):
    for base, _, files in os.walk(work):
        for fn in sorted(files):
            path = os.path.join(base, fn)
            if not os.path.isfile(path):
                continue
            h = hashlib.sha256()
            with open(path, "rb") as f:
                for chunk in iter(lambda: f.read(1 << 20), b""):
                    h.update(chunk)
            fixtures[os.path.relpath(path, work)] = h.hexdigest()

manifest = {
    "run_id": run_id,
    "measurement": os.environ["MEASUREMENT"],
    "started_at": os.environ.get("START_TS", ""),
    "assembled_at": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
    "app_commit": os.environ["APP_COMMIT"],
    "driver_sha256": os.environ["DRIVER_SHA"],
    "toolchain": {"swift": os.environ["SWIFT_VER"], "ffmpeg": os.environ["FFMPEG_VER"]},
    "control_legs": control_legs,
    "measurement": measurement,
    "measurement_authorized": (measurement or {}).get("measurement_authorized"),
    "fixture_count": len(fixtures),
    "fixtures_sha256": fixtures,
}
with open(os.environ["OUT_PATH"], "w") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"run manifest: {os.environ['OUT_PATH']} "
      f"(control legs {len(control_legs)}, fixtures {len(fixtures)})")
PY
