# MovieCut NLE Architecture Refactoring Plan (FCP / CapCut Grade)

> [!IMPORTANT]
> **타 세션(독립 개발 세션) 실행 지침 및 테스트 제약 사항 (필독)**
> 1. **목적**: 본 문서는 다른 세션의 에이전트가 **추가 질문이나 오해 없이 코드 수정만 즉시 순서대로 진행**할 수 있도록 파일 경로, 라인 번호, 변경 전/후 코드, 불변 조건(Invariants)을 명세한 상세 작업 계획서입니다.
> 2. **과도한 테스트 절대 금지 (Strict Minimal Testing Rule)**:
>    - 전체 테스트 스위트(`swift test` 전체 실행, `xcodebuild test` 전체 실행), UI 테스트(`MovieCutMacUITests`), 장시간 소요되는 E2E/Parity/Golden/Stress 하네스 실행을 **절대 금지**합니다.
>    - 각 Phase 완료 시 **오직 `swift build` 컴파일 확인과 해당 Phase에 명시된 단일 타겟 필터 테스트(`swift test --filter <단일테스트명>`) 1~2개만** 실행하십시오.
> 3. **기존 렌더링/동작 호환성 유지 (Behavioral Invariants)**:
>    - 기존 public/package API 시그니처는 하위 호환성(기본 파라미터 값 활용 등)을 유지하여 기존 호출부가 깨지지 않도록 합니다.
>    - SDR/HDR 픽셀 포맷 계약(`32BGRA` / `420YpCbCr10BiPlanarVideoRange`), `PersonSegmentationCompositor.maskContainsForeground`의 빈 마스크 방어 계약, 오디오 샘플 정확도(Bit-exactness)를 깨뜨리지 마십시오.

---

## 작업 순서 요약 (Execution Roadmap)

| Phase | 도메인 | 핵심 수정 대상 파일 | 검증 명령어 (단일 실행) |
| :--- | :--- | :--- | :--- |
| **Phase 1** | 렌더링 & 컴포지션 | `CustomVideoCompositor.swift`, `IOSCustomVideoCompositor.swift`, `RenderCache.swift` | `swift build` & `swift test --filter RenderCacheTests` |
| **Phase 2** | 미디어 I/O & 재생 | `ReverseRenderService.swift`, `PlaybackEngine.swift` | `swift build` & `swift test --filter ReverseRenderServiceTests` |
| **Phase 3** | 타임라인 모델 & 시간 | `FlattenedTimeline.swift`, `ClipTimeMapping.swift` | `swift build` & `swift test --filter CompoundFlattenerTests` |
| **Phase 4** | 오디오 엔진 DSP | `AudioGraphRendering.swift`, `AudioGraphEngines.swift` | `swift build` & `swift test --filter AudioGraphTests` |
| **Phase 5** | UI 가상화 & 제너레이터 | `WaveformGenerator.swift`, `FilmstripGenerator.swift`, `TimelineView.swift`, `IOSTimelineView.swift` | `swift build` & `swift test --filter WaveformGeneratorTests` |

---

## Phase 1: 렌더링 및 컴포지션 파이프라인 (Render Graph & Compositing)

### Task 1.1: `CustomVideoCompositor` (macOS & iOS) 요청 취소, 스티커 이미지 캐시, Vision Zero-Copy 적용

#### 대상 파일
- `App/MovieCutMac/Export/CustomVideoCompositor.swift`
- `App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift`

#### 수정 사항 상세

