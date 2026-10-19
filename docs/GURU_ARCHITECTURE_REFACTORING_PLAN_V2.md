# MovieCut NLE 코어 엔진 2차 아키텍처 리팩터링 상세 계획서 (GURU Refactoring Plan V2)

> **문서 목적**: 1차 아키텍처 리팩터링(`49a0668`) 이후 남아 있는 **2차 심층 병목(Hot-path CPU/Heap Allocation 폭탄, 정적 오버레이 매 프레임 재래스터화, 정적 이미지 150회 중복 드로잉, iOS 역재생 임시 파일 디스크 누수, 오디오 라우드니스 수천만 회 배열 할당, UI 클립 뷰포트 컬링 및 iOS Chase-Seek 누락)**을 제거하기 위한 단계별(Phase 1~5) 상세 작업 명세서입니다.  
> 다른 개발 세션에서 문맥 오해 없이 **오직 코드 구현만 즉시 진행**할 수 있도록 수정 대상 파일, 정확한 라인 번호, Before/After 코드 스니펫, 그리고 과도한 테스트를 배제한 최소 검증 명령어를 정의합니다.

---

## ⚠️ 작업자(에이전트) 필수 준수 규칙 (Strict Constraints)

1. **과도한 테스트 절대 금지**:
   - 전체 테스트 스위트(`swift test` 전체 실행), UI 테스트(`MovieCutUITests`), E2E 하네스(`--e2e-*`), 장시간 미디어 렌더링 테스트를 **절대 실행하지 마십시오.**
   - 각 Phase 완료 시 본 문서에 명시된 `swift build` 또는 단일 타겟 유닛 테스트(`swift test --filter <TestClassName>`)만 1회 실행하여 컴파일 및 핵심 로직 무결성만 빠르게 확인합니다.
2. **하위 호환성 및 기존 테스트 계약 유지**:
   - `public` API 시그니처와 기존 타입 이름을 깨뜨리지 마십시오(필요시 오버로드 또는 기본 인자 활용).
   - `EditorSession.commandCount`는 누적 디스패치 횟수를 반환해야 하므로, `undoStack` 상한(Cap)을 적용할 때 별도의 카운터로 기존 계약을 보존하십시오.
3. **작업 순서 준수**:
   - 아래 **Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5** 순서대로 1개 Phase씩 작업을 완결하십시오.

---

## Phase 1: 렌더링 및 컴포지션 파이프라인 (Render Graph & Compositing)

### 목표
1. **`CurveEvaluator` & `ColorGradePixelProcessor`**: $64^3 = 262,144$ 루프에서 $1,572,864$회 호출되던 `CurveEvaluator.evaluate`의 매 호출 딕셔너리/배열 할당을 제거하고, 1D 분리형(Separable) LUT 사전 평가로 연산량을 **$8,192\times$ 단축**합니다.
2. **`HSLCubeBuilder`**: $262,144$회 반복 호출되는 `apply(_:bands:)` 내부의 `bands.filter { !$0.isIdentity }` 힙 배열 할당을 루프 밖 1회로 이동합니다.
3. **`TextOverlayPixelProcessor` & 스티커 오버레이**: 정적 자막 및 스티커가 유지되는 동안 매 프레임 전체 해상도 `CGContext` 할당 + `CIImage(cgImage:)` 텍스처 업로드를 반복하지 않도록 렌더링된 오버레이 `CIImage`를 `NSCache`로 캐싱합니다.
4. **`ScopeAnalyzer` & `EditorViewModel.refreshScopes`**: 픽셀 버퍼를 4번 중복 순회하던 스코프 계산을 단일 패스(`analyzeAll`) + 정수 루마 연산으로 통합합니다.

---

### 1.1 [`Sources/MovieCutCore/Rendering/CurveEvaluator.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/CurveEvaluator.swift)
* **위치**: 라인 32~74 (`evaluate(points:at:)`, `lut(points:size:)`)
* **수정 내용**:
  - 사전 정규화된 포인트(`normalized`)와 접선(`tangents`)을 받아 **할당 없이(Zero-allocation)** 보간값만 계산하는 `public static func evaluatePrecomputed(normalized: [CurvePoint], tangents: [Double], at x: Double) -> Double` 및 `public static func prepare(_ points: [CurvePoint]) -> (normalized: [CurvePoint], tangents: [Double])` 헬퍼를 추가합니다.
  - `lut(points:size:)`가 루프 밖에서 `prepare(points)`를 **단 1회**만 호출한 뒤 `evaluatePrecomputed`를 실행하도록 변경합니다.

