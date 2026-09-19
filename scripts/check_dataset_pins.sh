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
  --repair-missing-journal) MODE="repair"; shift ;;
  --rebaseline) MODE="rebaseline"; shift ;;
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
      if [ "$rest" = "$spec" ]; then
        # bare path — no colon at all
        fid="$rest"; role="unassigned"
      else
        fid="${rest%%:*}"
        role="${rest#*:}"
        # Code-review P4-1: a 2-part spec (file:fixture_id) has no role
        # segment — "${rest#*:}" echoes the whole rest, duplicating fid.
        [ "$role" = "$rest" ] && role="unassigned"
      fi
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

# --- repair-missing-journal (manual operator only — 13th-cycle spec) -----
# Restores a LOST journal line for a lock update_history entry ONLY when
# Git history independently proves the change: (a) some commit holds the
# fixture blob == new git_blob_sha, (b) its parent holds the OLD blob,
# (c) the lock already records that A→B. recovered_at is ALWAYS now —
# never a backdated timestamp (the original event time is unknown by
# definition of "journal lost"). If Git cannot prove it, we escalate to
# UNRECOVERABLE_UPDATE_PROVENANCE instead of silently healing.
if [ "$MODE" = "repair" ]; then
  [ -e "$LOCK" ] || { echo "BASELINE_MISSING — lock absent: $LOCK" >&2; exit 1; }
  # reuse the update-mode arg parsing (--reason required)
  FILE_ARG=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason) REASON="${2:-}"; shift 2 ;;
      *) FILE_ARG="$1"; shift ;;
    esac
  done
  FILE="${FILE_ARG:?repair target file required}"
  [ -n "${REASON:-}" ] || { echo "REPAIR REFUSED — --reason is required" >&2; exit 1; }
  [ -f "$FILE" ] || { echo "HASH_ERROR $FILE (not a regular file)" >&2; exit 1; }
  rel="$(rel_of "$FILE")"
  JOURNAL="$(dirname "$LOCK")/dataset-lock-updates.jsonl"
  LOCK="$LOCK" REL="$rel" JOURNAL="$JOURNAL" REASON="$REASON" \
  LOCK_ROOT="$LOCK_ROOT" LOCK_REL="$(rel_of "$LOCK")" \
  python3 - <<'PY'
import datetime, hashlib, json, os, subprocess

lock = json.load(open(os.environ["LOCK"]))
rel = os.environ["REL"]
lock_rel = os.environ["LOCK_REL"]
entry = lock["fixtures"].get(rel)
if entry is None:
    print(f"REPAIR REFUSED — {rel} is not in the lock"); raise SystemExit(1)
hist = entry.get("update_history", [])
if not hist:
    print(f"REPAIR REFUSED — {rel} has no update_history (nothing to repair)")
    raise SystemExit(1)