1. **비동기 컴포지션 요청 취소(`cancelAllPendingVideoCompositionRequests`) 구현 (macOS & iOS 공통)**
   - **문제**: `cancelAllPendingVideoCompositionRequests()`가 빈 블록(`{}`)이어서 고속 스크러빙 시 큐에 쌓인 구형 프레임이 끝까지 렌더링됨.
   - **해결**: `OSAllocatedUnfairLock<UInt64>` 세대 카운터를 두고, `startRequest(_:)` 진입 시점의 세대 번호(`generation`)를 캡처합니다. `renderQueue.async` 내부 시작 시점에 현재 세대 번호와 다르면 즉시 `request.finishCancelledRequest()`를 호출하고 리턴합니다. `cancelAllPendingVideoCompositionRequests()` 호출 시 세대 번호를 `+1` 증가시킵니다.
   - **코드 변경 (`CustomVideoCompositor.swift` L270~L295, L557 및 `IOSCustomVideoCompositor.swift` L182~L200, L342)**:
     ```swift
     import os

     // 프로퍼티 추가 (CustomVideoCompositor 클래스 내부)
     private let cancellationGeneration = OSAllocatedUnfairLock<UInt64>(initialState: 0)
     private let stickerImageCache = NSCache<NSURL, CGImage>()
     ```
     `startRequest(_:)` 내부:
     ```swift
     func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
         let sendableRequest = RequestBox(request: request)
         let generation = cancellationGeneration.withLock { $0 }
         renderQueue.async {
             let request = sendableRequest.request
             if self.cancellationGeneration.withLock({ $0 != generation }) {
                 request.finishCancelledRequest()
                 return
             }
             // ... 기존 렌더링 로직 진행 ...
     ```
     `cancelAllPendingVideoCompositionRequests()` 구현:
     ```swift
     func cancelAllPendingVideoCompositionRequests() {
         cancellationGeneration.withLock { $0 &+= 1 }
     }
     ```

2. **스티커 이미지 디스크 I/O 인메모리 캐싱 (`CustomVideoCompositor.swift` L1049~L1058)**
   - **문제**: `loadStickerImage(from:)`가 매 프레임마다 `CGImageSourceCreateWithURL` + `CGImageSourceCreateImageAtIndex`를 호출하여 동기 디스크 I/O 및 PNG 디코딩을 수행함.
   - **해결**: `NSCache<NSURL, CGImage>`를 사용하여 URL별 디코딩된 `CGImage`를 캐싱합니다.
   - **코드 변경 (`CustomVideoCompositor.swift` L1049~L1058)**:
     ```swift
     private func loadStickerImage(from url: URL) -> CGImage? {
         let nsURL = url as NSURL
         if let cached = stickerImageCache.object(forKey: nsURL) {
             return cached
         }
         guard FileManager.default.fileExists(atPath: url.path),
               let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(
                   source,
                   0,
                   [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
               ) else {
             return nil
         }
         stickerImageCache.setObject(cgImage, forKey: nsURL)
         return cgImage
     }
     ```

3. **인물 배경 제거(`applyPersonSegmentation`) CPU Readback 제거 (`CustomVideoCompositor.swift` L1218~L1257, `IOSCustomVideoCompositor.swift` L798~L836)**
   - **문제**: `ciContext.createCGImage(image, from: extent)`를 호출해 GPU의 `CIImage`를 CPU 비트맵(`CGImage`)으로 강제 Readback한 뒤 `personSegmentationHandler.perform`에 전달함.
   - **해결**: `VNSequenceRequestHandler.perform(_:on: CIImage)` API를 직접 호출하여 GPU/Neural Engine 파이프라인에서 CPU 복사 없이 바로 처리하도록 변경합니다.
   - **코드 변경**:
     ```swift
     private func applyPersonSegmentation(
         to image: CIImage,
         request: AVAsynchronousVideoCompositionRequest,
         prefersFast: Bool = false
     ) -> CIImage {
         _ = request

         let extent = image.extent
         guard extent.width > 0, extent.height > 0 else { return image }

         let normalizedInput: CIImage
         if extent.origin == .zero {
             normalizedInput = image
         } else {
             normalizedInput = image.transformed(
                 by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
             )
         }

         let segmentationRequest = VNGeneratePersonSegmentationRequest()
         segmentationRequest.qualityLevel = prefersFast ? .fast : .accurate
         segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8

         do {
             try personSegmentationHandler.perform([segmentationRequest], on: normalizedInput)
         } catch {
             return image
         }

         guard let maskPixelBuffer = segmentationRequest.results?.first?.pixelBuffer else {
             return image
         }

         let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
         guard !maskImage.extent.isEmpty else {
             return image
         }

         let alignedMask = PersonSegmentationCompositor.align(maskImage, to: extent)
         guard maskContainsForeground(alignedMask, extent: extent) else {
             return image
         }

         return PersonSegmentationCompositor.removeBackground(from: image, mask: alignedMask)
     }
     ```

