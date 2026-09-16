#!/usr/bin/env bash
# QAUTO-01 hardening (10th/11th-cycle): dataset pin preflight — 1차 범위는
# COMMITTED fixture만(10회차 피드백 확정). say/lavfi로 매 실행 재생성되는
# fixture는 출력 바이트가 환경에 따라 달라지므로 이 판정기의 대상이 아니며,
# 별도 provenance class(generator recipe/environment/artifact)로 2차 분리된다.
#
# Verify mode:  check_dataset_pins.sh <lock.json> <file> [<file>...]
# Init mode:    check_dataset_pins.sh --init <lock.json> <file> [<file>...]
#               (bootstrap 전용 — lock이 이미 있으면 무조건 거부. --force는
#                11회차 피드백으로 제거: force 경로는 "오염된 SHA를 새
#                baseline으로 승인하는 관리자 우회구"가 된다. baseline 갱신은
#                fixture 변경 커밋과 같은 review 단위에서 수동으로.)
#               init은 각 fixture가 git tracked + HEAD와 일치(clean)를 요구
#               — worktree에서 변조된 파일을 bootstrap하지 않기 위함.
#
# Per-file verdict: MATCH / MISMATCH / BASELINE_MISSING / HASH_ERROR.
# Exit: 0 = all MATCH (or successful init), 1 = any non-MATCH / refusal.
# Lock keys are repo-relative paths; callers may pass absolute paths.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

MODE="verify"
case "${1:-}" in
  --init) MODE="init"; shift ;;
esac
LOCK="${1:?lock file required}"
shift
[ "$#" -ge 1 ] || { echo "no dataset files given" >&2; exit 1; }

if [ "$MODE" = "init" ] && [ -e "$LOCK" ]; then
  echo "ERROR_LOCK_ALREADY_EXISTS — $LOCK" >&2
  echo "no --force path exists; baseline updates are a manual procedure paired" >&2
  echo "with the fixture-change commit (see qa/baselines/dataset-lock.json header)" >&2
  exit 1
fi

if [ "$MODE" = "init" ] || [ "$MODE" = "force-init" ]; then
  mkdir -p "$(dirname "$LOCK")"
  GIT_COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  GIT_DIRTY="$( [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] && echo true || echo false)"
  {
    printf '{\n'
    printf '  "schema_version": 1,\n'
    printf '  "kind": "dataset-lock",\n'
    printf '  "updated_at": "%s",\n' "$(date +%Y-%m-%dT%H:%M:%S)"
    printf '  "updated_by_commit": "%s",\n' "$GIT_COMMIT"
    printf '  "worktree_dirty_at_init": %s,\n' "$GIT_DIRTY"
    printf '  "fixtures": {\n'
    first=1
    for f in "$@"; do
      [ -f "$f" ] || { echo "cannot hash (not a regular file): $f" >&2; exit 1; }
      rel_check="${f#"$ROOT"/}"
      git -C "$ROOT" ls-files --error-unmatch "$rel_check" >/dev/null 2>&1 \
        || { echo "DIRTY_FIXTURE $rel_check — untracked file cannot bootstrap a baseline" >&2; exit 1; }
      git -C "$ROOT" diff --quiet HEAD -- "$rel_check" \
        || { echo "DIRTY_FIXTURE $rel_check — differs from HEAD; commit the fixture first" >&2; exit 1; }
      rel="${f#"$ROOT"/}"
      sha="$(shasum -a 256 "$f" | awk '{print $1}')"
      size="$(stat -f %z "$f")"
      [ $first -eq 1 ] || printf ',\n'
      printf '    "%s": {"sha256": "%s", "size": %s}' "$rel" "$sha" "$size"
      first=0
    done
    printf '\n  }\n}\n'
  } > "$LOCK"
  echo "dataset lock written: ${LOCK#"$ROOT"/} ($# fixtures)"
  exit 0
fi

# --- verify mode ---
[ -e "$LOCK" ] || { echo "BASELINE_MISSING — lock absent: $LOCK" >&2; exit 1; }

overall=0
for f in "$@"; do
  [ -f "$f" ] || { echo "HASH_ERROR $f (not a regular file)"; overall=1; continue; }
  rel="${f#"$ROOT"/}"
  sha="$(shasum -a 256 "$f" | awk '{print $1}')"
  size="$(stat -f %z "$f")"
  entry="$(LOCK="$LOCK" REL="$rel" python3 - <<'PY'
import json, os
lock = json.load(open(os.environ["LOCK"]))
fx = lock.get("fixtures", {})
print(json.dumps(fx.get(os.environ["REL"])))
PY
)"
  if [ "$entry" = "null" ] || [ -z "$entry" ]; then
    echo "BASELINE_MISSING $rel — add via --init review flow"; overall=1; continue
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