```swift
    public static func prepare(_ points: [CurvePoint]) -> (normalized: [CurvePoint], tangents: [Double]) {
        let normalized = normalizedPoints(points)
        let tangents = monotoneTangents(normalized)
        return (normalized, tangents)
    }

    public static func evaluatePrecomputed(
        normalized points: [CurvePoint],
        tangents: [Double],
        at x: Double
    ) -> Double {
        let x = x.clamped(to: 0...1, fallback: 0)
        guard points.count > 1 else { return x }
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }

        // 이진 탐색으로 구간 탐색
        var low = 0
        var high = points.count - 1
        while low < high {
            let mid = (low + high) / 2
            if points[mid].x < x {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let upperIndex = low
        let lowerIndex = max(0, upperIndex - 1)
        let lower = points[lowerIndex]
        let upper = points[upperIndex]

        guard upper.x > lower.x else { return lower.y.clamped(to: 0...1, fallback: 0) }

        let h = upper.x - lower.x
        let t = (x - lower.x) / h
        let t2 = t * t
        let t3 = t2 * t

        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        let y = h00 * lower.y
            + h10 * h * tangents[lowerIndex]
            + h01 * upper.y
            + h11 * h * tangents[upperIndex]

        return y.clamped(to: 0...1, fallback: 0)
    }

    public static func evaluate(points: [CurvePoint], at x: Double) -> Double {
        let prepared = prepare(points)
        return evaluatePrecomputed(normalized: prepared.normalized, tangents: prepared.tangents, at: x)
    }

    public static func lut(points: [CurvePoint], size: Int = defaultLUTSize) -> [Double] {
        let sampleCount = max(size, 2)
        let prepared = prepare(points)
        return (0..<sampleCount).map { index in
            if index == 0 { return 0 }
            if index == sampleCount - 1 { return 1 }
            return evaluatePrecomputed(
                normalized: prepared.normalized,
                tangents: prepared.tangents,
                at: Double(index) / Double(sampleCount - 1)
            )
        }
    }
```

---

### 1.2 [`Sources/MovieCutCore/Rendering/ColorGradePixelProcessor.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/ColorGradePixelProcessor.swift)
* **위치**: 라인 106~131 (`curveCubeData(size:curves:)`, `applyCurves(to:master:channel:)`)
* **수정 내용**:
  - `curveCubeData`에서 $64^3$ 루프를 돌기 전에, `0..<size`의 각 그리드 인덱스에 대해 R, G, B 최종 1D 룩업 테이블(`redTable`, `greenTable`, `blueTable`: `[Float]`)을 **단 64회씩만** 먼저 계산합니다.
  - 3D 루프 내부에서는 함수 호출 없이 `redTable[redIndex]`, `greenTable[greenIndex]`, `blueTable[blueIndex]`를 즉시 인덱싱하여 채웁니다.

```swift
    private static func curveCubeData(size: Int, curves: ColorCurves) -> [Float] {
        let size = max(size, 2)
        let masterPrepared = CurveEvaluator.prepare(curves.master)
        let redPrepared = CurveEvaluator.prepare(curves.red)
        let greenPrepared = CurveEvaluator.prepare(curves.green)
        let bluePrepared = CurveEvaluator.prepare(curves.blue)

        var redTable = [Float](repeating: 0, count: size)
        var greenTable = [Float](repeating: 0, count: size)
        var blueTable = [Float](repeating: 0, count: size)
        let denom = Double(size - 1)

        for i in 0..<size {
            let x = Double(i) / denom
            let m = CurveEvaluator.evaluatePrecomputed(
                normalized: masterPrepared.normalized,
                tangents: masterPrepared.tangents,
                at: x
            )
            redTable[i] = Float(CurveEvaluator.evaluatePrecomputed(
                normalized: redPrepared.normalized,
                tangents: redPrepared.tangents,
                at: m
            ))
            greenTable[i] = Float(CurveEvaluator.evaluatePrecomputed(
                normalized: greenPrepared.normalized,
                tangents: greenPrepared.tangents,
                at: m
            ))
            blueTable[i] = Float(CurveEvaluator.evaluatePrecomputed(
                normalized: bluePrepared.normalized,
                tangents: bluePrepared.tangents,
                at: m
            ))
        }

        var data = [Float](repeating: 1, count: size * size * size * 4)
        var offset = 0
        for blueIndex in 0..<size {
            let bVal = blueTable[blueIndex]
            for greenIndex in 0..<size {
                let gVal = greenTable[greenIndex]
                for redIndex in 0..<size {
                    data[offset] = redTable[redIndex]
                    data[offset + 1] = gVal
                    data[offset + 2] = bVal
                    // data[offset + 3] is already 1.0
                    offset += 4
                }
            }
        }
        return data
    }
```

---