def git(*args):
    # rev-parse ECHOES unparseable args on stdout (root-commit "c^" trap —
    # 23rd-cycle E2E): only a zero rc proves the rev resolved.
    r = subprocess.run(["git", "-C", os.environ["LOCK_ROOT"], *args],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""

def unprovable(why):
    print(f"UNRECOVERABLE_UPDATE_PROVENANCE — {why}. Do NOT force-heal; "
          f"use --rebaseline to start a new provenance chain with an "
          f"explicit reason.")
    raise SystemExit(2)

h = hist[-1]
new_blob = entry.get("git_blob_sha", "")
new_sha = h.get("sha256", entry.get("sha256", ""))
old_blob_expected = h.get("old_git_blob_sha", "")  # may be absent (legacy)

# --- Hardened proof (24th-cycle): the two PAST TREES must independently
# prove fixture A→B AND lock A→B with stable identity. The current lock is
# an index of what to prove, never the proof itself.
# Step 1 — find change_commit: a commit whose tree holds fixture blob == B.
candidates = []
for c in git("log", "--format=%H", "--", rel).splitlines():
    if c and git("rev-parse", f"{c}:{rel}") == new_blob:
        candidates.append(c)
if not candidates:
    unprovable(f"no commit tree holds the pinned blob for {rel}")

def tree_lock(commit):
    out = git("show", f"{commit}:{lock_rel}")
    try:
        return json.loads(out) if out else None
    except Exception:
        return None

proven = None
rejects = []
for change_commit in candidates:
    base = git("rev-parse", f"{change_commit}^")
    if not base:
        rejects.append((change_commit, "root commit — no parent epoch")); continue
    # ancestry: base⊂change is implied by parent; require change⊂HEAD
    if git("merge-base", "--is-ancestor", change_commit, "HEAD") is not None \
            and subprocess.run(["git", "-C", os.environ["LOCK_ROOT"], "merge-base",
                                "--is-ancestor", change_commit, "HEAD"],
                               capture_output=True).returncode != 0:
        rejects.append((change_commit, "not an ancestor of HEAD")); continue
    base_blob = git("rev-parse", f"{base}:{rel}")
    if not base_blob or base_blob == new_blob:
        rejects.append((change_commit, "parent tree does not hold a distinct A")); continue
    # exactly ONE commit in the UNION of {fixture, lock} paths may exist in
    # base..change — fixture and lock changing in SEPARATE commits must be
    # UNRECOVERABLE even if both final trees show A→B (24th-cycle feedback).
    touching = git("log", "--format=%H", f"{base}..{change_commit}", "--", rel, lock_rel).splitlines()
    touching = [t for t in touching if t]
    if touching != [change_commit]:
        rejects.append((change_commit, f"base..change touches fixture/lock in "
                                       f"{len(touching)} commits — refusing to collapse")); continue
    # both trees must carry the LOCK with A→B and stable identity
    base_lock, change_lock_tree = tree_lock(base), tree_lock(change_commit)
    if base_lock is None or change_lock_tree is None:
        rejects.append((change_commit, "lock file absent in one of the two trees")); continue
    be = base_lock.get("fixtures", {}).get(rel)
    ce = change_lock_tree.get("fixtures", {}).get(rel)
    if not be or not ce:
        rejects.append((change_commit, "fixture entry absent in one of the two lock trees")); continue
    for ident in ("fixture_id", "path", "oracle_role"):
        if be.get(ident) != ce.get(ident) or ce.get(ident) != entry.get(ident):
            rejects.append((change_commit, f"identity field {ident} changed across the epoch")); continue
    # A→B: content SHAs from the trees' own lock entries
    if be.get("sha256") == ce.get("sha256"):
        rejects.append((change_commit, "lock trees show no A→B change")); continue
    proven = (base, change_commit, base_blob)
    break

if proven is None:
    detail = "; ".join(f"{c[:8]}: {w}" for c, w in rejects[:3])
    unprovable(f"no commit pair proves the epoch ({detail or 'no candidates'})")

base, change_commit, base_blob = proven
if old_blob_expected and old_blob_expected != base_blob:
    # lock claimed a different old blob than the tree proves — trust the tree
    print(f"note: lock old_git_blob_sha mismatched tree evidence "
          f"(tree wins: {base_blob[:12]})")
now = datetime.datetime.now().isoformat(timespec="seconds")
fid = entry.get("fixture_id", "")
update_seq = h.get("update_seq", len(hist))
# update_id recomputed from EVIDENCE (never the lock-supplied value)
update_id = hashlib.sha256(("dataset-pin-update-v2\n" + fid + "\n"
                            + str(update_seq)).encode("utf-8")).hexdigest()

payload = {"fixture_id": fid, "path": rel,
           "old_sha256": "", "new_sha256": new_sha,
           "old_git_blob_sha": base_blob, "new_git_blob_sha": new_blob,
           "base_head_commit": base[:12], "source_state": "recovered",
           "reason": os.environ["REASON"]}
payload_digest = hashlib.sha256(json.dumps(
    payload, sort_keys=True, ensure_ascii=False,
    separators=(",", ":")).encode("utf-8")).hexdigest()

# idempotency contract (24th-cycle feedback): same update_id + SAME
# canonical recovery → exit 0 / ALREADY_PRESENT (re-runnable); same
# update_id + DIFFERENT recovery → hard fail / PROVENANCE_CONFLICT —
# idempotency must never become a provenance-hiding mechanism.
if os.path.exists(os.environ["JOURNAL"]):
    for line in open(os.environ["JOURNAL"]):
        try:
            j = json.loads(line)
        except Exception:
            continue
        if j.get("update_id") == update_id and \
                j.get("kind") == "recovered_missing_update_journal":
            # canonical recovery identity = update_id + evidence commits.
            # The repair-time --reason is NOT part of it (a re-run may word
            # the reason differently; the A→B evidence is what must match).
            if j.get("evidence", {}).get("base_commit") == base[:12] and \
                    j.get("evidence", {}).get("change_commit") == change_commit[:12]:
                print(f"REPAIR_ALREADY_PRESENT")
                print(f"  update_id={update_id}")
                print(f"  recovered_at={j.get('recovered_at')}")
                print(f"  mutation=false reason=duplicate_update_id")
                raise SystemExit(0)
            print(f"PROVENANCE_CONFLICT — journal already holds a DIFFERENT "
                  f"recovery for {rel}@{update_id[:12]} "
                  f"(existing evidence {j.get('evidence')} vs proven "
                  f"{base[:12]}→{change_commit[:12]}). Refusing to overwrite.")
            raise SystemExit(3)

line_out = {"ts": now, "kind": "recovered_missing_update_journal",
        "recovered_at": now,
        "update_id": update_id, "update_seq": update_seq,
        "payload_digest": payload_digest,
        "original_payload_digest": h.get("payload_digest"),
        "fixture_id": fid, "path": rel,
        "old_sha256": payload["old_sha256"], "new_sha256": new_sha,
        "old_git_blob_sha": base_blob, "new_git_blob_sha": new_blob,
        "source_state": "recovered",
        "reason": os.environ["REASON"],
        "evidence": {"base_commit": base[:12], "change_commit": change_commit[:12],
                     "lock_read_from_trees": True},
        "note": "journal line re-created from two-tree Git proof; original event time unknown by construction"}
with open(os.environ["JOURNAL"], "a") as f:
    f.write(json.dumps(line_out, ensure_ascii=False) + "\n")
print(f"REPAIR_CREATED")
print(f"  update_id={update_id} recovered_at={now}")
print(f"  evidence={base[:12]}→{change_commit[:12]} lock_verified_in_both_trees=true")
print(f"  — re-run verify to confirm 1:1")
PY
  exit $?
fi

# --- rebaseline (manual operator only — last resort after UNRECOVERABLE) --
# Starts a NEW provenance chain for one fixture: provenance_reset event +
# re-pinned current bytes. The old entry is not deleted — history stays
# linked through the reset event (repair must never overwrite evidence).
if [ "$MODE" = "rebaseline" ]; then
  [ -e "$LOCK" ] || { echo "BASELINE_MISSING — lock absent: $LOCK" >&2; exit 1; }
  FILE_ARG=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason) REASON="${2:-}"; shift 2 ;;
      *) FILE_ARG="$1"; shift ;;
    esac
  done
  FILE="${FILE_ARG:?rebaseline target file required}"
  [ -n "${REASON:-}" ] || { echo "REBASELINE REFUSED — --reason is required (operator acknowledgment)" >&2; exit 1; }
  [ -f "$FILE" ] || { echo "HASH_ERROR $FILE (not a regular file)" >&2; exit 1; }
  rel="$(rel_of "$FILE")"
  git -C "$LOCK_ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1 \
    || { echo "REBASELINE REFUSED — $rel is not tracked" >&2; exit 1; }
  git -C "$LOCK_ROOT" diff --quiet HEAD -- "$rel" \
    || { echo "REBASELINE REFUSED — $rel differs from HEAD; commit first" >&2; exit 1; }
  JOURNAL="$(dirname "$LOCK")/dataset-lock-updates.jsonl"
  LOCK="$LOCK" REL="$rel" JOURNAL="$JOURNAL" REASON="$REASON" FILE="$FILE" \
  LOCK_ROOT="$LOCK_ROOT" \
  python3 - <<'PY'
