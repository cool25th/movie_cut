#!/usr/bin/env bash
# QAUTO-01 (evidence/harness pinning): retain a measurement verdict bound to
# app + harness identity, so a claimed PASS/FAIL is auditable afterwards.
#
# Usage (from a driver):
#   bash scripts/record_measurement_verdict.sh <name> <verdict> <measure.log> <harness-script>
#
# Structured control fields (6th-cycle schema extension, 4th-cycle feedback —
# "control PASS must be the condition that AUTHORIZES the real measurement",
# stale-record reuse must be detectable, an empty observed must never be
# stored as "") are passed via environment:
#   REC_RUN_ID            run identifier shared by every record of one driver
#                         invocation (controls + real measurement)
#   REC_PHASE             control_preflight | measurement
#   REC_EXPECTED          expected verdict/state of this leg (e.g. PASS,
#                         FAIL, ABORT_BEFORE_VERDICT)
#   REC_OBSERVED_STATE    what actually happened (e.g. ABORT_BEFORE_VERDICT)
#   REC_VERDICT_PRESENT   "true"/"false" — was a final verdict line issued
#   REC_AUTHORIZED        "true"/"false" — may the real measurement run
#
# Output: .build-check/history/qauto-<name>-<epoch>.json. An empty observed
# is NEVER stored — it is replaced by an explicit state marker.
set -euo pipefail
NAME="${1:?measurement id required}"
VERDICT="${2:?verdict required}"
LOG="${3:?measure log path required}"
HARNESS="${4:?calling harness script path required}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HISTORY="$ROOT/.build-check/history"
mkdir -p "$HISTORY"

APP_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
HARNESS_SHA="$(shasum -a 256 "$HARNESS" 2>/dev/null | awk '{print $1}' || echo unknown)"

OBSERVED_RAW="$(grep -E 'MEASURE |VERDICT: ' "$LOG" 2>/dev/null || true)"

REC_NAME="$NAME" REC_VERDICT="$VERDICT" REC_APP_COMMIT="$APP_COMMIT" \
REC_HARNESS_SHA="$HARNESS_SHA" REC_OBSERVED_RAW="$OBSERVED_RAW" \
REC_TS="$(date +%Y-%m-%dT%H:%M:%S)" \
OUT_PATH="$HISTORY/qauto-$NAME-$(date +%s).json" \
python3 - <<'PY'
import json, os
rec = {
    "ts": os.environ["REC_TS"],
    "measurement": os.environ["REC_NAME"],
    "verdict": os.environ["REC_VERDICT"],
    "app_commit": os.environ["REC_APP_COMMIT"],
    "harness_sha256": os.environ["REC_HARNESS_SHA"],
}
for env_key, field in [("REC_RUN_ID", "run_id"), ("REC_PHASE", "phase"),
                       ("REC_EXPECTED", "expected_verdict"),
                       ("REC_OBSERVED_STATE", "observed_execution"),
                       ("REC_AUTHORIZED", "measurement_authorized")]:
    value = os.environ.get(env_key, "")
    if value:
        rec[field] = value == "true" if env_key == "REC_AUTHORIZED" else value
if os.environ.get("REC_VERDICT_PRESENT", ""):
    rec["verdict_present"] = os.environ["REC_VERDICT_PRESENT"] == "true"
observed = [line.strip() for line in os.environ["REC_OBSERVED_RAW"].splitlines() if line.strip()]
if not observed:
    state = os.environ.get("REC_OBSERVED_STATE", "") or "verdict never issued"
    observed = [f"no measurement output lines (explicit state: {state})"]
rec["observed"] = observed
with open(os.environ["OUT_PATH"], "w") as f:
    json.dump(rec, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"measurement record: {os.environ['OUT_PATH']}")
PY
