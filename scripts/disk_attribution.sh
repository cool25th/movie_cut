#!/usr/bin/env bash
# QAUTO-DISK-ATTRIBUTION v1 (15th-cycle spec, 16th-cycle priority, 17th-cycle
# implementation): event-triggered, bounded, READ-ONLY disk attribution
# snapshot. Purpose — when a large delta (|Δ| ≥ 2 GiB) occurs, leave the
# minimum evidence an operator needs to tell "MovieCut consumed it" from
# "external consumption", instead of guessing after the fact.
#
# Bounded by design: a FIXED directory list only — no Top-N whole-volume du
# scans, no writes outside the append-only record, no cause determination.
#
# Trigger: run from disk_guard.sh whenever |Δ from the previous guard
# record| ≥ 2 GiB. Manual run: bash scripts/disk_attribution.sh (reads the
# last two guard records itself; no-op when the delta is small).
# Record: .build-check/history/attribution/attribution-<epoch>.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HISTORY="${1:-$ROOT/.build-check/history}"  # arg = synthetic history for testing
ATTR_DIR="$HISTORY/attribution"
GIB=$((1024 * 1024 * 1024))
THRESHOLD_BYTES=$((2 * GIB))

# Read the last two guard records (ts, available_bytes).
read -r CUR_TS CUR_BYTES PREV_BYTES <<EOF
$(python3 - "$HISTORY" <<'PY'
import glob, json, sys
files = sorted(glob.glob(sys.argv[1] + "/disk-*.json"))
recs = []
for f in files[-2:]:
    try:
        d = json.load(open(f))
        recs.append((d.get("ts", ""), int(d.get("available_bytes", 0))))
    except Exception:
        pass
if len(recs) < 2:
    print("", "0", "0")
else:
    print(recs[-1][0], recs[-1][1], recs[-2][1])
PY
)
EOF
[ "$CUR_BYTES" -gt 0 ] || { echo "attribution: no prior pair of guard records — skip"; exit 0; }

DELTA_BYTES=$((CUR_BYTES - PREV_BYTES))
ABS_DELTA=${DELTA_BYTES#-}
if [ "$ABS_DELTA" -lt "$THRESHOLD_BYTES" ]; then
  echo "attribution: |delta| $(python3 -c "print(round($ABS_DELTA/1024**3,2))")GiB < 2GiB — skip"
  exit 0
fi
REASON="LARGE_RECOVERY"; [ "$DELTA_BYTES" -lt 0 ] && REASON="LARGE_DROP"

du_kb() { # bounded du: fixed paths only, best-effort
  # `|| :` rescues the pipeline rc only — awk's printed output survives.
  # Without it, du's partial-failure exit (permission denied on a few files,
  # or an unmatched glob) under `set -o pipefail` + `set -e` kills the
  # script SILENTLY mid-capture (found by the 17th-cycle E2E — the exact
  # set -e silent-death trap class this repo has hit before).
  local p="$1"
  if [ -e "$p" ]; then
    du -sk "$p" 2>/dev/null | awk '{print $1}' || :
  else
    echo ""
  fi
}

REPO_KB="$(du_kb "$ROOT")"
BUILD_KB="$(du_kb "$ROOT/.build")"
DERIVED_KB="$(du_kb "$HOME/Library/Developer/Xcode/DerivedData")"
CACHES_KB="$(du_kb "$HOME/Library/Caches")"
TMP_KB="$(du -sk /tmp/moviecut-* 2>/dev/null | awk '{s+=$1} END {print s+0}' || :)"  # unmatched glob ⇒ du rc≠0, awk prints 0
# APFS local snapshot count via a 2s watchdog: tmutil can deadlock silently
# under a sandboxed shell — bounded tooling must never hang the observer.
# -1 = unavailable (watchdog), never a failure.
SNAPSHOTS="$(python3 -c "
import subprocess
try:
    out = subprocess.run(['tmutil','listlocalsnapshots','/'],
                         capture_output=True, timeout=2).stdout.decode()
    print(sum(1 for l in out.splitlines() if 'com.apple' in l))
except Exception:
    print(-1)
")"

CUR_TS="$CUR_TS" CUR_BYTES="$CUR_BYTES" PREV_BYTES="$PREV_BYTES" \
DELTA_BYTES="$DELTA_BYTES" REASON="$REASON" REPO_KB="$REPO_KB" \
BUILD_KB="$BUILD_KB" DERIVED_KB="$DERIVED_KB" CACHES_KB="$CACHES_KB" \
TMP_KB="$TMP_KB" SNAPSHOTS="$SNAPSHOTS" ATTR_DIR="$ATTR_DIR" \
python3 - <<'PY'
import datetime, json, os
def mb(kb):
    return round(int(kb) / 1024, 1) if kb not in ("", None) else None
rec = {
    "ts": datetime.datetime.now().isoformat(timespec="seconds"),
    "kind": "disk_attribution_v1",
    "observation_reason": os.environ["REASON"],
    "observed_at_guard": os.environ["CUR_TS"],
    "available_bytes": int(os.environ["CUR_BYTES"]),
    "delta_bytes": int(os.environ["DELTA_BYTES"]),
    "delta_gib": round(int(os.environ["DELTA_BYTES"]) / 1024**3, 2),
    "bounded_read_only": True,
    "paths_kb": {
        "repo": os.environ["REPO_KB"] or None,
        "repo_build": os.environ["BUILD_KB"] or None,
        "xcode_derived_data": os.environ["DERIVED_KB"] or None,
        "user_caches": os.environ["CACHES_KB"] or None,
        "tmp_moviecut_scratch": os.environ["TMP_KB"] or None,
    },
    "paths_mb": {k: mb(v) for k, v in {
        "repo": os.environ["REPO_KB"], "repo_build": os.environ["BUILD_KB"],
        "xcode_derived_data": os.environ["DERIVED_KB"],
        "user_caches": os.environ["CACHES_KB"],
        "tmp_moviecut_scratch": os.environ["TMP_KB"]}.items()},
    "apfs_local_snapshots": int(os.environ["SNAPSHOTS"]),
    "note": "evidence only — no cause determination (operator reviews)",
}
os.makedirs(os.environ["ATTR_DIR"], exist_ok=True)
out = os.path.join(os.environ["ATTR_DIR"],
                   f"attribution-{int(datetime.datetime.now().timestamp())}.json")
with open(out, "w") as f:
    json.dump(rec, f, indent=2)
    f.write("\n")
print(f"attribution snapshot: {os.environ['REASON']} "
      f"(Δ{rec['delta_gib']}GiB) — {out}")
PY
