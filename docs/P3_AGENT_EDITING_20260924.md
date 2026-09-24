# P3 에이전트 편집 — 증분 기록·로드맵 (2026-09-24)

> 방향 확정: 사용자 "에이전트가 편집하도록 해줘야해"(2026-09-24) — Palmier 선점 축
> (`PALMIER_DETAILED_COMPARISON_20260924.md` §2)에 대한 MovieCut의 대응을 사전등록
> 계획(P3-01)대로 실행한다. **선점을 뒤집으려 하지 않고, 검증된 안전 계층+N1 직접
> 편집으로 응수**하는 원칙 유지(방향 문서 §1.6 사다리와 정합).

## 안전 계약 (모든 증분이 지켜야 하는 것)

1. **타입 경계**: 에이전트는 `EditingActionDSL.Action`(Codable 10종)만 발화 — 자유형
   타임라인 변이는 계층 어디에도 없음. 디코드는 fail-closed(알 수 없는 액션 = 거부).
2. **Fail-closed 스크립트**: 스크립트 전체를 사전 검증(커널 `plan()`) — 하나라도 무효면
   전체 거부, 부분 적용 없음.
3. **원자성**: 스크립트 = `EditingActionBatchCommand` 1회 dispatch = **undo 1단계**.
   배치는 드래프트에 적용 후 커밋(중간 실패 시 세션 무변경).
4. **오프라인**: 분석 액션(duckBackground·removeSilence)은 온디바이스
   `SpeechDuckingService`/`SilenceDetectionProvider` — 네트워크 계층 부재(MC-01/02/03).
5. **수정가능성 원칙**(COMPETITIVE_ANALYSIS §1.5): 적용 전 검증 가능·완전 undo —
   계층 구조가 원칙을 기계적으로 보장.

## 증분 1 — 커널 v1 (완료, a3c4942)

`EditingActionDSL`: 10액션·`PlanningError` 타입 거부·`validate()`·fail-closed decode.

## 증분 2 — 적용기 (완료, 2026-09-24 · 이 문서)

- `EditingActionBatchCommand`(Core) — 순차 적용 + 드래프트 커밋(all-or-nothing).
- `EditingActionApplier`(Core) — 검증→실명령 컴파일→단일 undo 적용.
  `ApplyReport(actionCount/commandCount/undoUnits=1)`. 분석 액션의 자산 해석
  (`clip.assetId`→`mediaLibrary`, 부재=`assetMissing` 타입 오류).
- 검증: `EditingActionApplierTests` 6종 — 실명령 매핑(AutoCut/SetVolume/
  SetClipSpeed/.equalizer 프리셋 밴드), 원자 적용+**undo 완전 복원**, fail-closed
  (무효 1개=전체 거부·세션 무변경), keepRange 역방향 컷, **실물 오디오 fixture로
  duckBackground 실분석→언덕 적용→undo 해제**, removeSilence 연속 톤=타입 거부.
- 계약 학습: `AutoCutCommand`는 **위치 보존(비-리플)** — `[2,6)` 제거 결과
  `[0,2)+[6,10)`, `Timeline.duration`은 콘텐츠 합이 아니라 **마지막 클립 끝**.
  (첫 테스트 기대치가 이를 잘못 가정해 프로브로 판명 후 계약에 맞게 수정 —
  테스트가 배운 것은 문서에 남긴다.)

## 증분 3 — 로컬 플래너 (다음)

텍스트 지시 → 액션 스크립트를 **오프라인 규칙 기반**으로 번역하는 계층.
- 입력: 한국어/영어 지시 문장 + 현재 프로젝트 스냅샷(클립 메타데이터·자막 카드).
- 출력: `[Action]`(반드시 DSL 경유) + 근거 1줄(설명가능성).
- LLM 경로는 **선택적 외부 플래너**로만: 사용자가 자신의 키/로컬 모델을 연결하는
  형태(앱 자체는 네트워크 0 유지 — 오프라인 원칙 준수). 기본 플래너는 로컬.

## 증분 4 — MCP 노출 (Mac 앱)

- 앱 실행 중 로컬 서버(127.0.0.1, Streamable HTTP·JSON-RPC) — 외부 의존성 없이
  표준 MCP 도구면 노출: `get_timeline`·`inspect_timeline`(읽기) +
  `apply_actions`(DSL JSON 검증→applier)·`validate_actions`(dry-run) 등.
- **쓰기는 전부 apply_actions 단일 관문** — 도구마다 변이 로직을 복제하지 않는다
  (Palmier의 도구당 실행기 구조와 대비되는 안전 계층 우선 설계).
- 캡션/전사 도구는 온디맨드 STT(N1 경로) 재사용. 생성 AI 도구는 비노출(비목표).

## 증분 5 — 승격 측정 (사전등록 기준, 변경 없음)

스크립티드 시나리오 100개(실 프로젝트 fixture)로:
- 플랜 유효성 ≥95% · 의도 일치 ≥90%(사람 판정 라벨) · 파괴-복구불가 0 ·
  **undo 회복 100%**(증분 2의 기계 축이 이미 상시 회귀로 잠금).
- 기준 미달 시 UI 노출 없음(현재와 동일).

## iOS

에이전트 편집은 Mac 우선(iOS defer 사유는 CA-20과 동일 — 데스크톱 중심 워크플로).
Core 계층(1~3증분)은 플랫폼 중립이라 이식은 노출 계층만 남는다.
