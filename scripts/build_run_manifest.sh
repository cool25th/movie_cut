#!/usr/bin/env bash
# QAUTO-01 hardening (6th/7th/10th-cycle): run-level immutable provenance
# manifest, schema v2.
#
# v2 (10th-cycle feedback):
#   - ERROR_PROVENANCE_COLLISION: if the manifest already exists, the new
#     payload's canonical hash is compared with the stored one. Identical →
#     idempotent re-invocation (skip). Different → collision, exit 1. This
#     catches both accidental overwrite and run_id reuse with other content.
#   - New fields: manifest_schema_version, finished_at, duration_ms,
#     driver_exit_code (from the driver's EXIT trap $?), worktree_dirty,
#     record_count, manifest_sha256 (self-hash over the canonical JSON of
#     the payload WITHOUT the manifest_sha256 field).
#
# Usage:
#   build_run_manifest.sh <run_id> <measurement> [work_dir] [started_at] [driver_path] [driver_exit_code]
set -euo pipefail
RUN_ID="${1:?run id required}"
MEASUREMENT="${2:?measurement id required}"
WORK_DIR="${3:-}"
START_TS="${4:-}"
DRIVER="${5:-}"
DRIVER_RC="${6:-unknown}"
[ -n "$RUN_ID" ] || exit 0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HISTORY="$ROOT/.build-check/history"
OUT="$HISTORY/runs/${MEASUREMENT}-${RUN_ID}.json"
mkdir -p "$HISTORY/runs"

APP_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [ -n "$DRIVER" ]; then
  DRIVER_SHA="$(shasum -a 256 "$DRIVER" 2>/dev/null | awk '{print $1}' || echo unknown)"
else
  DRIVER_SHA="unknown"
fi
SWIFT_VER="$(swift --version 2>/dev/null | head -1 || echo unknown)"
FFMPEG_VER="$(ffmpeg -version 2>/dev/null | head -1 || echo unknown)"
DIRTY_COUNT="$(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

RUN_ID="$RUN_ID" MEASUREMENT="$MEASUREMENT" RECORDS_DIR="$HISTORY" WORK_DIR="$WORK_DIR" \
START_TS="$START_TS" APP_COMMIT="$APP_COMMIT" DRIVER_SHA="$DRIVER_SHA" \
SWIFT_VER="$SWIFT_VER" FFMPEG_VER="$FFMPEG_VER" DIRTY_COUNT="$DIRTY_COUNT" \
DRIVER_RC="$DRIVER_RC" OUT_PATH="$OUT" \
python3 - <<'PY'
import datetime, glob, hashlib, json, os

records_dir = os.environ["RECORDS_DIR"]
run_id = os.environ["RUN_ID"]
control_legs, measurement, record_count = [], None, 0
for name in sorted(os.listdir(records_dir)):
    if not (name.startswith("qauto-") and name.endswith(".json")):
        continue
    try:
        rec = json.load(open(os.path.join(records_dir, name)))
    except Exception:
        continue
    if rec.get("run_id") != run_id:
        continue
    record_count += 1
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

now = datetime.datetime.now()
finished_at = now.isoformat(timespec="seconds")
duration_ms = ""
if os.environ.get("START_TS"):
    try:
        start = datetime.datetime.fromisoformat(os.environ["START_TS"])
        duration_ms = str(int((now - start).total_seconds() * 1000))
    except Exception:
        duration_ms = ""

# 26th-cycle feedback: the manifest must reference the EXACT audit artifact
# of this run — never "latest in the directory" (parallel/stale/clock-skew
# runs would pick the wrong evidence). PROVENANCE_AUDIT env carries an
# explicit path; without it no audit is attached (rather than guessing).
audit_summary = None
_audit_path = os.environ.get("PROVENANCE_AUDIT") or ""
audits = [_audit_path] if (_audit_path and os.path.isfile(_audit_path)) else []
if audits:
    try:
        a = json.load(open(audits[-1]))
        audit_summary = {
            "provenance_audit_id": a.get("audit_id"),
            "audit_sha256": a.get("audit_sha256"),
            "audit_record": os.path.basename(audits[-1]),
            "audit_ts": a.get("ts"),
            "overall_continuity_status": a.get("overall_continuity_status"),
            "totals": a.get("totals"),
        }
    except Exception:
        audit_summary = None

payload = {
    "manifest_schema_version": 2,
    "run_id": run_id,
    "measurement": os.environ["MEASUREMENT"],
    "started_at": os.environ.get("START_TS", ""),
    "finished_at": finished_at,
    "duration_ms": duration_ms,
    "app_commit": os.environ["APP_COMMIT"],
    "worktree_dirty": os.environ["DIRTY_COUNT"] != "0",
    "worktree_dirty_entries": int(os.environ["DIRTY_COUNT"] or 0),
    "driver_sha256": os.environ["DRIVER_SHA"],
    "driver_exit_code": os.environ["DRIVER_RC"],
    "toolchain": {"swift": os.environ["SWIFT_VER"], "ffmpeg": os.environ["FFMPEG_VER"]},
    "control_legs": control_legs,
    "measurement": measurement,
    "measurement_authorized": (measurement or {}).get("measurement_authorized"),
    "record_count": record_count,
    "fixture_count": len(fixtures),
    "fixtures_sha256": fixtures,
}
if audit_summary is not None:
    payload["provenance_audit"] = audit_summary
# Collision comparison covers CONTENT only: the volatile time-of-assembly
# fields (finished_at/duration_ms) would make every re-invocation differ and
# turn the idempotent-re-invocation case into a false collision (found by
# the 10th-cycle verification run).
content = {k: v for k, v in payload.items()
           if k not in ("manifest_sha256", "finished_at", "duration_ms")}
payload["manifest_sha256"] = hashlib.sha256(json.dumps(
    content, sort_keys=True, ensure_ascii=False,
    separators=(",", ":")).encode("utf-8")).hexdigest()

out = os.environ["OUT_PATH"]
if os.path.exists(out):
    try:
        existing = json.load(open(out))
        existing_content = {k: v for k, v in existing.items()
                            if k not in ("manifest_sha256", "finished_at", "duration_ms")}
        existing_hash = hashlib.sha256(json.dumps(
            existing_content, sort_keys=True, ensure_ascii=False,
            separators=(",", ":")).encode("utf-8")).hexdigest()
        if existing_hash == payload["manifest_sha256"]:
            print(f"run manifest immutable — identical re-invocation, skip: {out}")
            raise SystemExit(0)
        print(f"ERROR_PROVENANCE_COLLISION — existing content hash {existing_hash[:16]}… "
              f"differs from re-invocation payload {payload['manifest_sha256'][:16]}… : {out}")
        raise SystemExit(1)
    except json.JSONDecodeError:
        print(f"ERROR_PROVENANCE_COLLISION — existing manifest is not valid JSON: {out}")
        raise SystemExit(1)

with open(out, "w") as f:
    json.dump(payload, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"run manifest: {out} (schema v2, control legs {len(control_legs)}, "
      f"records {record_count}, fixtures {len(fixtures)})")
PY
