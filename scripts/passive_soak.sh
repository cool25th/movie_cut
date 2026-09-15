#!/usr/bin/env bash
# QAUTO-06 passive soak v1 (7th-cycle feedback spec): read-only observation of
# the latest run manifest. No build, no fixture generation — it consumes
# nothing, so it may run under disk BLOCK (8th-cycle, first application).
# Checks: manifest existence · JSON parse · schema completeness · control
# legs · measurement_authorized · freshness (preregistered 48h constant) ·
# latest disk-guard verdict · orphan WORK dirs in /tmp.
# Output: append-only .build-check/history/soak/soak-<epoch>.json — separate
# from runs/ (execution evidence) so observation never mutates provenance.
# Verdict precedence: INVALID_PROVENANCE > STALE > DEGRADED > HEALTHY.
#
# Usage: passive_soak.sh [runs_dir] [history_dir] [soak_dir]
#        (arguments exist ONLY so the STALE/INVALID paths can be exercised
#         against synthetic dirs; defaults are the standard locations)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNS_DIR="${1:-$ROOT/.build-check/history/runs}"
HISTORY_DIR="${2:-$ROOT/.build-check/history}"
SOAK_DIR="${3:-$ROOT/.build-check/history/soak}"
mkdir -p "$SOAK_DIR"

RUNS_DIR="$RUNS_DIR" HISTORY_DIR="$HISTORY_DIR" SOAK_DIR="$SOAK_DIR" ROOT="$ROOT" \
python3 - <<'PY'
import datetime, glob, json, os

FRESHNESS_HOURS = 48  # preregistered constant — no env override

now = datetime.datetime.now()
runs_dir = os.environ["RUNS_DIR"]

def latest(pattern, directory):
    files = sorted(glob.glob(os.path.join(directory, pattern)), key=os.path.getmtime)
    return files[-1] if files else ""

checks = {}

guard_file = latest("disk-*.json", os.environ["HISTORY_DIR"])
try:
    guard = json.load(open(guard_file)).get("guard", "unknown") if guard_file else "no-record"
except Exception:
    guard = "unknown"
checks["disk_guard"] = guard

orphan = sorted(glob.glob("/tmp/moviecut-ca18*") + glob.glob("/tmp/moviecut-ca21*"))
checks["orphan_work_dirs"] = len(orphan)

mf = latest("*.json", runs_dir)
checks["latest_manifest"] = os.path.relpath(mf, os.environ["ROOT"]) if mf else None

parsed = None
if mf:
    try:
        parsed = json.load(open(mf))
        checks["json_parseable"] = True
    except Exception:
        checks["json_parseable"] = False
else:
    checks["json_parseable"] = None

REQUIRED = ["run_id", "started_at", "assembled_at", "app_commit", "driver_sha256",
            "toolchain", "control_legs", "measurement", "fixtures_sha256"]
schema_ok = bool(parsed) and all(k in parsed for k in REQUIRED)
checks["schema_complete"] = schema_ok

legs = (parsed or {}).get("control_legs", [])
checks["control_legs"] = len(legs)
checks["control_legs_authorized"] = bool(legs) and all(
    l.get("measurement_authorized") is True for l in legs)
m = (parsed or {}).get("measurement")
checks["measurement_authorized"] = bool(m and m.get("measurement_authorized") is True)

fresh = None
if parsed and parsed.get("assembled_at"):
    try:
        assembled = datetime.datetime.fromisoformat(parsed["assembled_at"])
        age_h = (now - assembled).total_seconds() / 3600
        fresh = age_h <= FRESHNESS_HOURS
        checks["manifest_age_hours"] = round(age_h, 2)
    except Exception:
        fresh = False
checks["fresh_within_48h"] = fresh

structural_invalid = (
    mf is None
    or checks["json_parseable"] is False
    or not schema_ok
    or not checks["measurement_authorized"]
)
# 8th-cycle feedback: reasons are multi-preserved — a STALE verdict keeps
# DISK_GUARD_BLOCK etc. so simultaneous conditions stay visible.
reasons = []
if guard in ("BLOCK", "STOP"):
    reasons.append(f"DISK_GUARD_{guard}")
if checks["orphan_work_dirs"] > 0:
    reasons.append("ORPHAN_WORK")
if not checks["control_legs_authorized"]:
    reasons.append("NO_AUTHORIZED_CONTROL_LEGS")
if fresh is False:
    reasons.append("FRESHNESS_EXCEEDED")
if structural_invalid:
    reasons.append("PROVENANCE_UNTRUSTWORTHY")

if structural_invalid:
    verdict = "INVALID_PROVENANCE"
elif fresh is False:
    verdict = "STALE"          # freshness is an independent condition
elif reasons:
    verdict = "DEGRADED"
else:
    verdict = "HEALTHY"

record = {
    "ts": now.isoformat(timespec="seconds"),
    "kind": "passive_soak_v1",
    "verdict": verdict,
    "reasons": reasons,
    "checks": checks,
}
out = os.path.join(os.environ["SOAK_DIR"], f"soak-{int(now.timestamp())}.json")
with open(out, "w") as f:
    json.dump(record, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"passive soak: {verdict} ({checks['manifest_age_hours'] if 'manifest_age_hours' in checks else '-'}h old manifest, "
      f"guard {guard}, orphans {checks['orphan_work_dirs']}) — {os.path.relpath(out, os.environ['ROOT'])}")
PY