### 1.3 [`Sources/MovieCutCore/Rendering/HSLCubeBuilder.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/HSLCubeBuilder.swift)
* **위치**: 라인 24~73 (`cube(size:bands:)`, `apply(_:bands:)`)
* **수정 내용**:
  - `cube(size:bands:)` 시작 시 `let activeBands = bands.filter { !$0.isIdentity }`를 1회만 구하고, 내부 헬퍼 `applyActive(_:activeBands:)`를 호출하여 262,144회의 배열 필터링 할당을 제거합니다.

```swift
    public static func cube(size: Int = 64, bands: [HSLBand]) -> [Float] {
        let size = max(size, 2)
        let activeBands = bands.filter { !$0.isIdentity }
        var data = [Float](repeating: 1, count: size * size * size * 4)
        let denom = Double(size - 1)
        var offset = 0

        for blueIndex in 0..<size {
            let b = Double(blueIndex) / denom
            for greenIndex in 0..<size {
                let g = Double(greenIndex) / denom
                for redIndex in 0..<size {
                    let rgb = RGB(red: Double(redIndex) / denom, green: g, blue: b)
                    let adjusted = applyActive(rgb, activeBands: activeBands)
                    data[offset] = Float(adjusted.red)
                    data[offset + 1] = Float(adjusted.green)
                    data[offset + 2] = Float(adjusted.blue)
                    offset += 4
                }
            }
        }
        return data
    }

    public static func apply(_ rgb: RGB, bands: [HSLBand]) -> RGB {
        let activeBands = bands.filter { !$0.isIdentity }
        return applyActive(rgb, activeBands: activeBands)
    }

    private static func applyActive(_ rgb: RGB, activeBands: [HSLBand]) -> RGB {
        guard !activeBands.isEmpty else { return rgb }
        // 기존 apply 본문(라인 52~72)과 동일
```

---

### 1.4 [`Sources/MovieCutCore/Rendering/TextOverlayPixelProcessor.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/TextOverlayPixelProcessor.swift)
* **위치**: 라인 33~92 (`TextOverlayPixelProcessor.apply`)
* **수정 내용**:
  - `private nonisolated(unsafe) static let overlayCache: NSCache<NSString, CIImage> = { let c = NSCache<NSString, CIImage>(); c.countLimit = 32; return c }()`를 추가합니다.
  - 각 `activeItems`의 현재 프레임 해석 상태(`textState`, `effectiveOpacity`, `activeKaraokeWordCount`, `renderSize`, `item.textContent`, `item.transform`)를 조합한 캐시 키 `cacheKey`를 생성합니다.
  - 캐시 히트 시 `CGContext` 생성 및 CoreText 렌더링을 완전히 건너뛰고 캐싱된 `CIImage`를 즉시 합성합니다.

```swift
    private nonisolated(unsafe) static let overlayCache: NSCache<NSString, CIImage> = {
        let cache = NSCache<NSString, CIImage>()
        cache.countLimit = 32
        return cache
    }()

    private static func resolvedCacheKey(
        for activeItems: [TextOverlayRenderItem],
        width: Int,
        height: Int,
        renderSize: CGSize,
        at time: TimeInterval
    ) -> NSString {
        var parts: [String] = ["\(width)x\(height)"]
        parts.reserveCapacity(activeItems.count + 1)
        for item in activeItems {
            let tc = item.textContent
            let state = animatedTextState(for: tc, item: item, renderSize: renderSize, at: time)
            let localTime = karaokeLocalTime(for: item, at: time)
            let activeKaraokeIndex: Int
            if tc.karaokeEnabled, let timings = tc.wordTimings, !timings.isEmpty {
                activeKaraokeIndex = timings.lastIndex(where: { $0.startTime <= localTime }) ?? -1
            } else {
                activeKaraokeIndex = -2
            }
            parts.append(
                "\(tc.text)|\(tc.fontFamily)|\(tc.fontSize)|\(tc.fontColor)|\(tc.backgroundColor ?? "")|" +
                "\(tc.isBold)|\(tc.isItalic)|\(tc.alignment.rawValue)|\(tc.position.x),\(tc.position.y)|" +
                "\(tc.strokeColor ?? ""):\(tc.strokeWidth ?? 0)|\(tc.shadowColor ?? ""):\(tc.shadowBlur ?? 0)|" +
                "\(tc.highlightFontColor ?? ""):\(activeKaraokeIndex)|" +
                "\(item.transform.position.x),\(item.transform.position.y),\(item.transform.offset.x),\(item.transform.offset.y)," +
                "\(item.transform.scale.width),\(item.transform.scale.height),\(item.transform.rotation)|" +
                "\(item.opacity)|\(state.visibleText)|\(state.opacity)|\(state.scale)|" +
                "\(state.translation.x),\(state.translation.y)|\(state.rotationDegrees)"
            )
        }
        return parts.joined(separator: "||") as NSString
    }
```
  - `apply(_:to:at:)` 내부에서 `width`, `height` 계산 직후:
    ```swift
    let cacheKey = resolvedCacheKey(for: activeItems, width: width, height: height, renderSize: renderSize, at: time)
    let baseOverlay: CIImage
    if let cached = overlayCache.object(forKey: cacheKey) {
        baseOverlay = cached
    } else {
        // 기존 CGContext 생성 + draw + makeImage 수행
        ...
        let created = CIImage(cgImage: cgImage)
        overlayCache.setObject(created, forKey: cacheKey)
        baseOverlay = created
    }
    var overlay = baseOverlay
    ```

