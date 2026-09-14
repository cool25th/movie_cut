#!/usr/bin/env bash
# QAUTO-07 disk guard (2026-09-14): headroom check for the unmanned loop.
# Thresholds compare RAW available bytes — UI-rounded GiB is forbidden
# (4th-cycle feedback: 24.96 GiB would display as "25 GiB" and skip the
# warning). 3 tiers:
#   WARN  < 25 GiB  or drop ≥ 10 GiB since the previous record → continue
#   BLOCK < 15 GiB  → no NEW build/test/soak (running steps may finish)
#   STOP  < 10 GiB  → hard stop
# This is a HALT mechanism, not a cleanup feature — it deletes nothing.
# Exit codes: 0 = GO/WARN, 2 = BLOCK, 3 = STOP.
#
# Usage: bash scripts/disk_guard.sh [mount-point]   (default /)
# Record: .build-check/history/disk-<epoch>.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MOUNT="${1:-/}"
HISTORY="$ROOT/.build-check/history"
mkdir -p "$HISTORY"

GIB=$((1024 * 1024))  # KiB → GiB scale helper (×1024²)
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

GUARD="$(RECORDS_DIR="$HISTORY" AVAIL_BYTES="$AVAIL_BYTES" PREV_BYTES="$PREV_BYTES" python3 - <<'PY'
import glob, json, os, sys
GIB = 1024 ** 3
avail = int(os.environ["AVAIL_BYTES"])
prev = os.environ.get("PREV_BYTES", "")
drop = (int(prev) - avail) if prev else 0
if avail < 10 * GIB:
    print("STOP"); raise SystemExit
if avail < 15 * GIB:
    print("BLOCK"); raise SystemExit
# Hysteresis (5th-cycle feedback): once BLOCKed, resume build/test only at
# >=20 GiB — otherwise a boundary at 15 GiB flaps enter/exit every hour.
prev_guard = ""
recs = sorted(glob.glob(os.path.join(os.environ["RECORDS_DIR"], "disk-*.json")))
if recs:
    try:
        prev_guard = json.load(open(recs[-1])).get("guard", "")
    except Exception:
        prev_guard = ""
if prev_guard == "BLOCK" and avail < 20 * GIB:
    print("BLOCK"); raise SystemExit
if avail < 25 * GIB or drop >= 10 * GIB:
    print("WARN"); raise SystemExit
print("GO")
PY
)"

case "$GUARD" in
  GO)   ALLOWED=true;  RC=0; REASON="sufficient headroom" ;;
  WARN) ALLOWED=true;  RC=0; REASON="headroom shrinking — continue, watch closely" ;;
  BLOCK) ALLOWED=false; RC=2; REASON="INSUFFICIENT_DISK_HEADROOM — no new build/test/soak" ;;
  STOP) ALLOWED=false; RC=3; REASON="CRITICAL_DISK_HEADROOM — hard stop" ;;
esac

OUT="$HISTORY/disk-$(date +%s).json"
{
  printf '{\n'
  printf '  "ts": "%s",\n' "$(date +%Y-%m-%dT%H:%M:%S)"
  printf '  "mount": "%s",\n' "$MOUNT"
  printf '  "available_bytes": %s,\n' "$AVAIL_BYTES"
  printf '  "available_gib": %s,\n' "$AVAIL_GIB"
  if [ -n "$DELTA_BYTES" ]; then
    printf '  "delta_from_previous_bytes": %s,\n' "$DELTA_BYTES"
    printf '  "delta_gib": %s,\n' "$DELTA_GIB"
  fi
  printf '  "guard": "%s",\n' "$GUARD"
  printf '  "reason": "%s",\n' "$REASON"
  printf '  "increment_allowed": %s\n' "$ALLOWED"
  printf '}\n'
} > "$OUT"

echo "disk guard: $GUARD (${AVAIL_GIB} GiB free$( [ -n "$DELTA_GIB" ] && printf ', delta %s GiB' "$DELTA_GIB")) — ${OUT#"$ROOT"/}"
exit "$RC"
