# 핵심 편집 경로 수리 — 후속 작업 지시서

> 작성일: 2026-07-28
> 기준: main 브랜치 `4088ee2` (CAPCUT_CORE_EDITING_REPAIR_HANDOFF Step 1~7 완료 병합)
> 대상: 후속 세션
> 목적: 핸드오프 7단계 완료 후 남은 과제 5종의 구체적 수행 지침

## 0. 현재 상태 요약

CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md의 7단계가 main에 병합됨.

| Step | 상태 | 비고 |
|------|------|------|
| 1~5 | ✅ 완료 | macOS Core 동작 + behavioral 테스트 검증 |
| 6 | ✅ silent-skip 제거 / ⚠️ parity 전체 실행은 인프라 대기 | 6개 픽셀 테스트 GoldenPixelHarness 마이그레이션 완료, harness 게이트 + 스크립트 준비됨 |
| 7 | ✅ 구현 완료 / ⚠️ 검증 대기 | iOS 코드 구현 완료, actual-app 검증 인프라 없음 |

**145개 Core 테스트 + 53개 픽셀 테스트 통과, macOS 빌드 성공.**

### 검증 한계 (후속 작업의 출발점)
- iOS actual-app 테스트 인프라가 전혀 없음 (XCUITest 타겟 없음, 시뮬레이터 없음)
- parity 스크립트 전체 실행이 이 호스트의 export 성능/GPU compositor 한계로 불가
- two-source transition 시나리오가 headless harness에서 안정적이지 않음

---

## 1. 우선순위별 후속 작업

### Task A — iOS actual-app 테스트 인프라 구축 (최우선, 모든 iOS 검증의 선행 조건)

#### 문제
Step 7의 iOS 코드(속도/ramp/reverse/freeze/export)가 구현됐지만 런타임 검증이 불가능하다. `project.yml`에 iOS 테스트 타겟이 없고, 시뮬레이터가 설치되어 있지 않다.

#### 시작 파일
- `project.yml` — 4개 타겟(MovieCutMac, MovieCutiOS, MovieCutCoreTests, MovieCutMacUITests), iOS 테스트 타겟 없음
- `App/MovieCutMac/UITestHarness.swift` — macOS harness 패턴 (`#if DEBUG`, `MOVIECUT_UITEST=1` 게이트, `:151`)
- `App/MovieCutMacUITests/ImportExportE2ETests.swift` — macOS XCUITest 패턴

#### 구현 방향
1. `project.yml`에 `MovieCutiOSUITests` 타겟 추가 (`bundle.ui-testing`, platform iOS, `TEST_TARGET_NAME: MovieCutiOS`)
2. `xcodegen generate` 실행으로 `project.pbxproj` 갱신
3. iOS harness 진입점 추가: `App/MovieCutiOS/ContentView.swift`의 `.task`에 `#if DEBUG await viewModel.runUITestHarnessIfRequested() #endif` (macOS `ContentView.swift:358` 패턴 차용)
4. iOS `IOSEditorViewModel`에 harness 확장 추가 (import → export → 결과 직렬화)
5. `App/MovieCutiOSUITests/` 디렉토리 + 첫 XCUITest 파일 생성
6. Xcode에 iOS 시뮬레이터 설치 확인 (Xcode > Settings > Platforms)
7. `xcodebuild -scheme MovieCutiOS -destination 'platform=iOS Simulator,name=iPhone 16' test` 실행

#### 수용 기준
- iOS 시뮬레이터에서 앱이 빌드 + 실행됨
- iOS harness가 import → export 파이프라인을 실제로 구동함
- Step 7의 속도/ramp/reverse/freeze export가 실제 mp4로 검증됨

#### 커밋 권장
`test(moviecut): add ios simulator test infrastructure`

---

### Task B — IOSPlaybackEngine dead code 제거

#### 문제
`App/MovieCutiOS/Playback/IOSPlaybackEngine.swift` 전체가 dead code다. `loadProject` (`:46-70`)와 `buildComposition` (`:169-266`)를 포함하지만, repo 전체에서 이 클래스를 참조하는 곳이 자기 자신의 선언 한 곳뿐이다. iOS Preview는 `App/MovieCutiOS/Views/PreviewView.swift`의 inline composition을 사용한다.