---

### 1.5 [`Sources/MovieCutCore/Rendering/ScopeAnalyzer.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/ScopeAnalyzer.swift) & [`App/MovieCutMac/EditorViewModel.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutMac/EditorViewModel.swift)
* **위치**:
  - `ScopeAnalyzer.swift` 라인 22~162
  - `EditorViewModel.swift` 라인 2855~2899 (`refreshScopes()`)
* **수정 내용**:
  - `ScopeAnalyzer`에 4개 스코프 결과를 한 번의 픽셀 루프로 동시에 집계하는 `public struct AllScopes: Sendable, Equatable` 및 `public static func analyzeAll(rgba: [UInt8], width: Int, height: Int, histogramBins: Int = 64, waveformColumns: Int, waveformLevels: Int = 48, vectorscopeSize: Int = 48) -> AllScopes`를 추가합니다.
  - `EditorViewModel.refreshScopes()`에서 4번의 개별 호출(라인 2895~2898)을 `let all = ScopeAnalyzer.analyzeAll(rgba: bytes, width: width, height: height, histogramBins: 64, waveformColumns: width, waveformLevels: 48, vectorscopeSize: 48)` 단일 호출로 교체합니다.

---

## Phase 2: 디코딩, 인코딩 및 미디어 I/O (Hardware Acceleration & Media I/O)

### 목표
1. **`ImageVideoRenderService`**: `kenBurnsEffect == nil`인 정적 이미지 클립을 렌더링할 때 매 프레임 CPU `CGContext.draw`를 반복하지 않고, 루프 밖에서 **단 1회**만 그린 `CVPixelBuffer`를 모든 프레임 타임스탬프에 재사용합니다.
2. **`PlaybackEngine` & `IOSExportEngine` 이미지 세그먼트 캐싱 + iOS 역재생 디스크 누수 차단**:
   - 프리뷰/익스포트 컴포지션 리빌드 시 변경되지 않은 이미지 클립의 `.mp4` 세그먼트를 캐싱하여 재인코딩을 방지합니다.
   - `IOSExportEngine.renderReversedAsset`가 생성한 임시 `.mov` 파일을 `imageRenderURLs`에 등록하여 컴포지션 해제 시 확실히 정리되도록 디스크 누수를 수정합니다.

---

### 2.1 [`Sources/MovieCutCore/Rendering/ImageVideoRenderService.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/ImageVideoRenderService.swift)
* **위치**: 라인 84~108 (`render(imageURL:duration:renderSize:outputURL:kenBurnsEffect:)`)
* **수정 내용**:
  - `kenBurnsEffect == nil`인 경우 첫 번째 프레임에서 그린 `staticPixelBuffer: CVPixelBuffer?`를 보관하여 이후 프레임에서는 `Self.draw(...)` 및 `CVPixelBufferPoolCreatePixelBuffer` 호출 없이 `adaptor.append(staticPixelBuffer, withPresentationTime: presentationTime)`만 호출합니다.

```swift
        let totalFrames = max(Int(ceil(duration * Double(Self.frameRate))), 1)
        var cachedStaticPixelBuffer: CVPixelBuffer?

        for frameIndex in 0..<totalFrames {
            try Task.checkCancellation()
            try await Self.waitForWriterInput(writerInput, writer: writer)

            let pixelBuffer: CVPixelBuffer
            if kenBurnsEffect == nil, let existing = cachedStaticPixelBuffer {
                pixelBuffer = existing
            } else {
                guard let pool = adaptor.pixelBufferPool else {
                    throw ImageVideoRenderServiceError.pixelBufferPoolUnavailable
                }
                var createdBuffer: CVPixelBuffer?
                let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &createdBuffer)
                guard status == kCVReturnSuccess, let unwrapped = createdBuffer else {
                    throw ImageVideoRenderServiceError.pixelBufferCreationFailed(status)
                }
                let progress = totalFrames > 1
                    ? Double(frameIndex) / Double(totalFrames - 1)
                    : 0
                try Self.draw(image, into: unwrapped, size: outputSize, kenBurnsEffect: kenBurnsEffect, progress: progress)
                if kenBurnsEffect == nil {
                    cachedStaticPixelBuffer = unwrapped
                }
                pixelBuffer = unwrapped
            }

            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: Self.frameRate)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? ImageVideoRenderServiceError.appendFailed
            }
        }
```

