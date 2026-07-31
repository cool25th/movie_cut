# 검증 신뢰도 부채 정리 — 작업 8.1 / 8.2 / 8.3 / 8.4 판정 기록

요구사항 15 / `tasks.md` §8 대응. 모든 수치는 이 세션에서 직접 실행한 명령의 출력이다.

- 측정 시각: 2026-07-31 (작업 8 세션)
- HEAD 기준: 작업 0.2~7 의 미커밋 변경 위에서 착수 (이 세션이 커밋하지 않음)
- swiftlint: 0.65.0 (`/opt/homebrew/bin/swiftlint`)

---

## 0. 착수 전후 지표 (직접 실행 `swift test`)

| 지표 | 착수 전 (8.1 직전) | 8.1 후 | 8.2 후 | 8.3 후 (최종) |
|---|---|---|---|---|
| 테스트 수 | **1176** | 1140 | 1139 | **1148** |
| 스위트 수 | 180 | 180 | 180 | **181** |
| 실패 | 0 | 0 | 0 | **0** |
| `swift test` RC | 0 | 0 | 0 | **0** |

- 8.1 감소(−36): docs/ 산문 단언 `@Test` 함수 43건 whole + 1건 부분(트림) 제거. swift-testing의 테스트 수는 `@Test` 함수 단위이며, 파라미터화 테스트 1개가 다중 케이스로 집계되던 차이로 함수 제거 건수(44)와 테스트 감소(36)가 정확히 일치하지 않는다 — 둘 다 실측값이다.
- 8.2 감소(−1): `Phase04/timelineViewDoesNotCallAISmartToolActions` 전체 함수 제거. `Phase23/timelineViewRemainsEditOnlyWithoutSmartOrQuickToolsActions` 는 narrowing(QuickToolsPanel 경계 단언만 잔존, 테스트 1건 유지).
- 8.3 증가(+9, +1 스위트): 신규 `RenderProcessorGoldenTests` 9건.

`swift build` 도 종료 0, warning 0 (캐시 히트 제외).

---

## 1. 작업 8.1 — docs/ 산문 단언 테스트 제거

### 1.1 판정 원칙

1. **`@Test` 함수 단위로 제거.** 파일 단위 삭제는 `P3DocsCleanupStaticContractTests.swift` 1건만 — 이 파일의 5개 함수 전체가 docs/ 산문 단언이었기 때문.
2. 동작 단언(코드/Sources 를 읽는)과 섞인 함수는 **부분 제거** 1건만(`IOSParityMatrixStaticContractTests.iosCompositorAuditMatchesCurrentCodeShape` — iOS compositor 배선 단언은 보존하고 docs/PLATFORM_PARITY_MATRIX 읽기와 그 3개 단언만 제거).
3. 제거 전 전수 대상 docs/ 8개가 아직 유효한지 확인 → **전부 live**(다른 docs/ 와 scripts/ 에서 교차 참조됨). 요구사항 16 이 별도 추적하므로 여기서 폐기 대상 추가 없음.

### 1.2 제거 일람 (44개 `@Test` 함수)

whole-removal 43건 + 부분 1건. 전체 파일은 `git diff --name-only -- Tests/` 로 확인 가능. 건별 한 줄 근거 패턴:

| 분류 | 건수 | 대상 docs | 근거 (한 줄) |
|---|---|---|---|
| backlog/handoff 완료 표시 단언 | 17 | `CAPCUT_FEATURE_BACKLOG.md`, `SESSION_HANDOFF.md` | "F-06/F-05/voiceover/text-style/fade/magnetic/speed-ramp 등이 backlog 에 완료로 표시됐는지" 검사 — 문서 오타가 테스트를 깸 (의존 역전) |
| parity row ✅ 표시 단언 | 14 | `CAPCUT_UI_PARITY_REQUIREMENTS.md` | "R1-03/R3-03/R4-0x/R5-0x 행이 ✅ 구현 문자열을 담는지" — 산문 trivia |
| showcase/audit 마커 단언 | 8 | `CAPCUT_UI_SHOWCASE_HANDOFF.md`, `MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md` | "Phase 0-N implemented / Loop 6 metric" 마커 존재 검사 — 산문 trivia |
| P3 docs cleanup 전체 | 5 | 4개 docs | `P3DocsCleanupStaticContractTests.swift` 파일 전체가 문서 산문 단언 (파일 삭제) |
| UIUX_HANDOFF 소스가드 표시 | 1 | `UIUX_HANDOFF.md` | "UX-08 source-level guard" 문구 존재 — 산문 trivia |

