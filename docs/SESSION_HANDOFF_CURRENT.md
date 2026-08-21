# 세션 핸드오프 — 현재 (2026-08-22)

> 마스터 프롬프트(`AGENT_MASTER_PROMPT_20260815.md`) 프로토콜 6번의 세션 종료 산출물.
> 이 파일은 **현재 인계 상태만** 유지한다. 직전 세션 59 전문은 `docs/archive/SESSION_HANDOFF_20260822_S59.md`에 보존한다.

## 2026-08-22 세션 60 — Phase 2 gap 재스캔 + G-28 Inc 2b

### 재스캔 결론
`DEVELOPMENT_DIRECTION_20260815.md`와 `EXECUTION_PLAN_PHASE2_20260819.md`를 현재 `main` 코드에 재대조했다. 2단계는 아직 DONE이 아니다.

G-28 계획은 ① EffectCostProfile/실측 → ② 브라우저 UI(검색·미리보기·즐겨찾기·파라미터) → ③ 템플릿 브라우저(G-19 확장) → ④ KPI 측정 하니스 순서다. 현재 코드는 ①과 ②의 검색/즐겨찾기/cost badge/background single-flight까지만 구현되어 있었고 다음 갭을 확인했다.

- 실제 before/after effect preview 없음
- 적용 전 parameter editor 없음
- browser apply가 모든 effect를 `Effect(type:, parameters: ["intensity": 0.5])`로 생성
  - brightness/contrast/saturation/temperature는 `amount`
  - exposure는 `ev`
  - blur는 `radius`
  - styleTransfer는 `styleIndex + intensity`
  를 renderer가 소비하므로 일부 browser card가 identity/no-op이 될 수 있음
- G-28 template browser surface 없음
- `EffectBrowserKPI` model/tests는 있으나 실제 search→preview→apply/reuse 측정 harness 없음

이 gap은 **Issue #16 `[P1] G-28 effect browser completion: preview, parameters, templates, KPI gate`**로 추적한다.

### 완료 — G-28 Inc 2b effect browser UI 완결
변경 세트: **PR #17 `feat(effects): complete G-28 browser preview controls`**.

#### Core
- `EffectBrowserCatalog` 신설
  - browser에서 노출할 built-in visual effect의 단일 metadata 계약
  - renderer-compatible parameter key/range/default/visible preview value 고정
  - neutral default와 실제로 차이가 보이는 preview start를 분리
  - override는 알려진 key만 허용하고 range clamp, 누락 key는 preview default로 보충
- transition(`fadeIn/fadeOut/crossDissolve`)은 전용 Transition inspector가 있으므로 grid 제외
- `externalLUT`는 파일 경로가 필요하므로 built-in preview grid 제외

#### Mac browser
- 카드 tap = 즉시 적용을 폐지하고 선택만 수행
- 오른쪽 detail pane에 **Original / Preview** thumbnail 추가
- preview는 `VisualEffectPixelProcessor`를 직접 사용해 preview/export와 같은 pixel implementation 소비
- effect별 slider를 Apply 전에 편집 가능
- `Apply to Clip` 버튼으로 draft parameter dictionary를 명시적으로 commit
- apply 시 sheet가 열린 시점의 `clip.effects`가 아니라 현재 `viewModel.selectedClip.effects`를 읽어 연속 적용에서 stale overwrite 방지
- 기존 cost profiling의 `Task.detached(priority: .utility)` process-wide single-flight는 유지

#### Tests
`EffectBrowserCatalogTests` 추가:
- preview grid가 실제 renderable built-in visual effects만 포함
- brightness=`amount`, exposure=`ev`, blur=`radius`, styleTransfer=`styleIndex+intensity` 계약 고정
- adjustment preview가 neutral 값에서 시작하지 않음
- default/preview 값이 UI range 내부
- unknown override 제거 + 누락값 보충 + clamp 동작

### 검증
구현 커밋: `fdcf8adf0e03fd925aa06264af6000415f399dcf`

PR CI #87 (`32503478653`):
- `build-and-test` ✅
  - Core build ✅
  - full Core tests ✅
  - Mac app build ✅
  - Mac unit tests(best-effort) ✅
  - generic iOS app build ✅
- `ios-tests` ✅
- `lint` ✅

따라서 Inc 2b의 코드/컴파일/회귀 게이트는 통과했다. 단, 이 수치는 G-28의 최종 사용자 작업 성공률 게이트가 아니다.

### 2단계 잔여
1. **G-28 Inc 3 — Template browser**
   - 기존 `BuiltinCardTemplates` / `CardTemplateGallery` / G-19 자산 재사용 감사부터 시작
   - searchable / previewable / favoritable / applyable flow를 effect browser와 정보구조 정합
2. **G-28 Inc 4 — KPI harness**
   - deterministic search → preview → apply/reuse scenario
   - search success / reuse 지표를 실제 UI/app path에서 수집
   - G-28 완료 게이트: discovery/apply 작업 성공률 **≥90%** 실측
3. 위 두 항목 완료 후에만 Phase-2 DONE 여부 재판정. 그 전 **G-29/HDR 진입 금지**.

### 병렬 사용자 의존 게이트
- **G-27 iOS 실기기 3종**: 최소/중간/최신 실제 iPhone. 러너/가이드 준비 완료.
- **접근 정규화 승인**: EditorViewModel 잔여 private 경계 정리를 위한 기존 선택 사항.
- N2 원클릭 오토스타일은 계획대로 사용자 등록 결정 전제.

### Git / tracking anchor
- baseline main before this increment: `54e9d3a8264e9abc4b5ad137ef43780d580f484e`
- implementation commit: `fdcf8adf0e03fd925aa06264af6000415f399dcf`
- change set: PR #17
- umbrella gap: Issue #16