#### 시작 파일
- `App/MovieCutiOS/Playback/IOSPlaybackEngine.swift` — 268줄 전체 dead code (`#if os(iOS)` 게이트됨)
- iOS Preview 실제 경로: `App/MovieCutiOS/Views/PreviewView.swift:99-149` (inline `buildComposition`)

#### 구현 방향
1. `IOSPlaybackEngine.swift` 삭제
2. `project.yml`의 `MovieCutiOS` 소스 경로(`App/MovieCutiOS`)가 디렉토리 기반이므로 xcodegen 재생성 불필요 (자동 반영)
3. `xcodebuild build` (MovieCutiOS)로 컴파일 검증
4. macOS 빌드에 영향 없음 확인 (`#if os(iOS)` 게이트)

#### 수용 기준
- 파일 삭제 후 iOS 빌드 성공
- macOS 빌드/테스트 회귀 없음

#### 커밋 권장
`refactor(moviecut): remove dead IOSPlaybackEngine`

---

### Task C — iOS chroma/background-removal shared processor 전환

#### 문제
iOS compositor가 chroma key와 person segmentation을 inline으로 재구현하고, Core의 shared processor를 사용하지 않는다. macOS는 `ChromaKeyPixelProcessor`와 `PersonSegmentationCompositor`를 사용한다.

#### 시작 파일
- `App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift`
  - `applyPersonSegmentation(to:request:)` — `:794-847` (inline `VNGeneratePersonSegmentationRequest` + vignette fallback `:876-909`)
  - `applyChromaKey(to:keyColor:threshold:)` — `:934-979` (inline `CIColorCube` + `smoothstep`)
- macOS 참조: `App/MovieCutMac/Export/CustomVideoCompositor.swift:544,546` (`ChromaKeyPixelProcessor`), `:1085,1091` (`PersonSegmentationCompositor`)
- Core processors: `Sources/MovieCutCore/Rendering/ChromaKeyPixelProcessor.swift`, `Sources/MovieCutCore/Rendering/PersonSegmentationCompositor.swift`

#### 구현 방향
1. `IOSCustomVideoCompositor.applyChromaKey`를 `ChromaKeyPixelProcessor.apply(chromaKey, to: image)` 호출로 교체
2. `IOSCustomVideoCompositor.applyPersonSegmentation`을 `PersonSegmentationCompositor` 호출로 교체 (또는 macOS 패턴 차용)
3. `Tests/MovieCutCoreTests/IOSParityMatrixStaticContractTests.swift:56-57`의 `#expect(!iosCompositor.contains("PersonSegmentationCompositor"))` assertion을 `#expect(iosCompositor.contains(...))`로 반전
4. `PLATFORM_PARITY_MATRIX.md` §6의 "여전히 defer" 항목 업데이트

#### 주의
- `IOSParityMatrixStaticContractTests.swift:63-65`가 iOS가 이 processors를 **사용하지 않음**을 적극적으로 강제하고 있다. 전환 시 이 assertion들을 반전해야 한다.
- chroma key는 현재 StaticContract로 강제되지 않음 (`:56-57`에 chroma 라인 없음). segmentation만 강제됨.

#### 수용 기준
- iOS compositor가 Core shared processor를 호출함
- StaticContract assertion이 새 상태를 반영함
- iOS 빌드 성공 (Task A 완료 후 시뮬레이터 검증 권장)

#### 커밋 권장
`refactor(moviecut): route ios chroma and segmentation through shared processors`

---

### Task D — Two-source transition iOS 배선

#### 문제
iOS compositor가 single-source만 처리한다. two-source cross dissolve/wipe/fade 전환이 없다. macOS는 `CustomVideoCompositor.startRequest`에서 두 번째 source buffer를 요청하고 `TransitionPixelProcessor.apply`를 호출한다.

