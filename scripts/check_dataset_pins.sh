#!/usr/bin/env bash
# QAUTO-01 hardening (10th–12th-cycle): dataset pin preflight — 1차 범위는
# COMMITTED fixture만(10회차 피드백 확정). say/lavfi로 매 실행 재생성되는
# fixture는 출력 바이트가 환경에 따라 달라지므로 이 판정기의 대상이 아니며,
# 별도 provenance class(generator recipe/environment/artifact)로 2차 분리된다.
#
# Lock schema v1.1 (12th-cycle): per-fixture fixture_id(논리 identity — 경로
# 이동과 무관)·oracle_role(측정에서의 계약 역할)·git_blob_sha(repository
# provenance) 추가. mtime은 의도적으로 제외(checkout/copy만으로 변동).
#
# Verify mode:  check_dataset_pins.sh <lock.json> <file> [<file>...]
#               per-file MATCH/MISMATCH/BASELINE_MISSING/HASH_ERROR,
#               exit 1 on any non-MATCH (fail-closed).
# Init mode:    check_dataset_pins.sh --init <lock.json> <spec>...
#               <spec> = <file>[:<fixture_id>:<oracle_role>]
#               bootstrap 전용 — lock이 이미 있으면 ERROR_LOCK_ALREADY_EXISTS
#               (no --force: force는 "오염된 SHA를 baseline으로 승인하는
#                관리자 우회구" — 11회차 확정). 각 fixture는 git tracked +
#               HEAD와 일치해야 함(DIRTY_FIXTURE 거부).
# Update mode:  check_dataset_pins.sh --update <lock.json> <file> --reason "…"
#               baseline update는 MANUAL OPERATOR 전용 — automation 금지
#               (12회차 절차 계약). 요건: tracked + 변경이 staged 또는
#               committed(worktree-only 거부) + reason 필수(기록) +
#               미변경 파일 거부. fixture와 lock 변경은 같은 review 단위로.
#
# Git operations target the repo that OWNS the lock
# (lock at <root>/qa/baselines/dataset-lock.json → <root>).
set -euo pipefail
SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MODE="verify"
case "${1:-}" in
  --init) MODE="init"; shift ;;
  --update) MODE="update"; shift ;;
esac
LOCK="${1:?lock file required}"
shift

LOCK_ROOT="$(cd "$(dirname "$LOCK")/../.." 2>/dev/null && pwd || echo "$SCRIPT_ROOT")"
git -C "$LOCK_ROOT" rev-parse --git-dir >/dev/null 2>&1 || LOCK_ROOT="$SCRIPT_ROOT"
REASON=""
FILE_ARG=""

if [ "$MODE" = "update" ]; then
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason) REASON="${2:-}"; shift 2 ;;
      --) shift; break ;;
      *) FILE_ARG="$1"; shift ;;
    esac
  done
  FILE="${FILE_ARG:?update target file required}"
  [ -n "$REASON" ] || { echo "UPDATE REFUSED — --reason is required (recorded in the lock)" >&2; exit 1; }
fi

