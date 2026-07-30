# 신뢰성 수리 작업지시서 (전체 코드 실사 기반)

> **[보관 — 완료]** 이 문서는 `docs/archive/`에 있다. 현역이 아니며 갱신되지 않는다. 전체 문서 지도는 [docs/README.md](../README.md).
>
> - 상태: Task A~G 전부 커밋됨. 당시 최대 문제였던 `swift test` 행(hang)과 3건 실패가 해소됐다.
> - 지금 볼 곳: 후속은 `docs/NEXT_SESSION_WORKORDER_20260729.md`.

> 작성일: 2026-07-28
> 기준: main 브랜치 `6b33aab` (작업트리 clean)
> 대상: 후속 세션
> 목적: 전체 코드베이스 실사에서 확인된 Critical/High 결함 7종의 구체적 수행 지침
> 성격: **모든 항목은 빌드·실행·계측으로 실증된 결함이다.** 정적 감사 추정이나 문서 자가보고가 아니다.

## 0. 실사 결과 (검증 방법 포함)

| 검증 | 명령 | 결과 |
|------|------|------|
| Core 빌드 | `swift build` | ✅ 성공 (3.4s) |
| Mac 앱 빌드 | `xcodebuild -scheme MovieCutMac ... build` | ✅ 성공 (에러 0, 경고 46) |
| iOS 앱 빌드 | `xcodebuild -scheme MovieCutiOS ... build` | ❌ **불가** — iOS 26.5 플랫폼 미설치, destination 없음 |
| 전체 테스트 | `swift test` | ❌ **행(hang)** — 재현 2/2. 872 pass, **3 fail** 후 정지 |
| 린트 | `swiftlint lint` | ⚠️ 1,005건 (error 409 / warning 596), **CI 미적용** |

규모: Core 22,536줄 / Mac 33,635줄 / iOS 8,706줄 / Tests 20,791줄.

### 이 지시서가 기존 지시서보다 우선하는 이유

`docs/archive/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md`(Task A~E)는 전부 **iOS 파리티**를 다룬다. 그러나:

1. **iOS는 이 호스트에서 컴파일조차 불가**하므로 어떤 iOS 작업도 검증할 수 없다.
2. **`swift test`가 완주하지 못한다.** 모든 회귀 검증의 전제가 무너져 있다.
3. **main이 red다.** 테스트 3개가 clean HEAD에서 실패 중이다.

따라서 iOS 파리티 작업(기존 지시서)은 **본 지시서의 Task A~B 완료 후**에 착수한다.

---

## 1. Task A — 블로킹 오디오 디코드를 협조적 스레드 풀 밖으로 (최우선)

### 문제

`AVAssetReader`의 **동기 블로킹 읽기**가 Swift Concurrency의 cooperative thread pool 위에서 수행된다. 결과는 두 가지다.

**(1) 테스트 스위트 데드락 — 재현 2/2**

`sample`로 뜬 스택에서 9개 테스트가 동시에 `FigSemaphoreWaitRelative`에 블록되어 있었다:

```
WaveformGeneratorTests.maxAmplitudeProducesNearOneBins()   → WaveformGenerator.swift:65
WaveformGeneratorTests.allSilenceProducesNearZeroBins()    → WaveformGenerator.swift:65
WaveformGeneratorTests.silenceLoudSilencePattern()         → WaveformGenerator.swift:65
WaveformGeneratorTests.veryShortWAV()                      → WaveformGenerator.swift:65
SilenceDetectionProviderTests × 5                          → SilenceDetectionProvider.swift:154
```

cooperative pool 스레드는 10개(`com.apple.root.default-qos.cooperative`)인데 9개가 블록되어 스레드 기아 상태가 된다.

**결정적 증거**: 같은 테스트를 단독 실행하면 정상 통과한다.

```
swift test --filter "WaveformGeneratorTests"
→ ✔ Test run with 8 tests in 1 suite passed after 0.175 seconds.
```

즉 로직 결함이 아니라 **동시성 구조 결함**이다. 문서에 적힌 "145개 Core 테스트 통과"는 필터링된 부분 실행 결과이며, 전체 실행은 완료된 적이 없다.

**(2) 프로덕션 메인스레드 블로킹 (테스트만의 문제가 아님)**

- `App/MovieCutMac/TimelineView.swift:1147` — SwiftUI `Canvas` **draw 클로저 안**에서 `viewModel.waveform(for: clip)` 호출
- `App/MovieCutMac/EditorViewModel.swift:440` — `waveform(for:)`는 `@MainActor` **동기** 함수
- `App/MovieCutMac/EditorViewModel.swift:448` — 그 안에서 `WaveformGenerator.generate(for: asset)` 동기 호출