import datetime, hashlib, json, os, subprocess
lock = json.load(open(os.environ["LOCK"]))
rel = os.environ["REL"]
entry = lock["fixtures"].get(rel)
if entry is None:
    print(f"REBASELINE REFUSED — {rel} is not in the lock"); raise SystemExit(1)
def git(*a):
    # same rev-parse echo trap as above — zero rc required
    r = subprocess.run(["git", "-C", os.environ["LOCK_ROOT"], *a],
                       capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""
blob = git("rev-parse", f"HEAD:{rel}")
sha = hashlib.sha256(open(os.environ["FILE"], "rb").read()).hexdigest()
now = datetime.datetime.now().isoformat(timespec="seconds")
epoch = len(entry.get("update_history", [])) + 1
reset_update_id = hashlib.sha256(("dataset-pin-reset-v1\n" + entry.get("fixture_id","") + "\n"
                                   + str(epoch)).encode("utf-8")).hexdigest()
supersedes = [h.get("update_id") for h in entry.get("update_history", [])
              if h.get("update_id")]
line = {"ts": now, "kind": "provenance_reset",
        "update_id": reset_update_id, "update_seq": epoch,
        "fixture_id": entry.get("fixture_id", ""), "path": rel,
        "provenance_epoch": epoch,
        "old_sha256": entry.get("sha256"), "new_sha256": sha,
        "old_git_blob_sha": entry.get("git_blob_sha"), "new_git_blob_sha": blob,
        "reason": os.environ["REASON"],
        "supersedes_update_ids": supersedes,
        "operator_acknowledgment": True,
        "note": "new provenance chain starts here — prior chain kept via reset event"}
with open(os.environ["JOURNAL"], "a") as f:
    f.write(json.dumps(line, ensure_ascii=False) + "\n")
entry["sha256"] = sha
entry["size"] = os.path.getsize(os.environ["FILE"])
entry["git_blob_sha"] = blob
entry["provenance_epoch"] = epoch
entry.setdefault("update_history", []).append({
    "ts": now, "commit": git("rev-parse", "--short", "HEAD"),
    "sha256": sha, "reason": os.environ["REASON"],
    "update_id": reset_update_id,
    "update_seq": epoch, "payload_digest": None,
    "kind": "provenance_reset"})
lock["updated_at"] = now
with open(os.environ["LOCK"], "w") as f:
    json.dump(lock, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"rebaselined: {rel} (epoch {epoch}, reset event appended)")
PY
  echo "NOTE: commit the lock and journal together (same review unit)." >&2
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
  # Code-review P3-3: a malformed entry (missing sha256) must produce an
  # explicit verdict — never a KeyError that set -e turns into a silent death
  # halfway through the loop.
  expected="$(printf '%s' "$entry" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('sha256', '') if isinstance(d, dict) else '')" || echo '')"
  if [ -z "$expected" ]; then
    echo "HASH_ERROR $rel — lock entry has no sha256 (malformed)"; overall=1; continue
  fi
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