---

### Task 1.2: `RenderCache` LRU 연산 고속화 및 바이트 기반 용량 추적

#### 대상 파일
- `Sources/MovieCutCore/Rendering/RenderCache.swift`

#### 수정 사항 상세
- **문제**: `RenderCache` 내부에서 `recency: [RenderSegmentKey]` 배열에 대해 매 `get`/`set`마다 `recency.removeAll { $0 == key }` ($O(N)$)를 수행하며, 바이트 단위 메모리 상한 옵션이 없습니다.
- **해결 (`RenderCache.swift` L96~L234)**:
  1. 각 캐시 엔트리의 마지막 접근 순서 번호(`accessOrder: UInt64`)를 `orderByKey: [RenderSegmentKey: UInt64]` 딕셔너리에 기록하고, `nextAccessOrder: UInt64` 카운터를 증가시킵니다.
  2. `touch(_:)`는 배열 순회/삭제 없이 `orderByKey[key] = nextOrder`만 갱신($O(1)$)하고, Eviction 시점에만 `orderByKey.min(by: { $0.value < $1.value })?.key`로 가장 오래된 키를 찾아 제거합니다.
  3. 선택적 `maxMemoryBytes: Int? = nil` 파라미터를 `init(memoryLimit: Int = 32, maxMemoryBytes: Int? = nil, diskDirectory: URL? = nil, fileManager: FileManager = .default)`에 기본값 `nil`로 추가하여 하위 호환성을 유지하면서 바이트 기반 Eviction도 지원합니다.

#### Phase 1 검증 명령어
```bash
swift build
swift test --filter RenderCacheTests
```

---

## Phase 2: 디코딩, 인코딩 및 미디어 I/O (Hardware Acceleration & Media I/O)

### Task 2.1: `ReverseRenderService` 청크(Chunk) 단위 역방향 렌더링으로 메모리 폭주(OOM) 제거

#### 대상 파일
- `Sources/MovieCutCore/Rendering/ReverseRenderService.swift`

#### 수정 사항 상세
- **문제**: `ReverseRenderService.renderReversed` (L79~L168)가 클립 전체 구간의 압축 해제된 `32BGRA` `CMSampleBuffer`를 `var sampleBuffers: [CMSampleBuffer] = []` 배열 하나에 전부 적재한 뒤 역순으로 기록합니다.
- **해결**:
  1. `effectiveTimeRange`를 뒤에서부터 앞으로 **최대 1.0초 단위의 시간 윈도우(Chunk)**로 분할합니다.
  2. 각 윈도우마다 `AVAssetReader` + `AVAssetReaderTrackOutput`을 생성하여 해당 윈도우 내부의 프레임들만 로컬 배열 `chunkSamples`에 읽어들인 뒤, `chunkSamples.reversed()`를 순회하며 `adaptor.append(imageBuffer, withPresentationTime: currentPresentationTime)`로 기록하고 즉시 해제합니다.
  3. 첫 번째(가장 뒤쪽) 유효 청크를 읽은 시점에 `AVAssetWriter`를 시작하며, 전체 구간에서 디코딩된 프레임이 0개이면 기존처럼 `ReverseRenderError.noFramesDecoded`를 던집니다.