각 오디오/비디오 클립의 **최초 렌더 시 메인스레드가 전체 에셋 PCM 디코드를 동기 수행**한다. 10분짜리 영상이면 UI가 수 초간 멈춘다. `waveformCache`가 반복 드로우만 막아줄 뿐 최초 드로우는 항상 블록된다.

### 시작 파일

| 파일 | 지점 | 내용 |
|------|------|------|
| `Sources/MovieCutCore/Media/WaveformGenerator.swift` | `:24` | `public static func generate(for:)` — **동기** 시그니처 |
| | `:65` | `while let sampleBuffer = output.copyNextSampleBuffer()` 블로킹 루프 |
| `Sources/MovieCutCore/Analysis/SilenceDetectionProvider.swift` | `:86` | `detectSilentRanges(in:)` — `async`지만 내부가 블로킹 |
| | `:153-154` | `while true { let buffer = trackOutput.copyNextSampleBuffer() }` |
| `Sources/MovieCutCore/Analysis/BeatDetectionProvider.swift` | `:134` | `readMonoSamples(from:)` — **동기** `throws`, `:119` async에서 호출 |
| `App/MovieCutMac/EditorViewModel.swift` | `:440-455` | `waveform(for:)` 동기 @MainActor |
| `App/MovieCutMac/TimelineView.swift` | `:1145-1147` | `waveformCanvas` Canvas draw 클로저 |

동일 패턴이 `App/MovieCutMac/Export/ExportEngine.swift`, `App/MovieCutMac/Export/ReverseRenderService.swift`에도 있다. 이들은 export 경로(백그라운드)이므로 우선순위는 낮으나 함께 점검한다.

### 구현 방향

**⚠️ `Task.detached`는 이 문제를 고치지 못한다.** detached task도 같은 cooperative pool에서 실행되므로 기아 상태가 그대로다. 반드시 **비협조적(non-cooperative) 스레드**로 내보내야 한다.

1. 각 블로킹 리더를 GCD 글로벌 큐로 이동하는 async 래퍼를 만든다:

   ```swift
   private static func decodeSamples(_ work: @escaping @Sendable () -> WaveformData?) async -> WaveformData? {
       await withCheckedContinuation { continuation in
           DispatchQueue.global(qos: .userInitiated).async {
               continuation.resume(returning: work())
           }
       }
   }
   ```

2. `WaveformGenerator`에 `public static func generateAsync(for:) async -> WaveformData?`를 추가한다. 기존 동기 `generate(for:)`는 곧바로 지우지 말고 남겨두되, **cooperative context에서 호출 금지**를 doc comment로 명시한다.

3. `SilenceDetectionProvider.detectSilentRanges` / `BeatDetectionProvider.readMonoSamples`의 블로킹 루프를 같은 래퍼로 감싼다.

4. `EditorViewModel.waveform(for:)`를 캐시 조회 전용 동기 함수 + 비동기 채움으로 분리한다:
   - `waveform(for:) -> [CGFloat]` — 캐시 히트면 반환, 미스면 **빈 배열 즉시 반환 + 백그라운드 생성 트리거**
   - `Task`로 `generateAsync` 실행 → 완료 시 `waveformCache[clip.id]` 갱신 → `@Observable`이 뷰를 자동 재드로우
   - 생성 중 중복 트리거 방지를 위해 `waveformInFlight: Set<UUID>` 가드를 둔다

5. 테스트를 async로 전환한다 (`Tests/MovieCutCoreTests/WaveformGeneratorTests.swift`의 6개 호출부: `:82, :111, :141, :176, :195, :241`).

### 수용 기준

- **`swift test` 전체가 완주한다** (필터 없이). 이것이 이 Task의 단일 판정 기준이다.
- 완주 시간과 pass/fail 수를 보고에 명시한다.
- 오디오 클립이 있는 프로젝트에서 타임라인 최초 스크롤 시 UI 멈춤이 사라진다 (수동 확인).
- 파형이 결국 그려진다 (빈 배열 반환 후 백그라운드 채움이 실제로 뷰에 반영되는지 확인).

### 커밋 권장

`fix(moviecut): move blocking audio decode off the cooperative pool`

---

## 2. Task B — main HEAD의 실패 테스트 3건 수정

### 문제

작업트리 clean 상태의 `6b33aab`에서 테스트 3개가 실패한다. CI는 `swift test`를 돌리므로 **main이 red다**.

```
✘ R301R302PreviewTransportZoomStaticContractTests.swift:22
✘ R301R302PreviewTransportZoomStaticContractTests.swift:75
✘ R305SafeZoneToggleStaticContractTests.swift:59
   Caught error: .missingMarker("private func previewSurface(for clip: Clip) -> some View")
```

원인: `App/MovieCutMac/PreviewPanel.swift`가 리팩터되면서 `previewSurface`가 **함수에서 계산 프로퍼티로** 바뀌었다 (`:385`, 현재 `private var previewSurface: some View`). StaticContract 테스트가 옛 시그니처 문자열을 섹션 마커로 쓰고 있어 깨졌다.

