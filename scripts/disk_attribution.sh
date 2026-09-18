#!/usr/bin/env bash
# QAUTO-DISK-ATTRIBUTION v1.1 (15th-cycle spec → 17th-cycle v1 → 18th-cycle
# v1.1): event-triggered, bounded, READ-ONLY disk attribution with baselines.
#
# v1.1 (18th-cycle feedback):
#   - 3-group schema: DIRECT_MOVIECUT / CORRELATED_DEV / EXTERNAL_CONTEXT
#   - CoreSimulator as its own field (ABSENT vs 0 — "not measured" never
#     conflated with "measured, not present")
#   - /private/var/vm (swap) as external context signal
#   - baseline record on every calm guard run; event captures compute
#     before/after/delta against the last baseline
#   - 4-tier verdict on drops: MOVIECUT_ATTRIBUTABLE / MOVIECUT_CONTRIBUTING /
#     EXTERNAL_DOMINANT / UNATTRIBUTED — "<10%" alone is only "insufficient
#     MovieCut evidence", never "external" by itself. Recoveries record
#     RECOVERY_OBSERVED only.
#
# Bounded: FIXED path list, no Top-N scans, reads only, writes only under
# .build-check/history/attribution/ (baselines pruned to the last 24).
#
# Trigger: invoked by disk_guard.sh on every run (mode decided by |Δ|).
# Manual: bash scripts/disk_attribution.sh [history-dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HISTORY="${1:-$ROOT/.build-check/history}"
ATTR_DIR="$HISTORY/attribution"
GIB=$((1024 * 1024 * 1024))
THRESHOLD_BYTES=$((2 * GIB))

du_kb() { # bounded du, rc-rescued (partial du failure must not kill us —
  # the set -e/pipefail silent-death trap this repo has hit three times)
  local p="$1"
  if [ -e "$p" ]; then
    du -sk "$p" 2>/dev/null | awk '{print $1}' || :
  else
    echo ""
  fi
}

# Last two guard records → current available + delta.
# Code-review P4-2: pipe-delimited so the parse makes NO assumption about
# ts containing no spaces (whitespace-delimited read would silently
# mis-split on any spaced timestamp).
IFS='|' read -r CUR_TS CUR_BYTES PREV_BYTES <<EOF
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
    print("|0|0")
else:
    print(f"{recs[-1][0]}|{recs[-1][1]}|{recs[-2][1]}")
PY
)
EOF
[ "$CUR_BYTES" -gt 0 ] || { echo "attribution: no prior pair of guard records — skip"; exit 0; }

