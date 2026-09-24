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

## 증분 3 — 로컬 플래너 v1 (완료, 2026-09-24)

`EditingIntentPlanner`(Core) — 오프라인 규칙 기반 지시 번역: 한국어/영어 지시 →
타입 액션 + 근거(대상 클립 명시). LLM·네트워크 부재(오프라인 원칙 그대로).

- **문법 v1(8의도)**: split(단일 시각)·범위 삭제/keep-only(양쪽 시간 리터럴)·
  volume(절반/%/소수)·speed(배속/%)·EQ 프리셋 4종·duckBackground·removeSilence.
- **시간 리터럴 계약**: 단위 필수("초/s"·"분/m", 복합 "1분 30초"=90) — 맨숫자는
  피연산자 이름공간(볼륨/배속/서수)이지 시간이 아님. 첫 구현이 분→초 환산 누락
  (1분30초→31)을 복합 시간 테스트가 적발·수리.
- **대상 지정 계약**: 서수는 타임라인 순 1-base("첫/first"·"마지막/last"·"N번째"·
  "Nth"·"clip N" — **마커에 붙은 숫자만**, 피연산자 숫자와 충돌 없음). 무지정 시
  기본 대상 = 최장 클립(가장 덜 놀라운 대상)·근거에 서수 명시(§1.5 미리보기 원칙).
- **Fail-closed**: 무지시·시간 부족·서수 초과는 전부 타입 오류(unrecognized/
  noTime/clipOrdinal/noClips) — 파괴적 추측 없음("삭제해줘"만으로 절대 삭제 안 함).
- 검증: `EditingIntentPlannerTests` 6종(양언어 매핑·서수≠피연산자·복합 시간·
  fail-closed 4형태·**플래너→적용기 종단 연결** — 원자 undo·위치 보존 결과 검증).

잔여: 증분 4 MCP 노출(엔타이틀먼트 결정 필요 — 하단)·증분 5 승격 측정.

### 증분 4 사전 결정 필요 — 로컬 서버 엔타이틀먼트

MCP 노출(HTTP 127.0.0.1)은 샌드박스 `com.apple.security.network.server`를 요구 —
현재 Mac entitlements는 네트워크 키 전면 부재(오프라인 실증 MC-01의 전제).
외부 전송은 없지만(localhost 수신) 보안 표면·대외 문구 검토 필요. 대안:
(a) 서버 엔타이틀먼트 추가(기본 off 토글·127.0.0.1 전용·토큰 핸드셰이크) —
Palmier 방식과 동일 수준, (b) 파일 교환 폴더 감시(엔타이틀먼트 0 유지, MCP
프로토콜은 아니 됨), (c) CLI 하니스로 Core 직접 구동(앱 외, OC-02 패턴 확장).
**사용자 결정 대기** — 결정 전 앱 코드 불변.