정상적인 리팩터가 테스트를 깨뜨린 것이며, **동작상의 회귀는 없다.**

### 시작 파일 및 정확한 수정 지점

| 파일:줄 | 현재 | 변경 후 |
|---------|------|---------|
| `Tests/MovieCutCoreTests/R301R302PreviewTransportZoomStaticContractTests.swift:27` | `from: "private func previewSurface(for clip: Clip) -> some View"` | `from: "private var previewSurface: some View"` |
| `Tests/MovieCutCoreTests/R301R302PreviewTransportZoomStaticContractTests.swift:86` | `to: "    private func previewSurface"` | `to: "    private var previewSurface"` |
| `Tests/MovieCutCoreTests/R305SafeZoneToggleStaticContractTests.swift:64` | `from: "private func previewSurface(for clip: Clip) -> some View"` | `from: "private var previewSurface: some View"` |

### 확인 완료 사항 (재조사 불필요)

세 테스트의 **내용 assertion은 전부 현재 코드에 그대로 있고 순서도 맞다.** 마커 문자열만 고치면 통과한다. `PreviewPanel.swift:385-416` 확인 결과:

- `VideoPreviewView(player: playbackEngine.player)` ✅
- `.aspectRatio(canvasAspectRatio, contentMode: .fit)` ✅
- `.overlay {` ✅
- `previewOverlay(for: clip)` ✅
- `.scaleEffect(previewZoom)` ✅

`to:` 마커인 `"    private var canvasAspectRatio"`도 `:431`에 그대로 존재한다.

### 수용 기준

- 3개 테스트 통과.
- `swift test --filter "R301R302|R305"` 그린.

### 커밋 권장

`test(moviecut): realign preview static contract markers with refactored previewSurface`

---

## 3. Task C — `ClipTimeMapping` 슬로우 램프 클램프 수정

### 문제

순 감속(net slow-motion) 스피드 램프에서 **클립 후반부 전체가 단일 소스 프레임으로 붕괴**한다.

10초 소스에 0.5배속 램프(타임라인 20초)를 넣고 실제로 실행한 결과:

```
renderedTimelineDuration = 20.0          (정상)
sourceTime(forTimelineTime: 15) = 5.0    (기대 7.5)   ← 붕괴
sourceTime(forTimelineTime: 20) = 5.0    (기대 10.0)  ← 붕괴
timelineTime(forSourceTime: 10) = 10.0   (기대 20.0)  ← 붕괴
라운드트립: timeline 16 → source 5 → timeline 10      (6초 오차)
```

영향 범위: 이 타입은 스크러버·트림 핸들·키프레임 에디터·필름스트립 hover·split 커맨드를 **통일하려고 만든 단일 진실 공급원**이다. 즉 램프 클립의 후반 50%에서 이 모든 UI가 동시에 틀어진다.

`renderedTimelineDuration`은 20.0으로 **정확하다**. 클립은 타임라인에 20초로 렌더되는데 쿼리 경로만 앞의 10초까지밖에 주소를 못 매긴다.

### 근본 원인

램프 커브의 **출력 스케일**로 클램프해야 하는데 **소스 스케일**로 클램프한다.

`SpeedRampCurve.timeMapping`은 1/rate를 적분하므로, 0.5배속 구간에서 `timeMapping(1.0) = 2.0`이다. 즉 정규화 출력이 1.0을 초과할 수 있다.

| 파일:줄 | 현재 코드 | 문제 |
|---------|-----------|------|
| `Sources/MovieCutCore/Timeline/ClipTimeMapping.swift:221` | `let normalizedOutput = min(max(timelineOffset / sourceDuration, 0), 1)` | 상한 `1`이 아니라 `curve.timeMapping(sourceTime: 1.0)`이어야 함 |
| `Sources/MovieCutCore/Timeline/ClipTimeMapping.swift:247` | `return min(max(normalizedOutput * sourceDuration, 0), sourceDuration)` | 상한이 `sourceDuration`이 아니라 `renderedTimelineDuration`이어야 함 |

### 기존 테스트가 이걸 못 잡은 이유 (조사 완료)

`Tests/MovieCutCoreTests/ClipTimeMappingTests.swift`의 램프 테스트 2개 모두 구조적으로 이 버그를 통과시킨다:

- **`speedRampRoundTrip` (`:103`)** — 램프가 1x→3x→0.5x다. 적분 출력이 ≈0.633이라 `renderedTimelineDuration(6.33s) < sourceDuration(10s)`이므로 **클램프에 닿지 않는다**.
- **`speedRampMonotonic` (`:83`)** — `#expect(source >= previousSource)`로 단조성만 본다. **평탄화(saturation)도 단조 증가를 만족**하므로 통과한다.