DELTA_BYTES=$((CUR_BYTES - PREV_BYTES))
ABS_DELTA=${DELTA_BYTES#-}

# Fixed path measurements (shared by baseline and event records).
REPO_KB="$(du_kb "$ROOT")"
BUILD_KB="$(du_kb "$ROOT/.build")"
DERIVED_KB="$(du_kb "$HOME/Library/Developer/Xcode/DerivedData")"
SIM_PATH="$HOME/Library/Developer/CoreSimulator/Devices"
SIM_KB="$(du_kb "$SIM_PATH")"
CACHES_KB="$(du_kb "$HOME/Library/Caches")"
VM_KB="$(du_kb "/private/var/vm")"
TMP_KB="$(du -sk /tmp/moviecut-* 2>/dev/null | awk '{s+=$1} END {print s+0}' || :)"
SNAPSHOTS="$(python3 -c "
import subprocess
try:
    out = subprocess.run(['tmutil','listlocalsnapshots','/'],
                         capture_output=True, timeout=2).stdout.decode()
    print(sum(1 for l in out.splitlines() if 'com.apple' in l))
except Exception:
    print(-1)
")"

CUR_TS="$CUR_TS" CUR_BYTES="$CUR_BYTES" DELTA_BYTES="$DELTA_BYTES" \
ABS_DELTA="$ABS_DELTA" THRESHOLD="$THRESHOLD_BYTES" ATTR_DIR="$ATTR_DIR" \
REPO_KB="$REPO_KB" BUILD_KB="$BUILD_KB" DERIVED_KB="$DERIVED_KB" \
SIM_KB="$SIM_KB" SIM_PRESENT="$([ -e "$SIM_PATH" ] && echo yes || echo no)" \
CACHES_KB="$CACHES_KB" VM_KB="$VM_KB" TMP_KB="$TMP_KB" SNAPSHOTS="$SNAPSHOTS" \
python3 - <<'PY'
import datetime, glob, json, os

def mb(kb):
    return round(int(kb) / 1024, 1) if kb not in ("", None) else None

def sizes():
    sim_present = os.environ["SIM_PRESENT"] == "yes"
    return {
        "direct_moviecut": {
            "repo": mb(os.environ["REPO_KB"]),
            "repo_build": mb(os.environ["BUILD_KB"]),
            "tmp_moviecut_scratch": mb(os.environ["TMP_KB"]),
        },
        "correlated_dev": {
            "xcode_derived_data": mb(os.environ["DERIVED_KB"]),
            "core_simulator": (mb(os.environ["SIM_KB"]) if sim_present
                               else "ABSENT"),
        },
        "external_context": {
            "user_caches": mb(os.environ["CACHES_KB"]),
            "var_vm": mb(os.environ["VM_KB"]),
            "apfs_local_snapshots": int(os.environ["SNAPSHOTS"]),
        },
    }

attr_dir = os.environ["ATTR_DIR"]
os.makedirs(attr_dir, exist_ok=True)
now = datetime.datetime.now()
abs_delta = int(os.environ["ABS_DELTA"])
delta_bytes = int(os.environ["DELTA_BYTES"])
is_event = abs_delta >= int(os.environ["THRESHOLD"])

if not is_event:
    # 18th-cycle feedback: debounce — reuse the existing baseline when it is
    # younger than 10 minutes (manual back-to-back guard runs must not
    # densify the rolling record needlessly).
    existing = sorted(glob.glob(os.path.join(attr_dir, "baseline-*.json")))
    if existing:
        try:
            last = json.load(open(existing[-1]))
            age_min = (now - datetime.datetime.fromisoformat(last["ts"])).total_seconds() / 60
            if age_min < 10:
                print(f"attribution baseline fresh ({age_min:.0f}min < 10min) — reuse {os.path.basename(existing[-1])}")
                raise SystemExit(0)
        except (ValueError, KeyError, OSError):
            pass
    rec = {
        "ts": now.isoformat(timespec="seconds"),
        "kind": "disk_attribution_baseline",
        "observed_at_guard": os.environ["CUR_TS"],
        "available_bytes": int(os.environ["CUR_BYTES"]),
        "groups": sizes(),
        "bounded_read_only": True,
    }
    out = os.path.join(attr_dir, f"baseline-{int(now.timestamp())}.json")
    with open(out, "w") as f:
        json.dump(rec, f, indent=2)
        f.write("\n")
    # prune: keep the newest 24 baselines (bounded growth, automation-owned)
    olds = sorted(glob.glob(os.path.join(attr_dir, "baseline-*.json")))[:-24]
    for p in olds:
        try:
            os.remove(p)
        except OSError:
            pass
    print(f"attribution baseline recorded — {os.path.basename(out)}")
    raise SystemExit(0)

# --- event capture: before (last baseline) / after / delta + verdict ---
reason = "LARGE_RECOVERY" if delta_bytes > 0 else "LARGE_DROP"
baselines = sorted(glob.glob(os.path.join(attr_dir, "baseline-*.json")))
before_groups = None
if baselines:
    try:
        before_groups = json.load(open(baselines[-1])).get("groups")
    except Exception:
        before_groups = None

after_groups = sizes()

def flat(groups):
    out = {}
    for g, items in (groups or {}).items():
        for k, v in (items or {}).items():
            out[f"{g}.{k}"] = v
    return out

bf, af = flat(before_groups), flat(after_groups)
deltas = {}
for key, a_val in af.items():
    b_val = bf.get(key)
    if isinstance(a_val, (int, float)) and isinstance(b_val, (int, float)):
        deltas[key] = round(a_val - b_val, 1)
    else:
        deltas[key] = None  # ABSENT / unmeasurable on either side

def pos(keys):
    total = 0.0
    for k in keys:
        d = deltas.get(k)
        if isinstance(d, (int, float)) and d > 0:
            total += d
    return round(total, 1)

corr_keys = ["correlated_dev.xcode_derived_data", "correlated_dev.core_simulator"]
ext_keys = ["external_context.user_caches", "external_context.var_vm"]
# 18th-cycle P0: repo CONTAINS .build — summing repo + repo_build double
# counts. direct = repo_excluding_build + repo_build + tmp (equivalently
# repo_total + tmp); .build stays as explanatory breakdown only.
def _num(x):
    return x if isinstance(x, (int, float)) else 0.0
d_repo = _num(deltas.get("direct_moviecut.repo"))
d_build = _num(deltas.get("direct_moviecut.repo_build"))
d_tmp = _num(deltas.get("direct_moviecut.tmp_moviecut_scratch"))
direct_growth = round(d_repo + d_tmp, 1)  # repo is the TOTAL (incl. .build)

drop_mb = round(-delta_bytes / 1024**2, 1) if delta_bytes < 0 else None
verdict = "RECOVERY_OBSERVED"
ratios = {}
if drop_mb and drop_mb > 0:
    corr_growth = pos(corr_keys)
    ext_growth = pos(ext_keys)  # positive byte growth only; APFS snapshot
    # COUNT is contextual evidence and deliberately NOT summed here.
    direct_ratio = round(direct_growth / drop_mb, 3) if drop_mb else None
    observed_ratio = round((direct_growth + corr_growth) / drop_mb, 3) if drop_mb else None
    ext_ratio = round(ext_growth / drop_mb, 3) if drop_mb else None
    ratios = {"direct": direct_ratio, "moviecut_observed": observed_ratio,
              "external_observed": ext_ratio}
    # Precedence (18th-cycle): ATTRIBUTABLE → EXTERNAL_DOMINANT →
    # CONTRIBUTING (observed ≥10% & not attributable) → UNATTRIBUTED.
    if direct_ratio is not None and (direct_ratio >= 0.6 or
            (direct_ratio >= 0.3 and observed_ratio >= 0.7)):
        verdict = "MOVIECUT_ATTRIBUTABLE"
    elif (observed_ratio is not None and observed_ratio < 0.1
          and ext_ratio is not None and ext_ratio >= 0.5):
        verdict = "EXTERNAL_DOMINANT"
    elif observed_ratio is not None and observed_ratio >= 0.1:
        verdict = "MOVIECUT_CONTRIBUTING"
    else:
        verdict = "UNATTRIBUTED"

rec = {
    "ts": now.isoformat(timespec="seconds"),
    "kind": "disk_attribution_v1_1",
    "observation_reason": reason,
    "observed_at_guard": os.environ["CUR_TS"],
    "available_bytes": int(os.environ["CUR_BYTES"]),
    "delta_bytes": delta_bytes,
    "delta_gib": round(delta_bytes / 1024**3, 2),
    "before_baseline": (os.path.basename(baselines[-1]) if baselines else None),
    "groups_before": before_groups,
    "groups_after": after_groups,
    "group_deltas_mb": deltas,
    "growth_mb": {"direct": direct_growth, "correlated": pos(corr_keys),
                  "external": pos(ext_keys)},
    "drop_mb": drop_mb,
    "ratios": ratios,
    "verdict": verdict,
    "bounded_read_only": True,
    "note": "evidence + tiered verdict — final judgement remains with the operator",
}
out = os.path.join(attr_dir, f"attribution-{int(now.timestamp())}.json")
with open(out, "w") as f:
    json.dump(rec, f, indent=2)
    f.write("\n")
# 18th-cycle: post-event baseline — the next event must compare from NOW,
# not from the pre-event state.
post = {"ts": now.isoformat(timespec="seconds"),
        "kind": "disk_attribution_baseline_post_event",
        "observed_at_guard": os.environ["CUR_TS"],
        "available_bytes": int(os.environ["CUR_BYTES"]),
        "groups": after_groups, "bounded_read_only": True}
with open(os.path.join(attr_dir, f"baseline-{int(now.timestamp())}b.json"), "w") as f:
    json.dump(post, f, indent=2)
    f.write("\n")
print(f"attribution snapshot: {reason} (Δ{rec['delta_gib']}GiB) "
      f"verdict={verdict} — {os.path.basename(out)} (post-event baseline written)")
PY