---

### 2.2 [`App/MovieCutMac/Playback/PlaybackEngine.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutMac/Playback/PlaybackEngine.swift) & [`App/MovieCutiOS/Export/IOSExportEngine.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutiOS/Export/IOSExportEngine.swift)
* **위치**:
  - `PlaybackEngine.swift` 라인 928~943 및 라인 1771~1815
  - `IOSExportEngine.swift` 라인 1042~1057 및 라인 1272~1276, 1521~1541
* **수정 내용**:
  1. **`PlaybackEngine`**:
     - `equalizedPreviewAudio`와 동일한 패턴으로 `private struct ImagePreviewCacheKey: Equatable { let sourceURL: URL; let durationMs: Int64; let width: Int; let height: Int; let kenBurns: KenBurnsEffect? }` 및 `private var cachedImagePreviewSegments: [UUID: (key: ImagePreviewCacheKey, url: URL)] = [:]`를 추가합니다.
     - `mediaAsset.kind == .image` 분기에서 캐시 키가 일치하고 파일이 존재하면 `ImageVideoRenderService().render`를 건너뛰고 즉시 캐시된 `url`을 사용합니다(`temporaryReverseRenderURLs`에는 넣지 않고 `cleanupTemporaryEqualizedPreviewURLs()`에서 함께 정리).
  2. **`IOSExportEngine`**:
     - `insertClip`(라인 1272~1276)에서 `renderReversedAsset(for: clip, from: asset)` 호출이 반환한 `reversedURL`을 `imageRenderURLs.append(reversedURL)`에 반드시 등록하여, 플랜 교체 및 정리 시 임시 `.mov` 파일이 디스크에 누수되지 않도록 수정합니다.

---

## Phase 3: 타임라인 데이터 모델 및 동시성 (Timeline Data Model & Concurrency)

### 목표
1. **`EditorViewModel.restorePlaybackAfterRebuild` & `PlaybackEngine.loadProject`**:
   - `EditorViewModel`의 20ms 슬립 폴링 루프(`for _ in 0..<150`)를 제거하고, `PlaybackEngine.loadProject`의 `playbackRestoreAfterRebuild` 메커니즘으로 복원 경로를 단일화하여 레이스 컨디션과 불필요한 폴링 태스크를 없앱니다.
2. **`EditorSession`**:
   - `undoStack`이 무한정 증가하지 않도록 `maxUndoHistory = 200` 상한을 도입하되, `commandCount` 프로퍼티는 누적 디스패치 횟수(`dispatchedCommandCount`)를 그대로 반환하도록 유지합니다.

---

### 3.1 [`App/MovieCutMac/Playback/PlaybackEngine.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutMac/Playback/PlaybackEngine.swift) & [`App/MovieCutMac/EditorViewModel.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutMac/EditorViewModel.swift)
* **위치**:
  - `PlaybackEngine.swift` 라인 118, 213~279
  - `EditorViewModel.swift` 라인 4591~4636
* **수정 내용**:
  1. `PlaybackEngine`의 `playbackRestoreAfterRebuild` 튜플을 `(time: TimeInterval, wasPlaying: Bool, volume: Float?)?`로 확장하고, `func schedulePlaybackRestore(time: TimeInterval, wasPlaying: Bool, volume: Float? = nil)` 메서드를 제공합니다.
  2. `PlaybackEngine.loadProject` 완료 시점(라인 270~278)에서 `restore`가 있으면:
     ```swift
     if let restore = playbackRestoreAfterRebuild {
         playbackRestoreAfterRebuild = nil
         if let volume = restore.volume {
             self.player.volume = volume
         }
         let clampedTarget = min(max(0, restore.time), self.duration)
         if clampedTarget > 0 {
             self.seek(to: clampedTarget)
         }
         if restore.wasPlaying {
             self.play()
         }
     }
     ```
  3. `EditorViewModel.rebuildPreviewComposition(preservingPlayback:)`(라인 4591~4608)에서 `preserve == true`일 때 `playbackEngine.schedulePlaybackRestore(time: snapshotTime, wasPlaying: wasPlaying, volume: Float(snapshotVolume))`를 먼저 등록한 뒤 `playbackEngine.loadProject(project, audioProcessing: audio)`를 호출하고, 기존의 20ms 폴링 함수 `restorePlaybackAfterRebuild`를 제거합니다.