### 구현 방향

1. `rampCurve`의 최대 출력값을 한 번 계산해 두는 private 헬퍼를 추가한다 (예: `rampOutputSpan = curve.timeMapping(sourceTime: 1.0)`).
2. `:221`의 클램프 상한을 `1` → `rampOutputSpan`으로 교체.
3. `:247`의 클램프 상한을 `sourceDuration` → `renderedTimelineDuration`으로 교체.
4. `sourceDuration <= 0`, `rampOutputSpan` 비유한/0 이하인 경우의 fail-closed 경로를 유지한다.

### 수용 기준 (회귀 테스트 필수)

`ClipTimeMappingTests.swift`에 **순 감속 램프** 케이스를 추가하고 아래를 검증한다:

- 램프 `[(0, 0.5), (1, 0.5)]`, 소스 10s 기준으로
  - `renderedTimelineDuration == 20.0`
  - `sourceTime(forTimelineTime: 15) ≈ 7.5` (1프레임 이내)
  - `sourceTime(forTimelineTime: 20) ≈ 10.0`
  - `timelineTime(forSourceTime: 10) ≈ 20.0`
- 타임라인 전 구간 라운드트립이 1프레임 이내
- **`speedRampMonotonic`을 강화한다**: `>=`(비감소)가 아니라 **구간별 실제 증가**를 검증해 평탄화를 잡아내도록 바꾼다
- 기존 가속 램프 테스트는 계속 통과해야 한다 (회귀 없음)

### 커밋 권장

`fix(moviecut): clamp ramped time mapping to output scale not source scale`

---

## 4. Task D — `CGPoint`/`CGSize` retroactive Codable 충돌 제거 (사용자 데이터 보호)

### 문제

`Sources/MovieCutCore/Models/CoreGraphicsCodable.swift`가 `CGPoint`/`CGSize`에 `@retroactive Codable`로 **키드 인코딩**(`{"x":1.5,"y":2.5}`)을 정의한다. 그러나 CoreGraphics가 이미 자체 conformance를 갖고 있어 충돌한다.

실제로 실행해 확인한 결과 **CoreGraphics의 배열 형식이 이긴다**:

```
CGPoint -> [1.5,2.5]
CGSize  -> [10,20]
array-form decode SUCCEEDED
```

즉 **이 파일의 `encode(to:)` / `init(from:)`은 한 번도 실행되지 않는 죽은 코드**다. 빌드 경고 6건이 이 충돌을 지적하고 있다 (`conformance of 'CGPoint' to protocol 'Decodable' was already stated in the protocol's module 'CoreGraphics'`).

### 왜 Critical인가

어느 conformance가 이기는지는 **언어 차원에서 보장되지 않는다**. SDK 업데이트, 최적화 설정 변경, 모듈 경계 차이로 뒤집히면 **기존에 저장된 `.moviecut` 파일이 디코딩 불가**가 된다. 사용자 작업물 손실이다.

영향받는 영속 모델 (14개 파일이 CGPoint/CGSize를 담는다):

```
Models/Mask.swift            Models/ClipTransform.swift    Models/CardLayout.swift
Models/TextClipContent.swift Models/TextTemplate.swift     Models/TextAnimation.swift
Models/CanvasPreset.swift    Models/Timeline.swift         Models/GestureTransform.swift
Models/ProxyInfo.swift       Models/ExportPreset.swift     Models/UserTextStylePreset.swift
Models/PlatformExportPreset.swift
```

### 구현 방향

1. **현재 저장 포맷을 먼저 고정한다.** 실측 결과 배열 형식(`[x, y]`)이 사용 중이므로, 이것이 기존 사용자 파일의 포맷이다. **마이그레이션 없이 포맷을 바꾸면 안 된다.**
2. `CoreGraphicsCodable.swift`에서 `Codable` retroactive conformance를 **제거**한다.
3. 대체 방안 중 택1 (권장: A):
   - **A. 명시적 래퍼 타입** — `CodablePoint`/`CodableSize`를 정의하고 모델 필드 타입을 교체한다. 인코딩 형식을 **배열로 맞춰** 기존 파일 호환을 유지한다. 가장 명확하고 재발 불가.
   - **B. 각 모델에서 개별 인코딩** — CGPoint 필드를 `[Double]`이나 개별 `x`/`y` 스칼라로 저장. 변경 범위가 넓다.
4. `zero` 재정의(`:5`, `:33`)도 함께 제거한다 — CoreGraphics의 `zero`와 모호해진다.
5. `Equatable` retroactive conformance도 동일하게 검토한다 (현재 3건 경고).

### 수용 기준 (마이그레이션 안전성이 핵심)