---

### Task 2.2: `PlaybackEngine` 메인 스레드 블로킹 제거, Chase-Seek 도입, Thermal 상태 재생 위치 보존

#### 대상 파일
- `App/MovieCutMac/Playback/PlaybackEngine.swift`

#### 수정 사항 상세

1. **`snapshotFrame(at:)` 내 `Thread.sleep` 제거 (`PlaybackEngine.swift` L394~L403)**
   - `Thread.sleep(forTimeInterval: 0.03)` 대신 `RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.015))`를 사용하여 메인 RunLoop 디스패치를 블로킹하지 않도록 변경합니다.

2. **고속 스크러빙 시 Chase-Seek 상태 머신 적용 (`PlaybackEngine.swift` L592~L609)**
   - `isSeeking: Bool`과 `pendingSeekTime: CMTime?`을 추가하여 이전 `player.seek`가 진행 중일 때는 최신 타겟 시간만 `pendingSeekTime`에 덮어쓰고, 이전 seek 완료 콜백에서 최신 `pendingSeekTime`으로 즉시 이어서 seek하도록 구현합니다. (`player.currentItem == nil`인 경우 기존처럼 즉시 `player.seek` 호출).

3. **발열 상태 변화(`thermalStateChanged`) 시 재생 위치 및 재생 상태 보존 (`PlaybackEngine.swift` L156~L161)**
   - `loadProject` 호출 전 `let priorTime = currentTime`, `let wasPlaying = isPlaying`을 캡처하고, `loadProject` 완료 후 `if priorTime > 0 { seek(to: priorTime) }` 및 `if wasPlaying { play() }`를 복원합니다.

#### Phase 2 검증 명령어
```bash
swift build
swift test --filter ReverseRenderServiceTests
```

---

## Phase 3: 타임라인 데이터 모델 및 시간 정밀도 (Timeline Data Model & Time Precision)

### Task 3.1: `CompoundFlattener.digest(of:)` 결정론적(Deterministic) 전체 렌더 속성 해시로 교체

#### 대상 파일
- `Sources/MovieCutCore/Rendering/FlattenedTimeline.swift`

#### 수정 사항 상세
- `Swift.Hasher()` 대신 FNV-1a 64-bit 기반 `DeterministicDigestHasher`를 구현하고, 트랙(`id`, `kind`, `isMuted`, `isLocked`, `voiceOverOnTop`)과 클립의 모든 렌더링 속성(`id`, `assetId`, `compoundId`, `timelineRange`, `sourceRange`, `playbackRate`, `isReversed`, `volume`, `opacity`, `blendMode`, `transitionToNext`, `effects`, `colorCorrection`, `colorGrade`, `transform`, `cropRect`, `mask`, `keyframes`, `speedRampPoints`, `stabilization`)이 해시에 반영되도록 확장합니다.

---

### Task 3.2: `ClipTimeMapping` 고정밀 Rational Timescale 헬퍼 추가

#### 대상 파일
- `Sources/MovieCutCore/Timeline/ClipTimeMapping.swift`

#### 수정 사항 상세
- `ClipTimeMapping`에 `public static let canonicalTimescale: CMTimeScale = 60000` 상수와 `public static func cmTime(seconds: Double, preferredTimescale: CMTimeScale = ClipTimeMapping.canonicalTimescale) -> CMTime` 헬퍼를 추가합니다.

#### Phase 3 검증 명령어
```bash
swift build
swift test --filter CompoundFlattenerTests
```

---

## Phase 4: 오디오 엔진 동기화 및 DSP 최적화 (Audio Engine & DSP)

### Task 4.1: `AudioGraphOfflineRenderer` 샘플 루프 내 정렬(Sorting) 할당 제거 및 이진 탐색($O(\log K)$) 적용

#### 대상 파일
- `Sources/MovieCutCore/Audio/AudioGraphRendering.swift`