---

### 3.2 [`Sources/MovieCutCore/EditorAPI/EditorSession.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/EditorAPI/EditorSession.swift)
* **위치**: 라인 11~99
* **수정 내용**:
  - `public static let maxUndoHistory = 200` 상수를 추가하고, `private var dispatchedCommandCount: Int = 0`을 추가합니다.
  - `dispatch(_:planId:expectedRevision:)`에서 `dispatchedCommandCount += 1`을 기록하고, `undoStack.count > Self.maxUndoHistory`이면 `undoStack.removeFirst(undoStack.count - Self.maxUndoHistory)`로 오래된 스냅샷을 정리합니다.
  - `undo()` 실행 시 `dispatchedCommandCount = max(0, dispatchedCommandCount - 1)`, `redo()` 실행 시 `dispatchedCommandCount += 1`로 기존 `undoStack.count` 기반의 `commandCount` 동작과 100% 동일한 시맨틱을 보장합니다.

---

## Phase 4: 오디오 엔진 동기화 및 DSP 처리 (Audio-Visual Sync & Processing)

### 목표
1. **`AudioGraphLoudness` & `Oversampler`**:
   - 샘플 프레임마다 `Array<Double>`을 힙에 할당하던 `measure(_:)`, `Analyzer.push(_:)`, `Oversampler.push(_:)`를 **Zero-Allocation** 구조로 리팩터링하여 5분 스테레오 오디오 기준 **4,320만 번의 힙 할당을 0회**로 제거합니다.
2. **`AudioGraphOfflineRenderer.render`**:
   - `spec.clipStrips`와 `spec.sources`를 루프 진입 전 Dictionary로 인덱싱($O(1)$ 조회)하고, 버스/마스터 볼륨 오토메이션이 정적(단일 포인트 또는 빈 배열)일 때 루프 밖에서 상수로 사전 계산합니다.

---

### 4.1 [`Sources/MovieCutCore/Audio/AudioGraphLoudness.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Audio/AudioGraphLoudness.swift)
* **위치**: 라인 43~54 (`measure`), 라인 162~188 (`Oversampler.push`), 라인 228~260 (`Analyzer.push`)
* **수정 내용**:
  1. `Oversampler`에 `[Double]` 배열 할당 없이 4개 위상의 최대 절댓값(`Double`)만 즉시 계산하여 반환하는 `mutating func pushAndMaxAbs(_ input: Double) -> Double` 메서드를 추가합니다(기존 `push(_:)`는 테스트 호환성을 위해 유지).
  2. `Analyzer`에 배열 할당 없이 스테레오/모노 프레임을 즉시 처리하는 `mutating func pushFrame(ch0: Double, ch1: Double)` 메서드를 추가합니다.
  3. `AudioGraphLoudness.measure(_:)`가 루프 내에서 `[Double]` 배열을 생성하지 않고 `analyzer.pushFrame(ch0: s0, ch1: s1)`을 직접 호출하도록 변경합니다.

```swift
        // Oversampler 내부에 추가:
        mutating func pushAndMaxAbs(_ input: Double) -> Double {
            if framesSeen == 0 {
                for index in 0..<Self.historyLength { history[index] = input }
            }
            history[historyIndex] = input
            historyIndex = (historyIndex + 1) % Self.historyLength
            framesSeen += 1
            let newest = (historyIndex - 1 + Self.historyLength) % Self.historyLength
            var maxAbs = 0.0
            for phase in 0..<4 {
                let coeffs = phaseCoefficients[phase]
                var accumulator = 0.0
                for k in -Self.halfTaps...Self.halfTaps {
                    let age = Self.halfTaps + k
                    var index = newest - age
                    if index < 0 { index += Self.historyLength }
                    accumulator += coeffs[k + Self.halfTaps] * history[index]
                }
                let absVal = abs(accumulator)
                if absVal > maxAbs { maxAbs = absVal }
            }
            return maxAbs
        }
```

```swift
    // AudioGraphLoudness.measure 교체:
    public static func measure(_ audio: AudioGraphSourceAudio) -> Measurement {
        var analyzer = Analyzer(sampleRate: audio.sampleRate, channels: audio.channels)
        let channels = max(1, min(2, audio.channels))
        if channels == 1 {
            for frame in 0..<audio.frameCount {
                let s0 = Double(audio.sample(frame: frame, channel: 0))
                analyzer.pushFrame(ch0: s0, ch1: 0)
            }
        } else {
            for frame in 0..<audio.frameCount {
                let s0 = Double(audio.sample(frame: frame, channel: 0))
                let s1 = Double(audio.sample(frame: frame, channel: 1))
                analyzer.pushFrame(ch0: s0, ch1: s1)
            }
        }
        return analyzer.finish()
    }
```