- **기존 포맷 호환 테스트**: Task 착수 전 현재 main에서 마스크·텍스트·카드 레이아웃을 포함한 프로젝트를 저장해 `.moviecut` 픽스처로 커밋한다. 수정 후 그 픽스처가 **손실 없이 로드**되어야 한다.
- 라운드트립 테스트: 저장 → 로드 → 모든 CGPoint/CGSize 필드가 값 동일.
- `xcodebuild MovieCutMac` 경고에서 conformance 중복 경고 6건이 사라진다.
- `swift test` 회귀 없음.

### 커밋 권장

`fix(moviecut): replace conflicting retroactive CG codable conformances`

---

## 5. Task E — 미저장 변경 보호 + 파괴적 작업의 undo 보전

### 문제 1: dirty 상태가 아예 없다

repo 전체에 `isDirty` / `hasUnsavedChanges` / `isModified` / `documentEdited` 상태가 **하나도 없다**.

- `App/MovieCutMac/EditorViewModel.swift:670` `newProject()` — 확인 없이 세션 교체
- `App/MovieCutMac/EditorViewModel.swift:690` `openProject(from:)` — 확인 없이 세션 교체

Cmd+N / Cmd+O가 미저장 작업을 **경고 없이, 되돌리기 없이** 폐기한다.

### 문제 2: Auto Highlights가 undo 히스토리를 파괴한다

`App/MovieCutMac/EditorViewModel.swift:4364`에서 프로젝트 전체를 교체하며 `session = EditorSession(project: newProject)`를 실행한다. `EditorSession`이 undo/redo 스택의 유일한 소유자(`Sources/MovieCutCore/EditorAPI/EditorSession.swift:8-9`)이므로 **스택이 통째로 사라진다**. 사용자가 Auto Highlights를 누르면 Cmd+Z가 무력화된다.

동일 패턴이 8곳에 있다 (`:210, :672, :694, :730, :785, :940, :4364, :5892`). 대부분은 정당하다(새 프로젝트 / 파일 열기 / 크래시 복구). **`:4364`(Auto Highlights)만 편집 작업이면서 세션을 리셋한다.**

### 구현 방향

1. `EditorViewModel`에 dirty 추적을 추가한다:
   - `private(set) var isDirty = false`
   - `refreshFromSession()` 경로에서 `true`로 설정 (autosave 트리거와 같은 지점: `:4613` 부근)
   - `saveProject(to:)` 성공 시 / `newProject()` / `openProject()` 직후 `false`로 리셋
2. `newProject()` / `openProject(from:)` 진입부에 `isDirty` 확인 다이얼로그를 붙인다 (`NSAlert`: 저장 / 저장 안 함 / 취소). 취소 시 아무 것도 하지 않는다.
3. 윈도우 닫기/앱 종료 경로에도 같은 가드를 적용한다.
4. **Auto Highlights를 커맨드 경로로 전환한다.** 세션을 버리지 말고, 하이라이트 시퀀스 구성을 `EditorCommand`로 만들어 `session.dispatch`로 적용한다. 그러면 undo가 자연히 동작한다.
   - 대안(차선): 세션 리셋 직전 스냅샷을 별도 보관하고 "실행 취소" 상태 메시지 액션을 제공. 커맨드 전환이 어려우면 이 경로를 쓰되 **적용 전 확인 다이얼로그는 필수**다.

### 수용 기준

- 편집 후 Cmd+N / Cmd+O 시 확인 다이얼로그가 뜬다. 취소 시 프로젝트가 유지된다.
- 저장 직후에는 다이얼로그가 뜨지 않는다 (dirty 리셋 확인).
- Auto Highlights 실행 후 Cmd+Z로 이전 상태 복구가 된다.
- `App/MovieCutMacUITests/`에 dirty 가드 시나리오를 추가한다 (Task F로 CI에 편입되면 회귀가 잡힌다).

### 커밋 권장

`fix(moviecut): guard unsaved work on new open and auto highlights`

---

## 6. Task F — CI 커버리지 확장

### 문제

`.github/workflows/ci.yml`이 `swift build` + `swift test`만 실행한다. 결과:

| 영역 | 줄 수 | CI 검증 |
|------|-------|---------|
| `Sources/MovieCutCore` | 22,536 | ✅ |
| `App/MovieCutMac` | 33,635 | ❌ **컴파일조차 안 됨** |
| `App/MovieCutiOS` | 8,706 | ❌ **컴파일조차 안 됨** |
| `App/MovieCutMacUITests` | 336 | ❌ 실행 안 됨 |
| swiftlint (1,005건) | — | ❌ 게이트 아님 |

전체의 약 26%만 검증된다. 게다가 그 `swift test`마저 Task A 때문에 완주하지 못한다.

### 구현 방향

1. **Task A/B 완료 후에** 착수한다 (그 전에는 CI를 켜도 계속 red다).
2. `ci.yml`에 Mac 앱 빌드 스텝 추가:
   ```yaml
   - name: Build Mac app
     run: xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug CODE_SIGNING_ALLOWED=NO build
   ```