#### 시작 파일
- `App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift`
  - `startRequest` — `:302` (`firstSourceFrame`만 호출, single-source)
  - `firstSourceFrame` — `:913-924` (첫 source만 반환)
  - `CustomCompositionInstruction` — `:222-284` (`clipEffects`만, transition 정보 없음)
- macOS 참조: `App/MovieCutMac/Export/CustomVideoCompositor.swift:410-440` (two-source branch)
- Core: `Sources/MovieCutCore/Rendering/TransitionPixelProcessor.swift`

#### 구현 방향
1. `CustomCompositionInstruction`에 `transitionEffects` / `activeTransition(at:)` 추가 (macOS 패턴)
2. `IOSCustomVideoCompositor.startRequest`에 two-source branch 추가: 두 source buffer를 가져와 `TransitionPixelProcessor.apply` 호출
3. `IOSCustomVideoCompositor`에 `secondSourceFrame` 헬퍼 추가
4. `IOSParityMatrixStaticContractTests.swift:56`의 `#expect(!iosCompositor.contains("TransitionPixelProcessor.apply"))` 반전
5. `PLATFORM_PARITY_MATRIX.md` 업데이트

#### 수용 기준
- iOS export가 two-source transition을 렌더링함
- macOS parity harness의 cross dissolve 시나리오가 iOS에서도 동작 (Task A 완료 후)

#### 커밋 권장
`feat(moviecut): wire two-source transitions on ios compositor`

---

### Task E — 수동 완주 시나리오 harness 확장 + parity 전체 실행

#### 문제
핸드오프 §4의 12단계 수동 완주 시나리오를 harness로 구동할 수 없다. sticker 게이트, trim 게이트, undo 게이트, preview-vs-export duration 비교가 없다.

#### 시작 파일
- `App/MovieCutMac/UITestHarness.swift` — `applyParityScenarioEdits` (`:2019-2110`)
- `scripts/run_core_editing_parity.sh` — 7개 시나리오 (transition 제외)
- `scripts/verify_preview_export_parity.py` — frame MAD 비교 (duration 비교 없음)

#### 현재 게이트 커버리지 (12단계 매핑)

| 단계 | 게이트 | 상태 |
|------|--------|------|
| import 2 videos + 1 photo | `MOVIECUT_UITEST_IMPORT` | ✅ |
| arrange | (없음) | ❌ |
| 2× speed | `MOVIECUT_UITEST_SPEED_RATE` | ✅ |
| speed ramp | `MOVIECUT_UITEST_SPEED_RAMP=1` | ✅ (고정 points) |
| transition | `MOVIECUT_UITEST_TRANSITION` | ✅ (headless hang — caveat) |
| text at 5s | `MOVIECUT_UITEST_TEXT_AT` | ✅ |
| **sticker at 5s** | **없음** | ❌ |
| BGM | `MOVIECUT_UITEST_BGM_AT` + `_PATH` | ✅ |
| split | `MOVIECUT_UITEST_SPLIT_AT` | ✅ |
| **trim** | **없음** | ❌ |
| delete | `MOVIECUT_UITEST_NORMAL_DELETE` | ✅ |
| **undo** | **없음 (parity 경로)** | ❌ |
| ripple delete | `MOVIECUT_UITEST_RIPPLE_DELETE` | ✅ |
| **play** | **없음** | ❌ |
| export | `MOVIECUT_UITEST_EXPORT` | ✅ |
| **preview vs export duration 비교** | **없음** | ❌ |

#### 구현 방향
1. `applyParityScenarioEdits`에 게이트 추가: `MOVIECUT_UITEST_STICKER_AT`, `MOVIECUT_UITEST_TRIM_END_AT`, `MOVIECUT_UITEST_UNDO=1`, `MOVIECUT_UITEST_PLAY=1`
2. `verify_preview_export_parity.py`에 duration 비교 추가: ffprobe로 export duration 추출, harness의 composition duration과 비교 (1프레임 이내)
3. `run_core_editing_parity.sh`에 12단계 완주 시나리오 추가 (모든 게이트 조합)
4. working GPU compositor host에서 실행 (transition 시나리오 포함)

