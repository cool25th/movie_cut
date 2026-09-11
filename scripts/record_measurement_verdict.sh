#!/usr/bin/env bash
# QAUTO-01 (evidence/harness pinning — 2026-09-12): retain a measurement
# verdict bound to app + harness identity, so a claimed PASS/FAIL is
# auditable afterwards. Both research drivers (CA-18, CA-21) kept all
# evidence in a trap-deleted /tmp dir — a verdict existed only as terminal
# output, which made the pre-registration discipline unenforceable.
#
# Usage (from a driver):
#   bash scripts/record_measurement_verdict.sh <name> <verdict> <measure.log> <harness-script>
#     <name>            measurement id (e.g. ca18, ca21) → qauto-<name>-<epoch>.json
#     <verdict>         PASS | FAIL | NO_VERDICT
#     <measure.log>     the measurement log captured before scratch cleanup
#     <harness-script>  path to the calling driver (sha256 is pinned)
#
# Output: .build-check/history/qauto-<name>-<epoch>.json — same dir the
# gate recorder already uses (gen_loop_state_report.py globs other
# prefixes, so these records are additive and safe).
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

# Observed lines: the driver's measurement prints (CA18MEASURE…/CA21MEASURE…)
# plus the verdict line. Escape for JSON (backslash, double quote, control CR).
OBSERVED="$(grep -E 'MEASURE |VERDICT: ' "$LOG" 2>/dev/null \
  | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\r//' || true)"

OUT="$HISTORY/qauto-$NAME-$(date +%s).json"
{
  printf '{\n'
  printf '  "ts": "%s",\n' "$(date +%Y-%m-%dT%H:%M:%S)"
  printf '  "measurement": "%s",\n' "$NAME"
  printf '  "verdict": "%s",\n' "$VERDICT"
  printf '  "app_commit": "%s",\n' "$APP_COMMIT"
  printf '  "harness_sha256": "%s",\n' "$HARNESS_SHA"
  printf '  "observed": ['
  first=1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    [ $first -eq 1 ] || printf ', '
    printf '"%s"' "$line"
    first=0
  done <<< "$OBSERVED"
  printf ']\n}\n'
} > "$OUT"

echo "measurement record: ${OUT#"$ROOT"/}"