3. swiftlint 스텝을 **경고 리포트 전용(non-blocking)** 으로 먼저 추가한다. 1,005건을 한 번에 게이트로 만들면 아무 것도 머지할 수 없다.
   - 후속으로 `.swiftlint.yml`에 baseline을 도입하거나, `--strict` 없이 신규 위반만 잡는 방식으로 단계적 강화.
4. `swift test`에 타임아웃을 건다 (`timeout-minutes`). Task A가 회귀하면 CI가 무한 대기하지 않고 실패하도록 한다.
5. iOS는 러너에 플랫폼이 있으면 generic build를 추가한다. 없으면 **추가하지 않고 그 사실을 ci.yml 주석으로 남긴다** (조용히 빠뜨리지 말 것).

### 수용 기준

- CI가 Mac 앱을 빌드한다.
- `swift test`에 타임아웃이 걸려 있다.
- lint 리포트가 CI 로그에 남는다.
- main이 green이다.

### 커밋 권장

`ci: build app targets and report lint`

---

## 7. Task G — StaticContract 테스트 방침 정리 (설계 결정 필요)

### 문제

테스트 파일 134개 중 **62개(46%)가 StaticContract**다. 앱 소스를 **문자열로 읽어** `source.contains(...)`를 검증한다. 그중 **38개는 `docs/*.md`의 한국어 산문을 assert**한다.

구조적 문제 3가지:

1. **동작 신호가 0이다.** 코드가 존재한다는 것만 확인하고 동작은 확인하지 않는다.
2. **정상 리팩터가 테스트를 깨뜨린다.** Task B의 3건이 정확히 이 사례다.
3. **결함을 고정한다.** `Tests/MovieCutCoreTests/IOSParityMatrixStaticContractTests.swift:56-57`:
   ```swift
   #expect(!iosCompositor.contains("TransitionPixelProcessor.apply"))
   #expect(!iosCompositor.contains("PersonSegmentationCompositor"))
   ```
   **기능을 구현하면 테스트가 깨진다.** 그래서 기존 지시서(`docs/archive/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md` Task C/D)에 "assertion을 반전하라"는 절차가 들어가 있다. 테스트가 개발을 막고 있다.

### 구현 방향 (판단이 필요하므로 단독 세션 권장)

이 Task는 코드 수정 전에 **방침 결정**이 필요하다. 제안:

1. StaticContract 62개를 3분류한다:
   - **(a) 삭제** — 문서 산문만 검증하는 것 (38개 중 다수). 문서는 테스트 대상이 아니다.
   - **(b) 동작 테스트로 승격** — 실제 기능을 다루는 것. 예: 파리티 매트릭스 assertion → Core processor 호출 결과의 골든 픽셀 비교로 전환.
   - **(c) 유지** — 아키텍처 경계 잠금 등 문자열 검사가 실제로 적합한 소수.
2. **부정 assertion(`!contains`)은 전부 제거한다.** 결함을 잠그는 테스트는 유지할 가치가 없다. 미구현 상태는 문서(`docs/PLATFORM_PARITY_MATRIX.md`)로 추적하면 충분하다.
3. `GoldenPixelHarness`(`Tests/MovieCutCoreTests/Support/GoldenPixelHarness.swift`)가 이미 올바른 패턴을 확립해 두었다. (b) 승격은 이 harness를 재사용한다.

### 수용 기준

- 분류 결과와 근거를 문서로 남긴다.
- 부정 assertion 0건.
- 삭제/승격 후 테스트 수 변화와 **실제 커버리지 변화**를 보고한다 (숫자가 줄어드는 건 정상이며, 줄어든 만큼이 원래 가짜였다는 뜻이다).

### 커밋 권장

`test(moviecut): retire doc-string contracts and unlock defect-locking assertions`

---

## 8. 권장 진행 순서

```
Task B (실패 3건 수정 — 30분, 즉시 가능, main 그린화)
  ↓
Task A (테스트 행 해소 — 모든 후속 검증의 전제)
  ↓
  ├─ Task C (램프 클램프 — 독립적, Core만)
  ├─ Task D (CG Codable — 독립적, 픽스처 선행 필요)
  └─ Task E (미저장 보호 — 독립적, Mac UI)
  ↓
Task F (CI 확장 — A/B 완료가 전제)
  ↓
Task G (StaticContract 정리 — 방침 결정 필요, 단독 세션)
  ↓
[기존 지시서] CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md Task A~E (iOS 파리티)
```

**Task B를 먼저 하는 이유**: 30분이면 끝나고, 그 후 모든 세션이 "main은 green이어야 한다"를 기준선으로 쓸 수 있다.

**Task C/D/E는 서로 독립적**이므로 병렬 세션 가능하다. 단 D는 픽스처 생성이 선행되어야 한다.