전체 함수명 목록은 `git diff` 의 삭제 라인(`@Test`/`func `)으로 재현 가능.

### 1.3 산 문서 거처 (cleanup flag)

`docs/CAPCUT_UI_PARITY_REQUIREMENTS.md`, `CAPCUT_UI_SHOWCASE_HANDOFF.md`, `UIUX_HANDOFF.md`, `MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md`, `CAPCUT_FEATURE_BACKLOG.md`, `SESSION_HANDOFF.md`, `CAPCUT_PARITY_SPEC.md`, `PLATFORM_PARITY_MATRIX.md` — **8개 전부 live**. 테스트 제거로 고립되는 것 없음. 폐기 판정은 요구사항 16 범위.

---

## 2. 작업 8.2 — 부정 단언 전수 분류

전수 대상: `#expect(!…)` 형태 **196건** (StaticContract + 일반 테스트). 분류 결과:

| 분류 | 건수 |处置 |
|---|---|---|
| **경계 방향** (boundary-direction) — 계층 침투/제거 회귀 방지 | **152** | KEEP (이유: 아래) |
| **결함 고정** (defect-pinning) — 기능 부재를 잠금 | **2 함수(13 단언) + 2 narrowing** | REMOVE/NARROW |
| **애매** → KEEP 으로 기울임 | **42** | KEEP |

### 2.1 제거/축소한 결함 고정 (유일하게 손댄 것)

| 위치 | 단언 | 판정 | 근거 |
|---|---|---|---|
| `Phase04TimelineEditToolbarStaticContractTests.timelineViewDoesNotCallAISmartToolActions` (전체 함수, 13개 `!contains`) | `runAutoCutOnSelection`/`detectBeats`/`autoReframeSelection`/`applyNoiseReductionToSelection`/`extractAudioFromSelection`/`Auto Cut`/`Detect Beats`/… 가 TimelineView 에 없어야 한다 | **REMOVE (전체 함수)** | AI Smart tool 의 TimelineView 배선을 능동 차단 → 요구사항 9(보컬 분리)/10(provider 배선) CapCut 파리티 작업을 막는 결함 고정. 편집 툴바 범위 경계는 `editToolbarExposesOnlyRequestedEditActions` 가 여전히 지킴. |
| `Phase23TimelineToolbarIconOnlyStaticContractTests.timelineViewRemainsEditOnlyWithoutSmartOrQuickToolsActions` (7개 루프) | 동일 + `QuickToolsPanel` | **NARROW** | `QuickToolsPanel` 제거 회귀 방지는 boundary(KEEP) 하되, AI Smart tool 항목은 결함 고정이므로 제거. 함수명을 `timelineViewRemainsFreeOfTheRemovedQuickToolsPanel` 로 변경하고 단언 1건만 잔존. |

### 2.2 경계 방향(KEEP)의 대표 패턴 (152건)

| 패턴 | 예 | KEEP 근거 |
|---|---|---|
| presentation-only 경계 | `R301R302`/`R305`: `!surface.contains("updateCanvas("/"updateExportSettings("/"exportEngine"/"playbackEngine."/"viewModel.")` | UI 계층이 Core engine 직접 호출 금지 (계층 침투 방지) |
| Command 경유 강제 | `R502`/`R503`: `!helper.contains("EditorSession"/"Command")`, `!methods.contains("session.dispatch")` | 발표층에서 직접 dispatch 금지 |
| inspector 섹션 라우팅 | `R401`/`R402`: audio branch 가 `InspectorEffectsSection`/`Picker("Inspector section"`) 미포함 | clip kind별 섹션 분기 경계 |
| inline 재구현 금지 (파리티 핵심) | `ChromaKey`/`VisualEffect`/`ColorCorrection`: `!source.contains("private func apply…")` | 공유 프로세서 경유 강제 → 요구사항 12(iOS 공유 프로세서 전환)의 전제. inline 재구현이 돌아오면 골든 픽셀 테스트가 무의미해짐 |
| iOS divergent formula 금지 | `IOSColorCorrectionParity`: `!preview.contains("6500 + colorCorrection.warmth")` | macOS↔iOS 출력 분기 방지 |
| 제거 회귀 가드 | `!source.contains("QuickToolsPanel"/"libraryTabBar"/"Smart tools move here next."/"StickerPickerView"/"EmptyInspectorSelectionView")` | 한번 제거한 컴포넌트 재도입 방지 |
| 테마 토큰 회귀 가드 | `Phase13`/`Phase14`/`R601`: 구 색상 리터럴 미포함 | 다크 셸 토큰 정책 고정 |
| 동작 단언(부정형) | `FilmstripPlanning.rejectsStaleResults`, `CloudConflict.noConflictNoBackup`, `WaveformRequestKey.hashableForTaskIdentity`, `ExportPlanner.hdrProfileFlags` | 진짜 동작 검증 (산문/문자열 아님) — 분류 대상 아님, KEEP 자명 |

