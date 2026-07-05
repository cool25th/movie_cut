# MovieCut vs CapCut 갭 분석 V11 — 기능 + UI 재감사 — 2026-07-05

> 작성일: 2026-07-05 / 브랜치: `feat/core-backend-expansion` (기준 커밋: `6f76415`)
> 기준선: V10 `docs/GAP_ANALYSIS_V10_FUNC_UI_20260705.md` (`fe8f8f5`) / 재평가 대상: `fe8f8f5..6f76415`
> 원천 스펙: `docs/CAPCUT_SURPASS_SPEC_20260703.md` v1.5
> 규칙: 코드 존재 ≠ 완료. 완료 = preview/export/iOS 반영 + 증거. static contract는 회귀 잠금 전용.
> 이 감사의 실측: `swift build` PASS, `swift test --filter 'ColorGrade|StaticContract|Golden|StyledCaption'` **353 tests / 84 suites PASS**(Color Grade Golden 스위트 포함), dead-code/dead-value/UI 표면 grep 전수 재실행.

---

## 0. 한 줄 요약

V10의 권장 순서가 **그대로 실행·완료됐다**: G-12 #9 챕터 마커(ffprobe 실측) 상환으로 **10/14**, 이어 **G-02 Inc 3 HSL/커브 렌더 체이닝**이 preview/export/iOS에 실반영됐다. 이로써 V7부터 지적된 **"Pro 포지셔닝인데 색 2차 보정이 CapCut보다 얕다"는 모순이 엔진 수준에서 해소** — 남은 것은 커브/HSL 편집기 UI(Inc 5~6)다. dead-value 4계열 중 3계열(CurveEvaluator·HSLCubeBuilder·CurvePoint/HSLBand)이 상환됐고 `wordTimings`만 남았다. **UI 트랙은 4회 연속 감사에서 착수 0건** — v1.4 게이트상 다음 자동 선택은 **U-08**이며 이번에는 반드시 집행되어야 한다.

---

## 1. V10 이후 델타와 독립 검증

| 커밋 | 내용 | V11 독립 검증 결과 |
|---|---|---|
| `f7690fa` | G-12 #9 챕터/비트 마커 메타데이터 export | ✅ — ExportEngine이 AssetWriter timed metadata track + `.chapterList` association으로 실제 chapter atom 기록. E2E 훅(`MOVIECUT_UITEST_CHAPTER_MARKERS`/`BEAT_CHAPTERS`) + ffprobe 실측 `count=3 starts=0.25,0.75,1.25` 스크립트 실재(`run_e2e_export.sh:512-521`). Caveat 정직 기록(ffprobe title tag 빈 문자열 → 하니스 status로 보완) |
| `6f76415` | **G-02 Inc 3 — HSL/커브 색 그레이드 체이닝** | ✅ — `ColorGrade.hslBands`/`curves` optional 편입(A5 디코딩 포함, `ColorGrade.swift:38-41`), `ColorGradePixelProcessor.apply`가 CDL→HSL `CIColorCube`→curve cube 체이닝(`:37-44`, cube 캐시 키), Mac Inspector/iOS 인스펙터 re-init 경로가 새 필드 보존(`InspectorEffectsSection.swift:227-240`, `IOSEffectsInspectorView.swift:421`), 골든 확장 + E2E `G-02 HSL/curve grade reflected in export`(base_rgb 5,1,0 → grade_rgb 5,5,5). **Caveat: 편집기 UI(커브 캔버스/HSL 밴드 패널)는 Inc 5~6 잔여 — 현재 사용자가 HSL/커브 값을 만들 수단이 없다(필드 보존만)** |

- 빌드/테스트: build PASS, 353/84 PASS — 회귀 없음. 스펙 검증 기록(§G-02, §G-12)과 코드가 정합.

## 2. dead-code / dead-value 재스캔 (2026-07-05 V11)

| 대상 | App 참조 | V10 → V11 | 상환처 |
|---|---|---|---|
| `CurveEvaluator` / `HSLCubeBuilder` / `CurvePoint`·`HSLBand` | 프로세서 소비 | 🟡 dead-value → **✅ 상환** (`6f76415`) | 완료 |
| `TextClipContent.wordTimings` | **0** | 🟡 dead-value 지속 | G-01 Inc 2 (게이트상 U-08 다음) |
| `VocalSeparationService` | **0** | ❌ dead code 지속 (4회 연속) | G-05 Inc 1~3 |
| `StyleTransferProvider` | **0** | ❌ dead code 지속 | 폐기 또는 G-07 흡수 — **결정 필요로 승격** |

A6 보강 규칙이 첫 사이클에서 작동했다(등재 → 다음 마일스톤 전환 시 상환). `VocalSeparationService`/`StyleTransferProvider`는 등재만 4회째 — G-05 착수 전이라도 **StyleTransferProvider는 폐기 여부를 다음 감사 전에 결정**할 것을 권고.

## 3. 3분류 변동 (V10 대비)

