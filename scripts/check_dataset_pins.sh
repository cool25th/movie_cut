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
    SOURCE_STATE="staged"
  else
    SOURCE_STATE="committed"
  fi
  JOURNAL="$(dirname "$LOCK")/dataset-lock-updates.jsonl"
  LOCK="$LOCK" REL="$rel" SHA="$(sha_of "$FILE")" SIZE="$(size_of "$FILE")" \
  BLOB="$(blob_of "$rel")" REASON="$REASON" SOURCE_STATE="$SOURCE_STATE" \
  JOURNAL="$JOURNAL" \
  UPDATED_AT="$(date +%Y-%m-%dT%H:%M:%S)" \
  HEAD_COMMIT="$(git -C "$LOCK_ROOT" rev-parse HEAD 2>/dev/null | cut -c1-12 || echo unknown)" \
  python3 - <<'PY'
import datetime, hashlib, json, os
lock = json.load(open(os.environ["LOCK"]))
entry = lock["fixtures"].get(os.environ["REL"])
if entry is None:
    print(f"UPDATE REFUSED — {os.environ['REL']} is not in the lock (BASELINE_MISSING)")
    raise SystemExit(1)
old_sha = entry["sha256"]
old_blob = entry.get("git_blob_sha", "")
new_sha = os.environ["SHA"]
if old_sha == new_sha:
    print("UPDATE REFUSED — pinned sha already matches the current bytes — nothing to update")
    raise SystemExit(1)
# 14th-cycle (feedback-revised): update_id and payload_digest are SEPARATE
# roles. update_id = occurrence identifier (sha256 of "dataset-pin-update-v2"
# + fixture_id + update_seq) — content hashes cannot identify occurrences
# (A→B→A→B with equal reasons reproduces the same id). payload_digest =
# sha256 of the canonical provenance payload — identifies what changed.
# Raw reason is stored as-is; JSON escaping handles embedded newlines.
fid = entry.get("fixture_id", "")
update_seq = len(entry.get("update_history", [])) + 1
update_id = hashlib.sha256(("dataset-pin-update-v2\n" + fid + "\n"
                            + str(update_seq)).encode("utf-8")).hexdigest()
payload = {"fixture_id": fid, "path": os.environ["REL"],
           "old_sha256": old_sha, "new_sha256": new_sha,
           "old_git_blob_sha": old_blob, "new_git_blob_sha": os.environ["BLOB"],
           "base_head_commit": os.environ["HEAD_COMMIT"],
           "source_state": os.environ["SOURCE_STATE"],
           "reason": os.environ["REASON"]}
payload_digest = hashlib.sha256(json.dumps(
    payload, sort_keys=True, ensure_ascii=False,
    separators=(",", ":")).encode("utf-8")).hexdigest()
line = {"ts": os.environ["UPDATED_AT"], "kind": "dataset_pin_update",
        "update_id": update_id, "update_seq": update_seq,
        "payload_digest": payload_digest,
        "fixture_id": fid, "path": os.environ["REL"],
        "old_sha256": old_sha, "new_sha256": new_sha,
        "old_git_blob_sha": old_blob,
        "new_git_blob_sha": os.environ["BLOB"],
        "source_state": os.environ["SOURCE_STATE"],
        "reason": os.environ["REASON"], "base_head_commit": os.environ["HEAD_COMMIT"]}
with open(os.environ["JOURNAL"], "a") as f:
    f.write(json.dumps(line, ensure_ascii=False) + "\n")
entry["sha256"] = new_sha
entry["size"] = int(os.environ["SIZE"])
entry["git_blob_sha"] = os.environ["BLOB"]
entry.setdefault("update_history", []).append({
    "ts": os.environ["UPDATED_AT"], "commit": os.environ["HEAD_COMMIT"][:12],
    "sha256": new_sha, "reason": os.environ["REASON"],
    "update_id": update_id, "update_seq": update_seq,
    "payload_digest": payload_digest})
lock["updated_at"] = os.environ["UPDATED_AT"]
lock["updated_by_commit"] = os.environ["HEAD_COMMIT"][:12]
with open(os.environ["LOCK"], "w") as f:
    json.dump(lock, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"dataset pin updated: {os.environ['REL']} (update_id {update_id[:12]}…, journal line appended)")
PY
  echo "NOTE: commit the lock, journal, and fixture change together (same review unit)." >&2
  exit 0
fi

# --- verify ---
[ -e "$LOCK" ] || { echo "BASELINE_MISSING — lock absent: $LOCK" >&2; exit 1; }
JOURNAL="$(dirname "$LOCK")/dataset-lock-updates.jsonl"

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

# Journal cross-check (13th-cycle): every lock update_history entry must have
# a matching append-only journal line. A lock that moved without its journal
# ("baseline이 몰래 움직임") is a fail-closed condition.
JOURNAL="$JOURNAL" LOCK="$LOCK" python3 - <<'PY'
import json, os
lock = json.load(open(os.environ["LOCK"]))
hist = []
for rel, entry in lock.get("fixtures", {}).items():
    for h in entry.get("update_history", []):
        hist.append((rel, h))
if not hist:
    raise SystemExit(0)
journal = []
jpath = os.environ["JOURNAL"]
if os.path.exists(jpath):
    for line in open(jpath):
        line = line.strip()
        if not line:
            continue
        try:
            journal.append(json.loads(line))
        except Exception:
            journal.append({})

problems = []
# Forward: history → journal (every recorded update must appear exactly once).
for rel, h in hist:
    uid = h.get("update_id")
    if not uid:
        # Legacy pre-update_id entries are treated as missing — strict by
        # design (no real legacy entries exist; created after this change).
        problems.append(f"MISSING_UPDATE_JOURNAL {rel} (no update_id)")
        continue
    hits = [j for j in journal if j.get("update_id") == uid]
    if len(hits) == 0:
        problems.append(f"MISSING_UPDATE_JOURNAL {rel}@{uid[:12]}")
    elif len(hits) > 1:
        problems.append(f"DUPLICATE_UPDATE_JOURNAL {rel}@{uid[:12]} x{len(hits)}")
    else:
        j = hits[0]
        if j.get("payload_digest") != h.get("payload_digest"):
            problems.append(f"UPDATE_JOURNAL_MISMATCH {rel}@{uid[:12]}")
# Reverse: journal → history (every journal line must correspond to exactly
# one recorded update — otherwise the entry is an orphan).
for j in journal:
    uid = j.get("update_id")
    if not uid:
        problems.append("ORPHAN_UPDATE_JOURNAL (line without update_id)")
        continue
    hits = [h for _rel, h in hist if h.get("update_id") == uid]
    if len(hits) == 0:
        problems.append(f"ORPHAN_UPDATE_JOURNAL {j.get('fixture_id', '?')}@{uid[:12]}")
    elif len(hits) > 1:
        problems.append(f"DUPLICATE_UPDATE_HISTORY {j.get('fixture_id', '?')}@{uid[:12]} x{len(hits)}")
if problems:
    print("UPDATE_JOURNAL_FAIL: " + "; ".join(problems))
    raise SystemExit(1)
print(f"update journal consistent ({len(hist)} updates, 1:1 cardinality verified)")
raise SystemExit(0)
PY
rc=$?
if [ "$rc" -ne 0 ]; then overall=1; fi

[ "$overall" -eq 0 ] && echo "dataset pins: ALL MATCH" || echo "dataset pins: FAILED (fail-closed)"
exit "$overall"
