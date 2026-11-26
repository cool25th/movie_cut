#!/usr/bin/env bash
# QAUTO hardening (27th-cycle): driver exit E2E — contract closure for the
# run manifest's exit-code chain. A runner that fails mid-flight must keep
# its exit code INTACT through three hops:
#   1. the driver's deliberate exit 23 (simulated mid-flight failure),
#   2. the EXIT trap that assembles the manifest (build_run_manifest.sh
#      must neither swallow nor alter the code),
#   3. the process's final exit code seen by the caller.
# The same run proves the PROVENANCE_AUDIT explicit-attach contract: the
# manifest must reference the audit record passed BY PATH — asserted via
# audit_sha256 equality — never "latest in the directory" (26th-cycle).
#
# PASS requires ALL of:
#   process rc == 23 · manifest driver_exit_code == "23" ·
#   manifest.provenance_audit.audit_sha256 == referenced audit's sha ·
#   record_count == 1 (the control record written before failing is
#   assembled into the same manifest — records and exit code one run).
#
# This is a SYNTHETIC driver (same trap pattern as the real runners, zero
# build/test work) — the real measurement runners stay unpolluted.
#
# Usage: bash scripts/run_driver_exit_e2e.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "DRIVER-EXIT-E2E FAIL: $1" >&2; exit 1; }

E2E_DIR="$(mktemp -d /tmp/moviecut-driver-exit-e2e.XXXXXX)"
E2E_START="$(date +%Y-%m-%dT%H:%M:%S)"

# --- 1) audit the REAL lock (read-only) — the explicit-attach source -------
echo "== provenance audit (real lock, read-only) =="
AUDIT_JSON="$(bash "$ROOT/scripts/check_dataset_pins.sh" --audit \
  "$ROOT/qa/baselines/dataset-lock.json")" || fail "audit run failed"
AUDIT_ID="$(printf '%s' "$AUDIT_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin)["audit_id"])')"
AUDIT_PATH="$ROOT/.build-check/history/audit/audit-$AUDIT_ID.json"
[ -f "$AUDIT_PATH" ] || fail "audit record missing: $AUDIT_PATH"

# --- 2) synthetic driver with the SAME EXIT-trap pattern -------------------
DRIVER="$E2E_DIR/synthetic_driver.sh"
cat > "$DRIVER" <<'DRIVER_EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="${MOVIECUT_REPO_ROOT:?}"
WORK="${MOVIECUT_E2E_WORK:?}"
RUN_ID="$(date +%s)-$$"
RUN_START="$(date +%Y-%m-%dT%H:%M:%S)"
SCRIPT_PATH="$0"
trap 'rc=$?; bash "$ROOT/scripts/build_run_manifest.sh" "$RUN_ID" driverexit "$WORK" "$RUN_START" "$SCRIPT_PATH" "$rc" || true; rm -rf "$WORK"' EXIT
mkdir -p "$WORK"
{
  echo "MEASURE synthetic control leg (driver exit E2E)"
  echo "VERDICT: PASS — control leg issued before the deliberate failure"
} > "$WORK/driver.log"
REC_RUN_ID="$RUN_ID" REC_PHASE="control_preflight" REC_EXPECTED="PASS" \
REC_OBSERVED_STATE="SEMANTIC_PASS" REC_AUTHORIZED="true" \
bash "$ROOT/scripts/record_measurement_verdict.sh" driverexit CONTROL_OK \
  "$WORK/driver.log" "$SCRIPT_PATH" >/dev/null
echo "DRIVER: deliberate mid-flight failure — exiting 23"
exit 23
DRIVER_EOF
chmod +x "$DRIVER"

echo "== running synthetic driver (deliberate exit 23) =="
set +e
MOVIECUT_REPO_ROOT="$ROOT" MOVIECUT_E2E_WORK="$E2E_DIR/work" \
  PROVENANCE_AUDIT="$AUDIT_PATH" \
  bash "$DRIVER" > "$E2E_DIR/driver-run.log" 2>&1
rc=$?
set -e
cat "$E2E_DIR/driver-run.log"

# --- 3) three-point match ---------------------------------------------------
[ "$rc" -eq 23 ] || fail "process rc was $rc, expected 23 (trap must not swallow the code)"
echo "POINT 1 OK — process final rc = 23"

MANIFEST_PATH="$(grep -o 'run manifest: .*' "$E2E_DIR/driver-run.log" | head -1 | sed 's/^run manifest: //; s/ (schema.*//')"
[ -n "$MANIFEST_PATH" ] && [ -f "$MANIFEST_PATH" ] || fail "manifest not found in driver output"

RESULT="$(MANIFEST="$MANIFEST_PATH" AUDIT="$AUDIT_PATH" python3 - <<'PY'
import json, os
m = json.load(open(os.environ["MANIFEST"]))
a = json.load(open(os.environ["AUDIT"]))
checks = {
    "driver_exit_code_23": m.get("driver_exit_code") == "23",
    "audit_sha_match": (m.get("provenance_audit") or {}).get("audit_sha256") == a.get("audit_sha256"),
    "audit_record_match": (m.get("provenance_audit") or {}).get("audit_record")
                          == os.path.basename(os.environ["AUDIT"]),
    "record_count_1": m.get("record_count") == 1,
    "control_leg_present": any(leg.get("verdict") == "CONTROL_OK"
                               for leg in m.get("control_legs", [])),
}
bad = [k for k, ok in checks.items() if not ok]
print("ALL_OK" if not bad else "BAD:" + ",".join(bad))
print("detail:", json.dumps({k: checks[k] for k in sorted(checks)}, ensure_ascii=False))
PY
)"
printf '%s\n' "$RESULT" | sed -n '2p'
printf '%s\n' "$RESULT" | grep -q "^ALL_OK$" || fail "manifest assertions failed ($(printf '%s' "$RESULT" | sed -n '1p'))"
echo "POINT 2 OK — manifest driver_exit_code = \"23\" (records assembled into the same manifest)"
echo "POINT 3 OK — manifest references the EXPLICIT audit by sha (audit_record $(basename "$AUDIT_PATH"))"

OUT_DIR="$ROOT/.build-check/history/driver-exit-e2e"
mkdir -p "$OUT_DIR"
E2E_START="$E2E_START" MANIFEST="$MANIFEST_PATH" AUDIT="$AUDIT_PATH" OUT_DIR="$OUT_DIR" \
python3 - <<'PY'
import datetime, json, os
rec = {
    "ts": datetime.datetime.now().isoformat(timespec="seconds"),
    "kind": "driver_exit_e2e",
    "verdict": "PASS",
    "checks": ["process_rc_23", "manifest_driver_exit_code_23",
               "provenance_audit_sha_match", "record_count_1"],
    "manifest": os.path.relpath(os.environ["MANIFEST"], os.path.dirname(os.environ["OUT_DIR"])),
    "audit": os.path.basename(os.environ["AUDIT"]),
}
out = os.path.join(os.environ["OUT_DIR"],
                   f"e2e-{rec['ts'].replace(':', '').replace('-', '')}.json")
with open(out, "w") as f:
    json.dump(rec, f, indent=2)
    f.write("\n")
print(f"evidence: {out}")
PY

rm -rf "$E2E_DIR"
echo ""
echo "DRIVER-EXIT-E2E PASS — exit-chain + explicit audit attach contract proven"
echo "  scratch freed: $E2E_DIR (synthetic driver work dir)"