- **2-A 능가/후보 (승격 1건)**: **색 그레이딩 엔진** — 3-way CDL+휠+스코프 3종(기존 우위)에 HSL 8밴드+4채널 커브가 실반영으로 합류. 엔진 기준 CapCut 데스크톱 HSL/커브와 **파리티 이상**(스코프 연동은 CapCut 불가). 단 편집기 UI 부재로 "사용자 체감 능가" 선언은 Inc 5~6 + W5 완주 후.
- **2-B 검증부채**: G-12 잔여 4건 — #11a/b·#12a/b(fixture 선행), #13/#14(수동 대기). 자동 상환 가능분은 소진됨.
- **2-C 열위 (변동)**: "색보정 열위" 항목이 "편집기 UI 잔여"로 축소. 나머지 열위 축 유지 — 캡션 렌더(wordTimings 미소비), 타임라인 표면(전환 pill/뱃지/필름스트립), 오디오(보컬분리/FX), iOS 본대(defer 15건), **제품 UI 표면 전부(홈/토스트/설정/현지화/팔레트/UI 회귀 인프라 — 4회 연속 0건)**.

## 4. G-ID / U-ID 현황판 (V11)

| ID | 상태 | 변동 |
|---|---|---|
| G-12 | 🟡 **10/14** | #9 상환. 자동 상환 가능분 소진 — 잔여는 fixture 증분(#11a/#12a)과 수동 대기(#13/#14) |
| G-02 | 🟡 **Inc 1~3 완료** | 체이닝+골든+E2E 완료. **잔여: Inc 5(커브 에디터 UI)·Inc 6(HSL 패널 UI)·iOS 시트, W5 완주** |
| G-01 | 🟡 Inc 1 | 변동 없음 — wordTimings dead-value 지속 |
| G-09 | 🟡 Inc 1~2 | 변동 없음 (CI job·iOS E2E·defer 15건) |
| G-05 | 🟡 부분 | 보컬분리 dead code 4회 연속 |
| G-03/04/06/07/08/10/11 | ❌ | 변동 없음 |
| G-13/14 | 합의 대기 | 변동 없음 |
| U-01~U-09 | **전부 V10 판정 유지** | **UI 트랙 4회 연속 착수 0건 — 게이트상 다음 자동 = U-08** |

## 5. 개선 방향성 (V11)

1. **U-08을 이번 사이클에 강제 집행** — v1.4 게이트의 다음 자동 항목이다. UI 회귀 인프라(populated 캡처·골든 스크린샷·클릭수) 없이는 이후 모든 U-ID와 G-02 Inc 5~6 UI 작업이 "완료 증거 없음" 상태로 쌓인다. 4회 연속 미착수가 이 문서의 최대 경고.
2. **G-02 Inc 5~6 (커브 에디터 + HSL 패널 UI)** — U-08 직후. 엔진이 끝났으므로 UI만 붙이면 **W5(Pro 그레이딩 워크플로우) 완주 = 첫 "체감 능가" 선언 후보**. 스코프+휠+커브+HSL 통합 패널은 CapCut이 구조적으로 못 만드는 표면.
3. **G-01 Inc 2~4 (캡션 렌더러+갤러리)** — 마지막 dead-value(wordTimings) 상환 + 숏폼 최대 체감 격차 공략.
4. **수동 검증 2건은 사용자 개입 필요** — #13(iCloud 2기기)/#14(Photos 드래그)는 자동 세션이 절차 문서만 준비 가능. 절차가 준비되면 사용자 실기기 세션 1회를 요청할 것.
5. **StyleTransferProvider 거취 결정** — 폐기(권고: G-07 이펙트 팩이 스타일 프리셋을 대체) 또는 G-07 플러그인 흡수. 방치 시 감사마다 노이즈.

## 6. 권장 실행 순서

| 슬롯 | 작업 | 근거 |
|---|---|---|
| 1 | **U-08** UI 회귀/지표 인프라 | 게이트상 다음 자동 항목, 4회 연속 미착수 해소 |
| 2 | **G-02 Inc 5~6** 커브/HSL 편집기 UI (+iOS 시트) → **W5 완주 녹화** | 첫 체감 능가 워크플로우 |
| 3 | G-01 Inc 2~4 캡션 스타일+렌더러+갤러리 | wordTimings 상환 + 숏폼 격차 |
| 4 | U-02 + G-04 타임라인 표면+필름스트립 | 체감 완성도 |
| 5 | G-12 #11a/#12a fixture 제작 → #11b/#12b 측정 | 병행 슬롯 |
| 병행 | #13/#14 수동 절차 문서 → 사용자 실기기 세션 요청 | 자동 불가분 |

## 7. 실사 증거 요약

- 델타: `git log fe8f8f5..6f76415` 2커밋, 각각 스펙 검증 기록·E2E 스크립트·골든과 대조 일치.
- dead 스캔: VocalSeparationService=0, StyleTransferProvider=0, wordTimings 소비 0 / CurveEvaluator·HSLCubeBuilder는 `ColorGradePixelProcessor` 소비 확인.
- UI 표면: HomeView/RecentProjects/ToastCenter/CommandPalette/Settings scene/xcstrings/CurveEditorView 전부 grep 0건.
- 빌드·테스트: build PASS, 353 tests/84 suites PASS (2026-07-05).