---

## 9. 각 Task별 세션 시작 프롬프트

### Task A — 블로킹 오디오 디코드

> `docs/archive/RELIABILITY_REPAIR_WORKORDER_20260728.md` Task A를 기준으로 작업해줘. `WaveformGenerator`, `SilenceDetectionProvider`, `BeatDetectionProvider`의 동기 `AVAssetReader` 읽기를 `withCheckedContinuation` + `DispatchQueue.global()` 패턴으로 협조적 풀 밖으로 내보내. `Task.detached`는 해결책이 아니니 쓰지 마. `EditorViewModel.waveform(for:)`를 캐시 조회 + 백그라운드 채움으로 분리해서 SwiftUI Canvas 드로우가 메인스레드를 막지 않게 해줘. 판정 기준은 **필터 없는 `swift test` 전체 완주**야. 완주 시간과 pass/fail 수를 반드시 보고해.

### Task B — 실패 테스트 3건

> `docs/archive/RELIABILITY_REPAIR_WORKORDER_20260728.md` Task B를 기준으로 작업해줘. 지시서 §2의 표에 정확한 파일:줄과 변경 전/후 문자열이 있어. 내용 assertion은 이미 현재 코드와 일치하는 걸 확인했으니 마커 문자열만 고치면 돼. `swift test --filter "R301R302|R305"`로 검증하고 커밋해.

### Task C — 램프 클램프

> `docs/archive/RELIABILITY_REPAIR_WORKORDER_20260728.md` Task C를 기준으로 작업해줘. `ClipTimeMapping.swift:221`과 `:247`의 클램프 상한이 소스 스케일로 잡혀 있어서 순 감속 램프의 후반부가 붕괴돼. 출력 스케일 기준으로 고쳐줘. 그리고 기존 램프 테스트 2개가 왜 이걸 못 잡았는지 지시서에 적혀 있으니, 순 감속 케이스 회귀 테스트를 추가하고 `speedRampMonotonic`도 평탄화를 잡도록 강화해줘.

### Task D — CG Codable

> `docs/archive/RELIABILITY_REPAIR_WORKORDER_20260728.md` Task D를 기준으로 작업해줘. **먼저** 현재 main에서 마스크·텍스트·카드 레이아웃을 포함한 프로젝트를 저장해 `.moviecut` 픽스처로 커밋해. 그 다음 `CoreGraphicsCodable.swift`의 retroactive Codable 충돌을 제거하되, 실측된 현재 저장 포맷(배열 `[x,y]`)과의 호환을 반드시 유지해. 픽스처가 손실 없이 로드되는 게 수용 기준이야.

### Task E — 미저장 보호

> `docs/archive/RELIABILITY_REPAIR_WORKORDER_20260728.md` Task E를 기준으로 작업해줘. `EditorViewModel`에 `isDirty` 추적을 추가하고 `newProject()`/`openProject()`/종료 경로에 확인 다이얼로그를 붙여줘. 그리고 Auto Highlights(`:4364`)가 `EditorSession`을 리셋해서 undo를 파괴하는 문제를 커맨드 경로 전환으로 고쳐줘.

### Task F — CI 확장

> `docs/archive/RELIABILITY_REPAIR_WORKORDER_20260728.md` Task F를 기준으로 작업해줘. Task A/B가 완료됐는지 먼저 확인하고(main이 green이어야 함), `ci.yml`에 Mac 앱 빌드와 `swift test` 타임아웃을 추가해. lint는 non-blocking 리포트로만 넣어줘 — 1,005건을 게이트로 만들면 아무 것도 머지 못 해.

### Task G — StaticContract 정리

> `docs/archive/RELIABILITY_REPAIR_WORKORDER_20260728.md` Task G를 기준으로 작업해줘. 코드 수정 전에 62개 StaticContract 테스트를 삭제/승격/유지로 분류하고 근거를 문서로 먼저 제시해줘. 특히 `IOSParityMatrixStaticContractTests.swift:56-57` 같은 부정 assertion은 기능 구현을 막고 있으니 제거 대상이야. 승격은 `GoldenPixelHarness` 패턴을 재사용해.

---

## 10. 주의사항

1. **`Task.detached`는 Task A의 해결책이 아니다.** detached task도 cooperative pool에서 실행된다. 반드시 GCD 등 비협조적 스레드로 내보내야 한다.

2. **Task D는 픽스처 선행이 필수다.** 포맷을 먼저 고정하지 않고 conformance를 건드리면 기존 사용자 파일을 못 읽게 된다. 실측 결과 현재 저장 포맷은 `[x, y]` 배열이다(`{"x":..}`가 아니다) — 코드만 읽고 판단하지 말 것.