### 2.3 애매(42건) → KEEP 으로 기울임

`KeyboardShortcut` 의 `keyboardShortcut("b"/"m")`, `Phase12` 의 `.movieCutCard(...)`, `R501` 의 `ReverseClipCommand`/`FreezeFrameCommand` 참조 부재, `Phase21`/`Phase22` 의 `forbidden` 루프 등. 제거 회귀 가드 또는 presentation-only 경계로 **해석 가능**하여 스펙 원칙("애매하면 KEEP")을 따라 손대지 않음.

---

## 3. 작업 8.3 — 렌더 프로세서 문자열 단언 → 골든 픽셀 승격

### 3.1 승격 대응표

문자열 "is wired" 단언(StaticContract)과 골든 픽셀 테스트의 대응. 새 파일 `Tests/MovieCutCoreTests/RenderProcessorGoldenTests.swift` 추가.

| 프로세서 | 문자열 단언 위치 | 골든 픽셀 테스트 | 상태 |
|---|---|---|---|
| `BlendPixelProcessor` | (기존) | `BlendPixelProcessorGoldenTests` (7 모드) | 기존 골든 있음 — 승격 불필요 |
| `ColorCorrectionPixelProcessor` | `ColorCorrectionPixelProcessorTests:145`, `IOSColorCorrectionParity:18,24` | `ColorCorrectionGoldenTests` (8) | 기존 골든 있음 |
| `ColorGradePixelProcessor` | `ColorGradeExportWiringStaticContract:17`, `ColorScopeWiringStaticContract:19`, `IOSColorGradeParity:18,32` | `ColorGradeGoldenTests` (8) | 기존 골든 있음 |
| `PersonSegmentationCompositor` | `BackgroundRemovalTests:141` | `BackgroundRemovalGoldenTests` (2) | 기존 골든 있음 |
| **`TransitionPixelProcessor`** | `TransitionPixelProcessorTests:427` | **`RenderProcessorGoldenTests`: crossDissolveMidpoint… / fadeThroughBlack…** | **신규 승격 (2)** |
| **`VisualEffectPixelProcessor`** | `VisualEffectPixelProcessorTests:148` | **`RenderProcessorGoldenTests`: sepiaEffect… / grayscaleEffect…** | **신규 승격 (2)** |
| **`CanvasBackgroundPixelProcessor`** | `CanvasBackgroundTests:211,226` | **`RenderProcessorGoldenTests`: solidColorBackground…** | **신규 승격 (1)** |
| **`MaskPixelProcessor`** | `MaskPixelProcessorTests:154,161` | **`RenderProcessorGoldenTests`: rectangleMask… / invertedRectangleMask…** | **신규 승격 (2)** |
| **`ChromaKeyPixelProcessor`** | `ChromaKeyPixelProcessorTests:137,138,147,148` | **`RenderProcessorGoldenTests`: chromaKeyRemoves… / chromaKeyLeaves…** | **신규 승격 (2)** |
| `TextOverlayPixelProcessor` | `TextOverlayPixelProcessorTests:432,439` | — | **미승격(사유 기록)**: 텍스트 렌더링은 폰트 힌팅·서브픽셀 처리가 기기별로 비결정적이라 고정 골든 값이 불안정. 골든 척도(채널당 ±2)로 신뢰할 수 없음. 기존 `TextOverlayPixelProcessorTests` 의 동작 단언이 폰트 무관 경로(karaoke 색상 적용 등)를 이미 커버. |

신규 골든: **9건, 1 스위트**. 전원 `GoldenPixel.assertRendererFunctional()` 를 최상단에서 호출.