superseded = set()
for j in journal:
    for uid in (j.get("supersedes_update_ids") or []):
        superseded.add(uid)

problems = []
# Forward: history → journal (every recorded update must appear exactly once).
for rel, h in hist:
    uid = h.get("update_id")
    if not uid:
        # Legacy pre-update_id entries are treated as missing — strict by
        # design (no real legacy entries exist; created after this change).
        problems.append(f"MISSING_UPDATE_JOURNAL {rel} (no update_id)")
        continue
    if uid in superseded:
        continue  # declared broken & reset by an operator provenance_reset
    hits = [j for j in journal if j.get("update_id") == uid]
    if len(hits) == 0:
        problems.append(f"MISSING_UPDATE_JOURNAL {rel}@{uid[:12]}")
    elif len(hits) > 1:
        problems.append(f"DUPLICATE_UPDATE_JOURNAL {rel}@{uid[:12]} x{len(hits)}")
    else:
        j = hits[0]
        if j.get("kind") == "recovered_missing_update_journal":
            # A recovered line corroborates via the lock's surviving digest —
            # its own reconstructed payload_digest can never equal the lost
            # original by construction.
            if j.get("original_payload_digest") != h.get("payload_digest"):
                problems.append(f"UPDATE_JOURNAL_MISMATCH {rel}@{uid[:12]}")
        elif j.get("payload_digest") != h.get("payload_digest"):
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