#### 수용 기준
- 12단계가 harness로 구동 가능함
- preview duration과 export duration이 1프레임 이내로 일치함
- 전체 시나리오가 막힘없이 완주됨

#### 커밋 권장
`test(moviecut): drive full manual completion scenario through harness`

---

## 2. 권장 진행 순서

```
Task B (dead code 제거, 독립적, 빠름)
  ↓
Task A (iOS 테스트 인프라, 선행 조건)
  ↓
Task C (chroma/segmentation shared processor, Task A 검증 필요)
  ↓
Task D (two-source transition, Task A 검증 필요)
  ↓
Task E (수동 완주 + parity 전체, 모든 선행 완료 후)
```

Task B는 독립적이고 즉시 가능. Task A가 가장 중요한 선행 조건 (C, D, E 모두 의존). Task E는 최종 검증.

---

## 3. 각 Task별 세션 시작 프롬프트

### Task A — iOS 테스트 인프라

> `docs/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md` Task A를 기준으로 작업해줘. 먼저 git status와 현재 코드를 재확인한 뒤, iOS UI test 타겟을 project.yml에 추가하고 xcodegen을 실행해. MovieCutiOS에 DEBUG harness 진입점을 추가하고(import → export → 결과 직렬화), 첫 iOS XCUITest를 작성해. iOS 시뮬레이터에서 빌드 + 테스트 실행까지 완료하고, 결과와 caveat를 보고해.

### Task B — Dead code 제거

> `docs/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md` Task B를 기준으로 작업해줘. `App/MovieCutiOS/Playback/IOSPlaybackEngine.swift`가 dead code인지 재확인(repo-wide grep)한 뒤 삭제하고, iOS + macOS 빌드와 swift test로 회귀 없음을 확인해. 커밋까지 완료해.

### Task C — Chroma/Segmentation shared processor

> `docs/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md` Task C를 기준으로 작업해줘. iOS compositor의 inline `applyChromaKey`와 `applyPersonSegmentation`을 Core의 `ChromaKeyPixelProcessor`와 `PersonSegmentationCompositor` 호출로 교체해. `IOSParityMatrixStaticContractTests`의 관련 assertion을 반전하고, PLATFORM_PARITY_MATRIX를 업데이트해. iOS 빌드 + Core 테스트로 검증해.

### Task D — Two-source transition

> `docs/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md` Task D를 기준으로 작업해줘. iOS compositor에 two-source transition branch를 추가해. macOS `CustomVideoCompositor.startRequest`의 two-source 패턴을 차용하고, `TransitionPixelProcessor.apply`를 호출해. `CustomCompositionInstruction`에 transition 정보를 추가하고, StaticContract assertion을 반전해.

### Task E — 수동 완주 + parity

> `docs/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md` Task E를 기준으로 작업해줘. harness에 sticker/trim/undo/play 게이트를 추가하고, verify_preview_export_parity.py에 duration 비교를 추가해. 12단계 수동 완주 시나리오를 하나의 harness 구동으로 만들고, working GPU host에서 전체 parity 스크립트를 실행해.

---

## 4. 주의사항

1. **Task A 선행**: iOS 런타임 검증 없이 C/D/E를 "완료"로 처리하지 말 것 (핸드오프 §0 원칙).
2. **StaticContract 반전**: Task C/D에서 `IOSParityMatrixStaticContractTests`의 `#expect(!source.contains(...))` assertion들을 반전해야 한다. 반전하지 않으면 테스트가 깨진다.
3. **GPU compositor host**: parity 스크립트의 transition 시나리오는 working GPU compositor host에서만 안정적으로 실행된다. 현재 호스트에서는 headless harness의 `CustomVideoCompositor` build가 완료되지 않는다.
4. **브랜치 관리**: 각 Task는 별도 브랜치(`fix/<task-name>`)에서 진행하고, 완료 시 main에 fast-forward 병합.
5. **xcodegen**: project.yml 변경 후 반드시 `xcodegen generate`를 실행해 project.pbxproj를 갱신할 것.