### 3.2 "실제로 실행됐음(skip 아님)" 증거

직접 실행 `swift test --filter "RenderProcessorGoldenTests"`:

```
◇ Suite "Render Processor Golden" started.
◇ Test "chroma key removes a pixel that matches the key color" started.
…
✔ Test "chroma key removes a pixel that matches the key color" passed after 0.069 seconds.
✔ Test "chroma key leaves a non-matching pixel at the golden source" passed after 0.070 seconds.
✔ Test "cross dissolve at the midpoint blends both sources toward the golden" passed after 0.077 seconds.
✔ Test "fade through black reaches pure black at the midpoint" passed after 0.066 seconds.
✔ Test "grayscale effect collapses a saturated source to the golden luma" passed after 0.066 seconds.
✔ Test "inverted rectangle mask makes the covered pixel fully transparent" passed after 0.068 seconds.
✔ Test "rectangle mask keeps the covered pixel opaque at the golden source" passed after 0.071 seconds.
✔ Test "sepia effect maps a saturated source to the golden warm tone" passed after 0.065 seconds.
✔ Test "solid color background fills the canvas with the exact hex value" passed after 0.075 seconds.
✔ Suite "Render Processor Golden" passed after 0.077 seconds.
✔ Test run with 9 tests in 1 suite passed after 0.078 seconds.
```

- chroma key 골든이 `RGBA(0,0,0,0)` 으로 통과한 것은 **`CIColorKernel` 이 실제 로드·실행됐음**의 증거. 커널이 로드 실패하면 프로세서가 입력을 그대로 반환해 `RGBA(0,230,0,255)` 가 돼 단언이 실패한다.
- 렌더러가 동작하지 않으면 `assertRendererFunctional()` 의 mid-gray sentinel 단언이 loudly fail 한다 (silent skip 경로 없음).

### 3.3 문자열 단언 처리 결정

골든 승격 후에도 기존 문자열 "is wired" 단언을 **제거하지 않음**. 이유: 그 단언들은 "공유 프로세서가 호출되는가"(배선/파리티 경계, 요구사항 12 전제)를 검사하고, 골든은 "픽셀이 맞는가"를 검사 — 직교하는 두 가지. 단, `MaskStaticContractTests`(`MaskPixelProcessorTests.swift:144-181`) 처럼 문자열 단언만으로 구성된 struct 는 골든이 픽셀을 커버하므로 향후 정리 후보(이번 범위 밖).

---

## 4. 작업 8.4 — 린트 게이트 판단

### 4.1 현황 (측정)

| 위치 | 동작 | 차단 여부 |
|---|---|---|
| `.swiftlint.yml` | 식별자/길이/본문길이 등 규칙 정의 | — |
| `scripts/lint.sh` | `swiftlint lint --strict` 후 build+test | strict 지정이나 swiftlint 미설치 시 silent skip |
| `.github/workflows/ci.yml` `lint` job | `swiftlint lint … \|\| true`, `if: always()` | **비차단** ("~1,000 existing findings" 주석) |

### 4.2 규칙별 분해 (직접 실행 `swiftlint lint .`)

착수 시점 총 **1219 위반 (error 528 / warning 691)**.

**ERROR by rule (착수 시점):**

| 규칙 | error 수 | 게이트 판정 |
|---|---|---|
| `identifier_name` | 436 | **완화** (§4.3) |
| `line_length` | 17 | 보류 (style) |
| `function_body_length` | 14 | 보류 (style) |
| `force_try` | 12 | **게이트 대상** (§4.4) |
| `type_body_length` | 11 | 보류 (style) |
| `file_length` | 11 | 보류 (style) |
| `large_tuple` | 8 | 보류 |
| `force_cast` | 8 | **게이트 대상** (§4.4) |
| `cyclomatic_complexity` | 5 | 보류 |
| `shorthand_operator` | 4 | **게이트 대상** (§4.4) |
| `empty_count` | 2 | 보류 |

### 4.3 완화 결정 — `identifier_name` (정당한 사유 기록)

436 error 의 ~99% 가 1글자 루프/DSP/픽셀 변수 — `r`,`g`,`b`,`a`(색 채널), `x`,`y`(좌표), `i`,`t`(루프/시간). 미디어 처리 코드에서 이 이름이 **가독성 정답**. 기본 `min_length: 3` 은 이 코드베이스에 역보정이며 `redChannel`/`greenChannel` 강제는 오히려 픽셀 수학 가독성을 해친다.

