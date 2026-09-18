#!/usr/bin/env bash
# QAUTO-07 disk guard (2026-09-14): headroom check for the unmanned loop.
# Thresholds compare RAW available bytes — UI-rounded GiB is forbidden
# (4th-cycle feedback: 24.96 GiB would display as "25 GiB" and skip the
# warning). 3 tiers:
#   WARN  < 25 GiB  or drop ≥ 10 GiB since the previous record → continue
#   BLOCK < 15 GiB  → no NEW build/test/soak (running steps may finish)
#   STOP  < 10 GiB  → hard stop
# Exit codes: 0 = GO/WARN, 2 = BLOCK, 3 = STOP.
#
# 5th-cycle: hysteresis — once BLOCKed, do not release below 20 GiB.
# 8th-cycle (disk recovery contract): leaving BLOCK requires TWO consecutive
# ≥20GiB observations (capacity recovery alone proved insufficient:
# 21.7 → 13.5 re-drop). RECURRENT_BLOCK — ≥2 BLOCK episodes within a rolling
# 24h window (consecutive BLOCK observations merge into one episode) flags
# recurrent_block + operator_action_required: keep build/test forbidden,
# passive soak only, no automatic cleanup/rebaseline.
# This is a HALT mechanism, not a cleanup feature — it deletes nothing.
#
# Usage: bash scripts/disk_guard.sh [mount-point] [history-dir]
# Record: <history-dir>/disk-<epoch>.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOUNT="${1:-/}"
HISTORY="${2:-$ROOT/.build-check/history}"
mkdir -p "$HISTORY"

AVAIL_KB="$(df -k "$MOUNT" | awk 'NR==2 {print $4}')"
AVAIL_BYTES=$((AVAIL_KB * 1024))

PREV_BYTES="$(python3 - "$HISTORY" <<'PY'
import glob, json, sys, os
files = sorted(glob.glob(os.path.join(sys.argv[1], "disk-*.json")))
if not files:
    print(""); raise SystemExit
try:
    with open(files[-1]) as f:
        print(json.load(f).get("available_bytes", ""))
except Exception:
    print("")
PY
)"

AVAIL_GIB="$(python3 -c "print(round($AVAIL_BYTES / 1024**3, 2))")"
if [ -n "$PREV_BYTES" ]; then
  DELTA_BYTES=$((AVAIL_BYTES - PREV_BYTES))
  DELTA_GIB="$(python3 -c "print(round($DELTA_BYTES / 1024**3, 2))")"
else
  DELTA_BYTES=""; DELTA_GIB=""
fi

GUARD_OUT="$(HISTORY_DIR="$HISTORY" AVAIL_BYTES="$AVAIL_BYTES" PREV_BYTES="$PREV_BYTES" python3 - <<'PY'
import glob, json, os
from datetime import datetime, timedelta
GIB = 1024 ** 3
avail = int(os.environ["AVAIL_BYTES"])
prev = os.environ.get("PREV_BYTES", "")
prev_int = int(prev) if prev else None
drop = (prev_int - avail) if prev_int else 0

MAX_OBS_GAP_HOURS = 26  # preregistered: the loop observes ~daily at 04:00,
                        # so nominal consecutive-observation spacing is 24h
                        # plus slack. A wider gap voids recovery confirmation.
FRESH_HOURS = 24        # operator-attention clear window after a clean release

records = []
for name in sorted(glob.glob(os.path.join(os.environ["HISTORY_DIR"], "disk-*.json"))):
    try:
        rec = json.load(open(name))
        records.append((datetime.fromisoformat(rec["ts"]),
                        rec.get("guard", ""), int(rec.get("available_bytes", 0))))
    except Exception:
        continue
now = datetime.now()

# Episodes: a BLOCK entry (previous observed record non-BLOCK) starts one;
# consecutive BLOCK observations — including across an observation GAP — stay
# the same episode (absence of data is not evidence of recovery).
episode_starts = []
prev_g = None
for ts, g, _b in records:
    if g == "BLOCK" and prev_g != "BLOCK":
        episode_starts.append(ts)
    prev_g = g
window_starts = [t for t in episode_starts if t >= now - timedelta(hours=24)]
recurrent = len(window_starts) >= 2

prev_guard = records[-1][1] if records else ""
prev_ts = records[-1][0] if records else None

# STOP state (14th-cycle contract): guard-only. While in STOP, stay STOP
# until >=12 GiB is observed TWICE consecutively, then return to BLOCK (never
# straight to WARN). "BLOCK-safe increments" are FORBIDDEN in STOP — only the
# guard observation, a small guard-state update, and the cycle report run.
# Any STOP observation in the recent history keeps us in the STOP
# release contract (last record governs; consecutive >=12GiB reads
# still required below — see the 12-GiB release check).
prev_stopped = prev_guard == "STOP" or any(g == "STOP" for _t, g, _b in records[-3:])
if avail < 10 * GIB:
    tier = "STOP"
elif prev_stopped and (avail < 12 * GIB or prev_int is None or prev_int < 12 * GIB):
    tier = "STOP"          # STOP release needs TWO consecutive >=12GiB reads
    # (code-review P3-2: the single-read release matched the documented
    #  contract only in spirit — now enforced like the BLOCK release path)
elif avail < 15 * GIB:
    tier = "BLOCK"
