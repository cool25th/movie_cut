---
description: CapCut 대비 기능+UI 격차 재감사 — 코드 실사 기반으로 분석 문서/스펙 갱신 (개발 없음)
argument-hint: "(인자 없음 — 항상 전체 재감사)"
---

# CapCut 격차 재감사 세션 (기능 + UI)

CapCut 대비 격차를 **코드 실사 기반**으로 재도출하고, 분석 문서와 스펙을 갱신한다. **이 세션은 분석·문서 작업만 한다 — 기능 개발 금지.** 개발은 별도 세션(`/surpass`)이 스펙을 읽고 수행한다.

## 0. 이전 산출물 로드 (필수, 순서대로)

1. `docs/archive/CAPCUT_SURPASS_SPEC_20260703.md` — 현행 스펙(G-ID 기능 / U-ID UI). **스펙이 사실의 원천.**
2. **`docs/CAPCUT_BENCHMARK_STANDARD.md` — CapCut 수준의 명시적 기준(B-ID). 모든 비교 판정은 이 문서의 B-ID 기준 문장에 대해 ⬆/=/⬇/❌로 내린다.**
3. 최신 `docs/GAP_ANALYSIS_V*` (버전 번호 가장 높은 것) — 직전 통합 격차 분석.
4. `docs/CAPCUT_FEATURE_BACKLOG.md` §2.5 — 증거 기반 검증 현황.
5. `docs/UI_DESIGN_PRINCIPLES.md`, `docs/MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md` — UI 원칙·IA 계약 배경.
6. `git log --oneline` — 직전 분석의 기준 커밋 이후 델타 전부 확인.

## 1. 코드 실사 (문서 주장 검증 — 자가보고 신뢰 금지)

직전 분석 이후 커밋된 작업을 **실제 코드로 검증**한다. 최소 수행:

- 각 신규 커밋의 기능이 스펙 AC/검증 기록과 일치하는지 대조 (검증 기록 없는 커밋 = 부채로 기록).
- **dead code 스캔**: `Sources/MovieCutCore/`의 서비스/프로세서 중 `App/`에서 호출 0회인 것 grep (전례: EQ, VocalSeparation).
- **dead model field 스캔**: Core 모델의 public 필드 중 UI 미배선인 것 (전례: `Track.isLocked`).
- 스펙 G-ID/U-ID별 상태 재판정: 미착수 / 진행중(Inc 어디까지) / 완료(증거 링크). 스펙의 검증 기록 줄과 git log 대조.
- UI 실사: 주요 표면 파일(`ContentView`, `TimelineView`, `MediaLibraryPanel`, `InspectorPanel`, `MovieCutMacApp`)에서 직전 분석의 격차 항목이 해소됐는지 grep으로 확인.

## 2. CapCut 대비 재비교 (기능 + UI)

- **기준: `CAPCUT_BENCHMARK_STANDARD.md`의 B-ID가 판정 단위다.** §7 채점 시트를 복사해 갱신하고 신규 분석 문서에 첨부한다. 판정 변화(⬇→= 등)는 반드시 증거와 함께.
- 이전 분석의 비교표(1-A 능가 / 1-B 검증부채 / 1-C 열위)는 B-ID 채점의 요약 뷰로 유지·갱신한다.
- 새 격차 발견 시 근거(파일:라인 또는 grep 결과) 필수. **[추정] 표기 B-ID로 ⬇/❌ 판정 시 웹 검색으로 CapCut 실동작을 먼저 확인하고 벤치마크 문서를 [확인]으로 승격(출처 병기).** CapCut에 신기능이 보이면 벤치마크에 B-ID 추가 + 버전 bump.
- **능가 기회**(CapCut이 구조적으로 못 하는 것 — 온디바이스/오프라인/Pro 출력/macOS 네이티브)도 함께 갱신.

## 3. 산출물 (전부 이 세션에서 작성·커밋)

1. **신규 분석 문서** `docs/GAP_ANALYSIS_V<N+1>_FUNC_UI_<YYYYMMDD>.md` (오늘 날짜, 직전 버전+1):
   - 델타 요약(직전 분석 이후 커밋·판정 변화) / 3분류 현황(능가·부채·열위) / 기능 G-ID 현황판 / UI 격차표(실사 근거 포함) / 개선 방향성 / 신규·변경 항목 요약 / 권장 실행 순서(병행 슬롯).
2. **스펙 갱신** `archive/CAPCUT_SURPASS_SPEC_20260703.md`:
   - 버전 bump + 변경 이력 1줄. 상태 변화 반영(완료 항목 검증 기록, 진행중 표시).
   - 신규 격차는 새 G-ID/U-ID로 **상세 명세 추가**(요구사항/현재 상태 실사/데이터 모델/구현 증분(파일 수준)/측정 가능한 AC/검증 계획/리스크 — 기존 항목과 같은 밀도).
   - 무효화된 항목은 삭제하지 말고 취소선+사유.
3. **백로그 갱신**: `CAPCUT_FEATURE_BACKLOG.md`에 재판정 반영.
4. **커맨드 갱신**: 신규 ID가 생겼으면 `.claude/commands/surpass.md` 인자 안내 확인.
5. **커밋**: `docs: ...` conventional commit, attribution 없음.

## 4. 규율

- 판정은 증거로만: 코드 존재 ≠ 완료. "preview+export 반영 + 증거(골든/E2E/캡처)"가 기준.
- static contract는 회귀 잠금 전용 — 완료 증거 불인정.
- 이미 잠긴 UI 계약(IA 패스 등)을 "격차"로 재보고하지 말 것 — 지킬 목록(1-A)으로 관리.
- 빌드/테스트 실행은 실사 목적(현상 확인)으로만 — 코드 수정 금지. 회귀 발견 시 고치지 말고 분석 문서에 P0 부채로 기록.
- 분석 완료 후 최종 보고: 핵심 변화 3줄 + 최우선 착수 항목 1개 추천.