**처置:** `.swiftlint.yml` 에서 `identifier_name.min_length.error/warning: 1` 로 완화 (규칙 끄기 아님 — `max_length` 40 초과 등 진짜 오명은 여전히 flag). 결과: **error 528 → 95** (−83%), 총 위반 1219 → 692. 잔존 `identifier_name` error 는 3건(40자 초과 실제 오명).

### 4.4 게이트 전환 결정 — high-signal allow-list

`force_cast`/`force_try`/`shorthand_operator` error 는 개수가 적고(각 8/12/4 = 24) **충돌/정확성 리스크**를 의미하므로 CI 차단으로 전환 가능. 신규 `scripts/lint_gate.sh` 가 이 3규칙의 error 만 허용목록 게이트로 검사.

- `force_unwrapping`(241, opt-in)은 개수가 많아 **전환 불가** — 현 시점 게이트하면 모든 PR 차단. 별도 baseline 정리 후 편입(기록).
- `line_length`/`function_body_length`/`file_length` 등 style 규칙은 error 라도 차단하면 PR 단위 작업이 좌절되므로 **스타일 보류**(단, 신규 코드에서는 `lint.sh --strict` 가 로컬에서 여전히 잡는다).

**현재 상태:** allow-list 게이트는 baseline 24건이 남아 있어 `--report` 모드로 측정용 운용. 24건 정리(대부분 테스트 픽스처의 `as!`/`try!` → 안전 언래핑) 후 `ci.yml` 의 `lint` step 을 `scripts/lint_gate.sh` 호출 + `continue-on-error` 제거로 차단 전환 가능. 게이트 스크립트 자체는 완성됐고 종료코드 0/1 을 정확히 반환한다(아래).

### 4.5 게이트 검증 (직접 실행)

```
$ scripts/lint_gate.sh --report
lint_gate: FAIL (24 allow-list violation(s) for rules: force_cast,force_try,shorthand_operator)
… (24건 위치 출력) …
lint_gate: --report mode, not failing the build.   rc=0
```

위반 0인 경우 `lint_gate: PASS (0 …)` + rc=0 반환 (스크립트 내 분기 확인됨).

---

## 5. 파일 변경 요약 (이 세션)

**신규:**
- `Tests/MovieCutCoreTests/RenderProcessorGoldenTests.swift` (8.3, 9 테스트)
- `scripts/lint_gate.sh` (8.4, 실행가능)

**수정:**
- `.swiftlint.yml` (8.4, identifier_name 완화 + 사유 주석)
- `Tests/MovieCutCoreTests/IOSParityMatrixStaticContractTests.swift` (8.1 부분 제거)
- `Tests/MovieCutCoreTests/Phase04TimelineEditToolbarStaticContractTests.swift` (8.2 함수 제거)
- `Tests/MovieCutCoreTests/Phase23TimelineToolbarIconOnlyStaticContractTests.swift` (8.2 narrowing)
- 8.1 whole-removal 대상 StaticContract 파일 37건 (docs 산문 `@Test` 함수 1개씩 제거)

**삭제:**
- `Tests/MovieCutCoreTests/P3DocsCleanupStaticContractTests.swift` (8.1, 전체가 산문 단언)

**손대지 않음 (스펙 제약 준수):** `EditorViewModel.swift`, `project.pbxproj`, `tasks.md`, 네트워크 entitlement. `xcodegen` 미실행.

## 6. 미검증 / 범위 밖

1. iOS §9 작업과 무관 (이 세션은 요구사항 15 단독).
2. `scripts/lint.sh` 의 swiftlint 미설치 silent-skip 은 그대로 둠 — `lint_gate.sh` 가 미설치 시 rc=1 로 fail 하도록 별도 구현했으므로, CI 가 `lint_gate.sh` 를 호출하도록 전환하면 우회 불가.
3. `ci.yml` 의 `lint` step 을 게이트로 전환하는 커밋은 이 세션 범위 밖 — 24건 baseline 정리 후 orchestrator 가 수행.
4. 잔존 docs/ 산문 단언 0건 확인 완료 (`grep -rn '"docs/' Tests/` 결과, StaticContract 내 docs/ 읽기 전부 제거됨).