elif prev_guard == "BLOCK":
    # Release contract (8th/9th/18th-cycle): TWO consecutive >=20GiB
    # observations, gap within the preregistered observation limit, AND a
    # MINIMUM interval of 1h — two guard invocations seconds apart are one
    # physical moment, not temporal stability (17th-cycle 10s-gap lesson).
    if avail < 20 * GIB or prev_int is None or prev_int < 20 * GIB:
        tier = "BLOCK"
    elif prev_ts is None or (now - prev_ts) > timedelta(hours=MAX_OBS_GAP_HOURS):
        tier = "BLOCK"
    elif (now - prev_ts) < timedelta(hours=1):
        tier = "BLOCK"
    else:
        tier = "WARN" if avail < 25 * GIB else "GO"
elif avail < 25 * GIB or drop >= 10 * GIB:
    tier = "WARN"
else:
    tier = "GO"

reasons = []
if recurrent:
    reasons.append("RECURRENT_BLOCK_EPISODES")
    reasons.append("OPERATOR_ACTION_REQUIRED")
if tier == "BLOCK" and prev_guard == "BLOCK" and avail >= 20 * GIB:
    if prev_ts is not None and (now - prev_ts) > timedelta(hours=MAX_OBS_GAP_HOURS):
        reasons.append("RECOVERY_CONFIRMATION_EXPIRED")
    elif prev_ts is not None and (now - prev_ts) < timedelta(hours=1):
        reasons.append("AWAITING_MIN_OBSERVATION_INTERVAL_1H")
    else:
        reasons.append("AWAITING_SECOND_CONSECUTIVE_20GIB_OBSERVATION")

# operator_attention clears only after a clean release plus 24h with no
# new BLOCK (9th-cycle feedback — not on "24h without a record").
# Code-review P3-1 (2026-09-18): a history with NO BLOCK/STOP record ever
# requires no operator attention — released_at=None must not force the flag
# on forever for fresh deployments.
released_at = None
for i in range(1, len(records)):
    if records[i - 1][1] == "BLOCK" and records[i][1] != "BLOCK":
        released_at = records[i][0]
ever_gated = any(g in ("BLOCK", "STOP") for _t, g, _b in records)
since_release_ok = (released_at is not None
                    and (now - released_at) >= timedelta(hours=FRESH_HOURS)
                    and all(g != "BLOCK" for _t, g, _b in records
                            if released_at is not None and _t >= released_at))
operator_attention = recurrent or (ever_gated and not since_release_ok)

print(json.dumps({"tier": tier, "episodes_24h": len(window_starts),
                  "recurrent_block": recurrent,
                  "operator_attention_required": operator_attention,
                  "reasons": reasons}))
PY
)"

TIER="$(printf '%s' "$GUARD_OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['tier'])")"
EXTRAS_JSON="$GUARD_OUT"

case "$TIER" in
  GO)    ALLOWED=true;  RC=0; REASON="sufficient headroom" ;;
  WARN)  ALLOWED=true;  RC=0; REASON="headroom shrinking — continue, watch closely" ;;
  BLOCK) ALLOWED=false; RC=2; REASON="INSUFFICIENT_DISK_HEADROOM — no new build/test/soak" ;;
  STOP)  ALLOWED=false; RC=3; REASON="CRITICAL_DISK_HEADROOM — hard stop" ;;
esac

OUT="$HISTORY/disk-$(date +%s).json"
GUARD="$TIER" EXTRAS_JSON="$EXTRAS_JSON" OUT_PATH="$OUT" \
TS="$(date +%Y-%m-%dT%H:%M:%S)" MOUNT="$MOUNT" AVAIL_BYTES="$AVAIL_BYTES" \
AVAIL_GIB="$AVAIL_GIB" DELTA_BYTES="$DELTA_BYTES" DELTA_GIB="$DELTA_GIB" REASON="$REASON" ALLOWED="$ALLOWED" \
python3 - <<'PY'
import json, os
rec = {
    "ts": os.environ["TS"],
    "mount": os.environ["MOUNT"],
    "available_bytes": int(os.environ["AVAIL_BYTES"]),
    "available_gib": float(os.environ["AVAIL_GIB"]),
    "guard": os.environ["GUARD"],
    "reason": os.environ["REASON"],
    "increment_allowed": os.environ["ALLOWED"] == "true",
}
if os.environ.get("DELTA_BYTES"):
    rec["delta_from_previous_bytes"] = int(os.environ["DELTA_BYTES"])
    rec["delta_gib"] = float(os.environ["DELTA_GIB"])
extras = json.loads(os.environ["EXTRAS_JSON"])
rec["episodes_24h"] = extras["episodes_24h"]
rec["recurrent_block"] = extras["recurrent_block"]
rec["operator_attention_required"] = extras["operator_attention_required"]
if extras["reasons"]:
    rec["notes"] = extras["reasons"]
with open(os.environ["OUT_PATH"], "w") as f:
    json.dump(rec, f, indent=2)
    f.write("\n")
print(f"disk guard: {rec['guard']} ({rec['available_gib']} GiB free"
      f"{', delta ' + str(rec.get('delta_gib')) + ' GiB' if 'delta_gib' in rec else ''}, "
      f"episodes24h {rec['episodes_24h']}"
      f"{', RECURRENT' if rec['recurrent_block'] else ''}) — {os.environ['OUT_PATH']}")
PY

# QAUTO-DISK-ATTRIBUTION (18th-cycle): invoked on EVERY guard run — the
# script itself decides baseline vs event by |Δ|. Best-effort, never changes
# the guard rc.
bash "$ROOT/scripts/disk_attribution.sh" "$HISTORY" || true
exit "$RC"