---

### 4.2 [`Sources/MovieCutCore/Audio/AudioGraphRendering.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Audio/AudioGraphRendering.swift)
* **위치**: 라인 143~183 (`AudioGraphOfflineRenderer.render`)
* **수정 내용**:
  - 루프 진입 전에 `let stripsById = Dictionary(uniqueKeysWithValues: spec.clipStrips.map { ($0.clipId, $0) })` 및 `let sourcesById = Dictionary(uniqueKeysWithValues: spec.sources.map { ($0.id, $0) })`를 구성하여 $O(N)$ 선형 탐색을 $O(1)$ 해시 조회로 변경합니다.

---

## Phase 5: UI/UX 퍼포먼스 및 크로스플랫폼 아키텍처 (macOS & iOS/iPadOS)

### 목표
1. **`TimelineFilmstripImageStripNSView` (`TimelineFilmstripStore.swift`)**:
   - `NSImage` 래퍼 배열 할당을 제거하고 `[CGImage]`를 직접 보유하며, `draw(_ dirtyRect: NSRect)`에서 `dirtyRect.intersects(targetRect)` 컬링 및 `CGContext` 직접 드로잉을 수행합니다.
2. **`TimelineView.swift` (`clipsForDisplay`)**:
   - 트랙 내 클립 수가 많을 때(> 32개) 수평 스크롤 뷰포트(`[minVisibleTime, maxVisibleTime]`)와 교차하는 클립(+ 선택된 클립 및 드래그 중인 클립)만 렌더링하여 SwiftUI 뷰 그래프 비용을 $O(1)$로 고정합니다(32개 이하일 때는 기존 UI/접근성 테스트 호환성을 위해 전체 반환).
3. **`PreviewView.swift` (iOS Chase-Seek)**:
   - iOS `PreviewView.seekPlayer(to:coalescingSmallMoves:)`에 macOS `PlaybackEngine`과 동일한 Chase-Seek(`isSeeking` + `pendingSeekTime`) 상태 머신을 적용하여 스크러빙 시 VideoToolbox 디코더 큐 스래싱을 방지합니다.

---

### 5.1 [`App/MovieCutMac/Media/TimelineFilmstripStore.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutMac/Media/TimelineFilmstripStore.swift)
* **위치**: 라인 605~665 (`TimelineFilmstripImageStripNSView`)
* **수정 내용**:
  - `private var images: [NSImage] = []`를 `private var cgImages: [CGImage] = []`로 교체합니다.
  - `configure(frames:...)`에서 `cgImages = frames.map(\.image)`만 저장합니다.
  - `draw(_ dirtyRect: NSRect)`에서 `guard dirtyRect.intersects(targetRect) else { continue }`로 화면 밖 타일을 스킵하고, `NSGraphicsContext.current?.cgContext`를 사용해 aspect-fill 클리핑 후 `cgImage`를 직접 그립니다.

```swift
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        cgContext.interpolationQuality = .low
        let availableWidth = max(1, bounds.width - CGFloat(max(0, cgImages.count - 1)))
        let frameWidth = availableWidth / CGFloat(cgImages.count)
        for (index, cgImage) in cgImages.enumerated() {
            let targetRect = NSRect(
                x: CGFloat(index) * (frameWidth + 1),
                y: 0,
                width: frameWidth,
                height: bounds.height
            )
            guard dirtyRect.intersects(targetRect) else { continue }
            let imageSize = NSSize(width: cgImage.width, height: cgImage.height)
            guard imageSize.width > 0, imageSize.height > 0,
                  targetRect.width > 0, targetRect.height > 0 else { continue }

            let scale = max(targetRect.width / imageSize.width, targetRect.height / imageSize.height)
            let drawWidth = imageSize.width * scale
            let drawHeight = imageSize.height * scale
            let drawRect = CGRect(
                x: targetRect.minX + (targetRect.width - drawWidth) * 0.5,
                y: targetRect.minY + (targetRect.height - drawHeight) * 0.5,
                width: drawWidth,
                height: drawHeight
            )
            cgContext.saveGState()
            cgContext.clip(to: targetRect)
            cgContext.draw(cgImage, in: drawRect)
            cgContext.restoreGState()
        }
```

---

