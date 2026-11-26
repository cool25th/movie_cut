#!/usr/bin/env bash
# ChatGPT 외부 리뷰 루프 — 진행상황 다이제스트 수집 (docs/CHATGPT_REVIEW_LOOP_20260912.md §1)
# 기록된 산출물만 읽는다 — 테스트/빌드 실행 없음(새벽 무인 실행·디스크 정책).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "# PROGRESS DIGEST $(date +%Y-%m-%dT%H:%M:%S)"
echo

echo "## HEAD"
git log --oneline -1
echo

# 다음 보고 범위 계산용: 직전 보고서의 Since-commit
SINCE=""
LAST_REPORT=""
for f in $(ls -1 docs/AI_REVIEW/REPORT_*.md 2>/dev/null | sort); do LAST_REPORT="$f"; done
if [ -n "$LAST_REPORT" ] && [ -f "$LAST_REPORT" ]; then
  SINCE="$(awk '/^Since-commit:/ {print $2; exit}' "$LAST_REPORT" || true)"
  echo "## Last report"
  echo "$LAST_REPORT (Since-commit: ${SINCE:-none})"
  echo
fi

echo "## Commits since last report"
if [ -n "$SINCE" ] && git cat-file -e "$SINCE" 2>/dev/null; then
  git log --oneline "${SINCE}..HEAD"
else
  echo "(no marker — showing last 20)"
  git log --oneline -20
fi
echo

echo "## Working tree (다른 세션 WIP — 읽기 전용 컨텍스트, 커밋 포함 금지)"
git status --short | head -20
echo

echo "## LOOP_STATE (현재 증분 헤드)"
head -8 docs/LOOP_STATE.md
echo

echo "## SESSION_HANDOFF_CURRENT (최신 항목 + 큐)"
awk '/^## 2026/{n++} n==1' docs/SESSION_HANDOFF_CURRENT.md | head -45
echo

echo "## Measured gate report (기록된 산출물에서 재생성)"
python3 scripts/gen_loop_state_report.py 2>&1 || echo "(gen_loop_state_report failed — history absent?)"
echo

echo "## Disk"
df -h / | tail -1
echo

echo "## Disk guard (QAUTO-07 — raw bytes 3단계 판정, 매 회차 자동 기록)"
# 종료코드(0 GO/WARN·2 BLOCK·3 STOP)가 set -e로 수집기를 끝내지 않도록 흡수.
bash scripts/disk_guard.sh || true
echo