#### 수정 사항 상세
- `automationValue(_:at:)` (L240~L260)에서 매 샘플마다 호출되던 `points.sorted` 및 `zip(sorted, sorted.dropFirst())`를 제거하고, 단일 포인트($O(1)$) 패스트패스, 정렬 여부 확인 후 이진 탐색($O(\log K)$)으로 교체합니다.
- `stripFrame` (L200~L236)에서 `0 dB`일 때 불필요한 `pow(10.0, db / 20.0)` 호출을 건너뛰는 `dbToLinear(_:)` 헬퍼를 적용합니다.

---

### Task 4.2: `AudioGraphEngines.StripStream.fill` 이중 락(Lock) 획득 제거

#### 대상 파일
- `Sources/MovieCutCore/Audio/AudioGraphEngines.swift`

#### 수정 사항 상세
- `StripStream.fill` (L243~L246)에서 두 번 연속 호출하던 `cursor.withLock`을 단일 `withLock` 호출로 통합합니다.

#### Phase 4 검증 명령어
```bash
swift build
swift test --filter AudioGraphTests
```

---

## Phase 5: 타임라인 UI 가상화 및 미디어 제너레이터 최적화 (UI & Media Generators)

### Task 5.1: `WaveformGenerator` Zero-Copy 블록 버퍼 읽기 및 부분 구간(`timeRange`) 디코딩 지원

#### 대상 파일
- `Sources/MovieCutCore/Media/WaveformGenerator.swift`

#### 수정 사항 상세
- `decodeWaveform(at:)` (L120~L136)에서 매 샘플 버퍼마다 `[UInt8]` 배열을 새로 할당해 복사하는 대신 `CMBlockBufferGetDataPointer`로 연속 메모리를 직접 읽고, 비연속 버퍼일 때만 재사용 버퍼(`scratchBytes`)를 사용하도록 변경합니다.
- 선택적 `timeRange: TimeRange? = nil`을 받아 `AVAssetReader.timeRange`에 전달할 수 있는 오버로드를 추가합니다.

---

### Task 5.2: `FilmstripGenerator` 썸네일 바이트 해싱 최적화

#### 대상 파일
- `App/MovieCutMac/Media/FilmstripGenerator.swift`

#### 수정 사항 상세
- `Self.digest(for: image)` (L332~L349)에서 전체 픽셀 데이터를 매 바이트 순회하는 대신 `CFDataGetBytePtr`와 고정 샘플링 스트라이드(`max(1, length / 512)`)를 사용하여 힙 복사를 없애고 해싱 비용을 $O(1)$ 상수 시간으로 단축합니다.

---

### Task 5.3: `TimelineView` (macOS) 룰러/그리드 Step 하한 방어 및 `IOSTimelineView` (iOS) 클립 폭 개선

#### 대상 파일
- `App/MovieCutMac/TimelineView.swift`
- `App/MovieCutiOS/IOSTimelineView.swift`

#### 수정 사항 상세
- `TimelineView.swift`의 `timeRuler` (L726) 및 `timelineGridLines` (L809)에서 줌아웃 시 그리는 눈금/선 개수가 250개를 넘지 않도록 `step`을 동적으로 배수 조정하는 가드를 추가합니다.
- `IOSTimelineView.swift`의 `width(for:)` (L286~L288)에서 `min(360, ...)` 상한을 `min(2400, ...)`로 완화하여 클립 길이에 비례하는 타임라인 폭을 표시합니다(기존 `accessibilityIdentifier` 절대 유지).

#### Phase 5 검증 명령어
```bash
swift build
swift test --filter WaveformGeneratorTests
```

---

## 최종 점검 명령어 (Final Verification Command)

```bash
swift build && swift test --filter "RenderCacheTests|ReverseRenderServiceTests|CompoundFlattenerTests|AudioGraphTests|WaveformGeneratorTests"
```