rel_of() { # repo-relative path for lock keys
  local p="$1"
  case "$p" in
    "$LOCK_ROOT"/*) printf '%s' "${p#"$LOCK_ROOT"/}" ;;
    "$SCRIPT_ROOT"/*) printf '%s' "${p#"$SCRIPT_ROOT"/}" ;;
    *) printf '%s' "$p" ;;
  esac
}

sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }
size_of() { stat -f %z "$1"; }
blob_of() { git -C "$LOCK_ROOT" ls-files -s "$1" | awk '{print $2}'; }

# --- init (bootstrap only) ---
if [ "$MODE" = "init" ]; then
  [ ! -e "$LOCK" ] || { echo "ERROR_LOCK_ALREADY_EXISTS — $LOCK" >&2
    echo "no --force path exists; baseline updates are a manual --update procedure" >&2
    exit 1; }
  mkdir -p "$(dirname "$LOCK")"
  {
    printf '{\n'
    printf '  "schema_version": "1.1",\n'
    printf '  "kind": "dataset-lock",\n'
    printf '  "updated_at": "%s",\n' "$(date +%Y-%m-%dT%H:%M:%S)"
    printf '  "updated_by_commit": "%s",\n' "$(git -C "$LOCK_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    printf '  "fixtures": {\n'
    first=1
    for spec in "$@"; do
      file="${spec%%:*}"
      rest="${spec#*:}"
      if [ "$rest" = "$spec" ]; then fid="$rest"; role="unassigned"; else fid="${rest%%:*}"; role="${rest#*:}"; fi
      [ -f "$file" ] || { echo "cannot hash (not a regular file): $file" >&2; exit 1; }
      rel="$(rel_of "$file")"
      git -C "$LOCK_ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1 \
        || { echo "DIRTY_FIXTURE $rel — untracked file cannot bootstrap a baseline" >&2; exit 1; }
      git -C "$LOCK_ROOT" diff --quiet HEAD -- "$rel" \
        || { echo "DIRTY_FIXTURE $rel — differs from HEAD; commit the fixture first" >&2; exit 1; }
      [ $first -eq 1 ] || printf ',\n'
      printf '    "%s": {"fixture_id": "%s", "oracle_role": "%s", "sha256": "%s", "size": %s, "git_blob_sha": "%s", "path": "%s"}' \
        "$rel" "$fid" "$role" "$(sha_of "$file")" "$(size_of "$file")" "$(blob_of "$rel")" "$rel"
      first=0
    done
    printf '\n  }\n}\n'
  } > "$LOCK"
  echo "dataset lock written (schema 1.1): $LOCK ($# fixtures)"
  exit 0
fi

# --- update (manual operator only) ---
if [ "$MODE" = "update" ]; then
  [ -e "$LOCK" ] || { echo "BASELINE_MISSING — lock absent: $LOCK" >&2; exit 1; }
  [ -f "$FILE" ] || { echo "HASH_ERROR $FILE (not a regular file)" >&2; exit 1; }
  rel="$(rel_of "$FILE")"
  git -C "$LOCK_ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1 \
    || { echo "UPDATE REFUSED — $rel is not tracked; track and commit the fixture first" >&2; exit 1; }
  if ! git -C "$LOCK_ROOT" diff --quiet HEAD -- "$rel"; then
    if git -C "$LOCK_ROOT" diff --cached --quiet -- "$rel"; then
      echo "UPDATE REFUSED — $rel has worktree-only changes; stage or commit the fixture change first" >&2
      exit 1
    fi
  elif git -C "$LOCK_ROOT" diff --cached --quiet -- "$rel"; then
    echo "UPDATE REFUSED — no staged/committed change for $rel — nothing to update" >&2
    exit 1
  fi
  LOCK="$LOCK" REL="$rel" SHA="$(sha_of "$FILE")" SIZE="$(size_of "$FILE")" \
  BLOB="$(blob_of "$rel")" REASON="$REASON" \
  UPDATED_AT="$(date +%Y-%m-%dT%H:%M:%S)" \
  UPDATED_BY="$(git -C "$LOCK_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  python3 - <<'PY'
import json, os
lock = json.load(open(os.environ["LOCK"]))
entry = lock["fixtures"][os.environ["REL"]]
entry["sha256"] = os.environ["SHA"]
entry["size"] = int(os.environ["SIZE"])
entry["git_blob_sha"] = os.environ["BLOB"]
entry.setdefault("update_history", []).append({
    "ts": os.environ["UPDATED_AT"], "commit": os.environ["UPDATED_BY"],
    "reason": os.environ["REASON"]})
lock["updated_at"] = os.environ["UPDATED_AT"]
lock["updated_by_commit"] = os.environ["UPDATED_BY"]
with open(os.environ["LOCK"], "w") as f:
    json.dump(lock, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"dataset pin updated: {os.environ['REL']} (reason recorded in lock update_history)")
PY
  echo "NOTE: commit the lock together with the fixture change (same review unit)." >&2
  exit 0
fi

# --- verify ---
[ -e "$LOCK" ] || { echo "BASELINE_MISSING — lock absent: $LOCK" >&2; exit 1; }
overall=0
for f in "$@"; do
  [ -f "$f" ] || { echo "HASH_ERROR $f (not a regular file)"; overall=1; continue; }
  rel="$(rel_of "$f")"
  sha="$(sha_of "$f")"
  entry="$(LOCK="$LOCK" REL="$rel" python3 - <<'PY'
import json, os
lock = json.load(open(os.environ["LOCK"]))
print(json.dumps(lock.get("fixtures", {}).get(os.environ["REL"])))
PY
)"
  if [ "$entry" = "null" ] || [ -z "$entry" ]; then
    echo "BASELINE_MISSING $rel — add via the init/update review flow"; overall=1; continue
  fi
  expected="$(printf '%s' "$entry" | python3 -c "import json,sys; print(json.load(sys.stdin)['sha256'])")"
  if [ "$sha" = "$expected" ]; then
    echo "MATCH $rel"
  else
    echo "MISMATCH $rel expected=$expected observed=$sha"; overall=1
  fi
done
[ "$overall" -eq 0 ] && echo "dataset pins: ALL MATCH" || echo "dataset pins: FAILED (fail-closed)"
exit "$overall"