### 5.2 [`App/MovieCutMac/TimelineView.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutMac/TimelineView.swift)
* **위치**: 라인 25~27 (`@State` 프로퍼티), 라인 722 (`timeRuler`), 라인 1865~1867 (`clipsForDisplay`)
* **수정 내용**:
  1. `@State private var timelineScrollOffsetX: CGFloat = 0` 프로퍼티를 추가합니다.
  2. `timeRuler` 내부 `ZStack(alignment: .topLeading)`의 `.background`에 뷰포트 스크롤 오프셋 리더(64pt 단위 양자화로 불필요한 리렌더 방지)를 부착합니다:
     ```swift
     private var timelineScrollOffsetReader: some View {
         GeometryReader { proxy in
             let rawOffset = max(0, -proxy.frame(in: .named(TimelineFilmstripCoordinateSpace.viewport)).minX)
             let quantized = (rawOffset / 64).rounded(.down) * 64
             Color.clear
                 .onAppear { timelineScrollOffsetX = quantized }
                 .onChange(of: quantized) { _, newValue in
                     timelineScrollOffsetX = newValue
                 }
         }
     }
     ```
  3. `clipsForDisplay(_ track: Track) -> [Clip]`에서 클립 수가 32개를 초과할 때 현재 가시 시간 범위(`[minTime, maxTime]`, 좌우 600pt 버퍼)와 겹치거나 선택/드래그 중인 클립만 반환합니다:
     ```swift
     private func clipsForDisplay(_ track: Track) -> [Clip] {
         let all = track.clipsForLayerDisplay
         guard all.count > 32, pixelsPerSecond > 0 else {
             return all
         }
         let marginPt: CGFloat = 600
         let minX = max(0, timelineScrollOffsetX - marginPt)
         let maxX = timelineScrollOffsetX + max(timelineScrollViewportWidth, 900) + marginPt
         let minTime = Double(minX) / pixelsPerSecond
         let maxTime = Double(maxX) / pixelsPerSecond
         let selectedId = viewModel.selectedClipId
         let activeDraggedId = draggedClipId

         return all.filter { clip in
             if clip.id == selectedId || clip.id == activeDraggedId {
                 return true
             }
             return clip.timelineRange.end >= minTime && clip.timelineRange.start <= maxTime
         }
     }
     ```

---

### 5.3 [`App/MovieCutiOS/Views/PreviewView.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutiOS/Views/PreviewView.swift)
* **위치**: 라인 15~25 (`@State` 프로퍼티), 라인 302~318 (`seekPlayer(to:coalescingSmallMoves:)`)
* **수정 내용**:
  - `@State private var isSeekingPlayer = false` 및 `@State private var pendingSeekTime: TimeInterval?`를 추가합니다.
  - `seekPlayer(to:coalescingSmallMoves:)`에서 이미 `isSeekingPlayer == true`이면 `pendingSeekTime = clampedTime`만 기록하고 즉시 반환하며, `player.seek`의 완료 콜백에서 `pendingSeekTime`이 있으면 연쇄적으로 최신 타겟 위치만 추격(Chase-Seek)하도록 수정합니다.

```swift
    private func seekPlayer(to time: TimeInterval, coalescingSmallMoves: Bool) {
        guard hasPlayableMedia else { return }
        let clampedTime = min(max(0, time), max(viewModel.currentProject.timeline.duration, 0))
        let currentSeconds = player.currentTime().seconds

        if coalescingSmallMoves, currentSeconds.isFinite, abs(currentSeconds - clampedTime) < 0.25 {
            return
        }

        if isSeekingPlayer {
            pendingSeekTime = clampedTime
            return
        }

        performChaseSeek(to: clampedTime)
    }

    private func performChaseSeek(to targetSeconds: TimeInterval) {
        isSeekingPlayer = true
        pendingSeekTime = nil
        player.seek(
            to: cmTime(targetSeconds),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { _ in
            Task { @MainActor in
                if let nextTarget = pendingSeekTime {
                    performChaseSeek(to: nextTarget)
                } else {
                    isSeekingPlayer = false
                }
            }
        }
    }
```

---

## 최소 검증 프로토콜 (Lightweight Verification Protocol)

각 Phase 구현 후 아래의 가벼운 명령어만 실행하여 검증하십시오(전체 테스트나 UI 테스트 실행 금지).

1. **Phase 1 완료 후**:
   ```bash
   swift test --filter CurveEvaluatorTests
   swift test --filter ScopeAnalyzerTests
   ```
2. **Phase 2 & 3 완료 후**:
   ```bash
   swift test --filter EditorSessionTests
   swift build
   ```
3. **Phase 4 완료 후**:
   ```bash
   swift test --filter AudioGraphLoudnessTests
   ```
4. **Phase 5 완료 후 (최종 빌드 검증)**:
   ```bash
   swift build
   ```