3. **`swift test` 결과 보고 시 필터 여부를 반드시 명시한다.** 이 프로젝트는 과거에 필터링된 부분 실행 결과를 전체 통과로 기록한 전례가 있다. "N개 통과"라고만 쓰지 말고 실행한 명령 전문과 완주 여부를 함께 남긴다.

4. **iOS 관련 작업은 이 호스트에서 검증 불가다.** `xcodebuild -scheme MovieCutiOS`가 "iOS 26.5 is not installed"로 실패하고 `simctl`의 iOS 26-5 런타임도 Unavailable이다. iOS 코드를 수정했다면 **"빌드 검증 안 됨"을 명시**하고 완료로 처리하지 않는다.

5. **각 Task는 별도 브랜치**(`fix/<task-name>`)에서 진행하고 완료 시 main에 fast-forward 병합한다.

6. **`project.yml` 변경 시 반드시 `xcodegen generate`를 실행**한다. 단, `info:` 블록은 절대 추가하지 않는다 — Info.plist는 hand-maintained이며 xcodegen이 덮어쓰면 drag-and-drop UTI와 마이크 권한 키가 사라진다 (project.yml `:27-30` 주석 참조).

---

## 11. 이번 실사에서 확인된 양호 항목 (건드리지 말 것)

수리 과정에서 되돌리지 않도록 기록한다.

- **Core 아키텍처가 견고하다.** actor 기반 `EditorSession` + Command 패턴 + 값 타입 모델. Swift 6 strict concurrency `complete`가 Core/Tests 양쪽에 적용됨. ViewModel은 읽기 미러 역할에 충실하고(dispatch 57회, 직접 뮤테이션 우회 없음) undo 우회 경로가 없다.
- **`ClipTimeMapping`의 설계와 문서화는 우수하다.** Task C는 이 설계의 문제가 아니라 클램프 경계 두 줄의 실수다. 타입 자체를 재설계하지 말 것.
- **`GoldenPixelHarness`는 실제 문제를 고쳤다.** headless에서 픽셀 assertion이 조용히 skip되던 거짓 확신을 software `CIContext` + `assertRendererFunctional()`로 해결했다. Task G의 승격 대상 패턴으로 재사용한다.
- **위생 상태 양호**: `Sources`+`App`에 TODO/FIXME 0건, `try!` 0건, `as!` 1건. Core의 force unwrap 46건은 거의 전부 `UUID(uuidString: <리터럴>)!`로 무해하다.
- **하드코딩된 시크릿 없음.** API 키는 주입 클로저(`@Sendable () -> String?`) 방식이다.

---

## 12. 이번 지시서 범위 밖 (별도 추적)

수리 대상이지만 위 Task들보다 우선순위가 낮은 항목들이다.

| 항목 | 근거 | 비고 |
|------|------|------|
| `EditorViewModel` 6,013줄 분해 | 함수 312개, 클래스 본문 4,997줄 (프로젝트 자체 lint 한도 600) | Task E 작업 중 자연 분할 기회가 있으면 착수 |
| autosave 디바운스 없음 | `:4613` — 모든 뮤테이션마다 전체 프로젝트 JSON 인코딩 + 디스크 쓰기, Task 간 순서 보장 없음 | actor라 파일은 안 찢어짐. 성능/최신성 문제 |
| undo 스택 무제한 | `EditorSession.swift:8` — 전체 프로젝트 스냅샷 무제한 축적 | 긴 세션에서 메모리 단조 증가 |
| 컴포지터 중복 23개 함수 | Mac/iOS 컴포지터에 동명 구현 각각 존재 | 문서화된 "P0 warmth/tint divergence" 사고의 구조적 원인 |
| 미배선 Core 기능 | `CollaborationService`, `VersionHistory`, `TemplateMarketplace`, `SocialShareService`, `RenderCache`, `SnapEngine`, `MediaLibrary`, `ExportPreset`, `ClaudeEditingProvider`/`AIEditingProvider`, `CrossfadeAudioCommand`, `SaveAsTemplateCommand`, `AutoReframeCommand`, `ImportMultipleCommand` — App 참조 0건 | 삭제할지 배선할지 제품 결정 필요 |
| Mac Auto Assistant가 스텁 | `AutoAssistantView.swift:96`이 `StubAnalysisProvider()` 사용 (`isAvailable = false`, 항상 빈 결과) | UI는 있고 백엔드가 없음 |
| `SnapEngine` 중복 | Core `SnapEngine` 미사용, Mac은 `TimelineView.swift:1406`에 자체 `snappedTime` 보유 | 기능 누락이 아니라 중복 |
| stale 모델 ID | `ClaudeEditingProvider.swift:64`의 `claude-opus-4-8` (현행은 Claude 5 계열) | 미배선이라 영향 없음 |
| 문서 스프롤 | `docs/` 33개 파일 8,596줄, `GAP_ANALYSIS` 계열만 12개 버전 | Task G와 함께 정리 |
