# MovieCut NLE 코어 엔진 3차 아키텍처 리팩터링 상세 계획서 (GURU Refactoring Plan V3)

> **문서 목적**: 1차(`49a0668`) 및 2차(`4ea4653`) 리팩터링 이후 전수 감사(Audit)에서 발견된 **3차 심층 병목(브러시/다각형 마스크 매 프레임 CPU 래스터화, 프리셋 그라디언트 맵 매 프레임 재생성, `ThumbnailGenerator` 매 호출 `CIContext` 할당, `AudioGraphLimiter`의 $O(N \times W)$ 690억 회 중첩 루프, `AudioGraphCompressor` 불필요 초월함수 호출, 드래그 스냅 매 프레임 배열 재할당, 웨이브폼 Canvas 200회 개별 드로우 콜 및 썸네일 PNG 재디코딩)**을 제거하기 위한 단계별(Phase 1~5) 상세 작업 명세서입니다.  
> 다른 개발 세션에서 문맥 오해 없이 **오직 코드 구현만 즉시 진행**할 수 있도록 수정 대상 파일, 정확한 라인 번호, Before/After 코드 스니펫, 그리고 과도한 테스트를 배제한 최소 검증 명령어를 정의합니다.

---

## ⚠️ 작업자(에이전트) 필수 준수 규칙 (Strict Constraints)

1. **과도한 테스트 절대 금지**:
   - 전체 테스트 스위트(`swift test` 전체 실행), UI 테스트(`MovieCutUITests`), E2E 하네스(`--e2e-*`), 장시간 미디어 렌더링 테스트를 **절대 실행하지 마십시오.**
   - 각 Phase 완료 시 본 문서에 명시된 `swift build` 또는 단일 타겟 유닛 테스트(`swift test --filter <TestClassName>`)만 1회 실행하여 컴파일 및 핵심 로직 무결성만 빠르게 확인합니다.
2. **하위 호환성 및 비트/픽셀 정합성 유지**:
   - `public` API 시그니처와 기존 타입 이름을 깨뜨리지 마십시오.
   - 특히 `AudioGraphLimiter.apply`와 `AudioGraphCompressor.apply`는 기존 유닛/골든 테스트와 **수치적으로 완전히 동일한 출력**을 내야 합니다.
3. **작업 순서 준수**:
   - 아래 **Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5** 순서대로 1개 Phase씩 작업을 완결하십시오.

---

## Phase 1: 렌더링 파이프라인 — 마스크 및 그라디언트 맵 텍스처 캐싱

### 목표
1. **`MaskPixelProcessor`**: `.brush`, `.triangle`, `.diamond` 마스크가 적용된 클립에서 매 프레임 전체 해상도 Grayscale `CGContext`를 새로 할당하고 수백 개의 브러시 선분을 다시 그리던 병목을 `NSCache<NSString, CIImage>`(`countLimit = 32`)로 제거합니다.
2. **`VisualEffectPixelProcessor`**: `.cinematic`, `.vintage`, `.vivid`, `.styleTransfer` 프리셋 이펙트가 매 프레임마다 256픽셀 루프를 돌며 `Data` 및 `CIImage(bitmapData:...)`를 재생성하던 병목을 `NSCache<NSString, CIImage>`로 제거합니다.

---

### 1.1 [`Sources/MovieCutCore/Rendering/MaskPixelProcessor.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/MaskPixelProcessor.swift)
* **위치**: 라인 6~54 (`MaskPixelProcessor` 선언부 및 `makeMaskImage`), 라인 185~213 (`drawMask(in:drawing:)`)
* **수정 내용**:
  - `MaskPixelProcessor` 내부에 `private nonisolated(unsafe) static let rasterMaskCache: NSCache<NSString, CIImage> = { let c = NSCache<NSString, CIImage>(); c.countLimit = 32; return c }()`를 추가합니다.
  - `.triangle`, `.diamond`, `.brush`처럼 CPU `CGContext` 래스터화를 수행하는 경로에서 `(extent.origin, width, height, mask)`를 직렬화한 캐시 키를 조회하여, 히트 시 `drawMask` 호출을 건너뛰고 캐시된 `CIImage`를 즉시 반환합니다.

```swift
    private nonisolated(unsafe) static let rasterMaskCache: NSCache<NSString, CIImage> = {
        let cache = NSCache<NSString, CIImage>()
        cache.countLimit = 32
        return cache
    }()

    private static func rasterCacheKey(for mask: Mask, in extent: CGRect) -> NSString {
        let width = max(Int(ceil(extent.width)), 1)
        let height = max(Int(ceil(extent.height)), 1)
        var base = "\(mask.shape.rawValue)|\(extent.minX),\(extent.minY)|\(width)x\(height)|" +
                   "\(mask.position.x),\(mask.position.y)|\(mask.size.width),\(mask.size.height)|\(mask.rotation)"
        if mask.shape == .brush {
            base.reserveCapacity(base.count + mask.brushPoints.count * 16)
            for pt in mask.brushPoints {
                base.append(";\(pt.x),\(pt.y)")
            }
        }
        return base as NSString
    }
```
  - `makeMaskImage(for:in:)`(라인 39~54)에서 `.triangle`, `.diamond`, `.brush` 케이스를 다음과 같이 캐시 경유로 감쌉니다:
```swift
        case .triangle:
            let key = rasterCacheKey(for: mask, in: extent)
            if let cached = rasterMaskCache.object(forKey: key) { return cached }
            let rendered = pathMask(points: trianglePoints(for: mask), in: extent)
            rasterMaskCache.setObject(rendered, forKey: key)
            return rendered
        case .diamond:
            let key = rasterCacheKey(for: mask, in: extent)
            if let cached = rasterMaskCache.object(forKey: key) { return cached }
            let rendered = pathMask(points: diamondPoints(for: mask), in: extent)
            rasterMaskCache.setObject(rendered, forKey: key)
            return rendered
        case .brush:
            let key = rasterCacheKey(for: mask, in: extent)
            if let cached = rasterMaskCache.object(forKey: key) { return cached }
            let rendered = brushMask(for: mask, in: extent)
            rasterMaskCache.setObject(rendered, forKey: key)
            return rendered
```

---

### 1.2 [`Sources/MovieCutCore/Rendering/VisualEffectPixelProcessor.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/VisualEffectPixelProcessor.swift)
* **위치**: 라인 134~136 (`cubeCache` 인근) 및 라인 289~311 (`gradientMapImage(stops:)`)
* **수정 내용**:
  - `private nonisolated(unsafe) static let gradientMapCache = NSCache<NSString, CIImage>()`를 추가합니다.
  - `gradientMapImage(stops:)` 시작 부분에서 `stops`의 `(position, red, green, blue)` 문자열 키로 `gradientMapCache`를 조회하고, 미스일 때만 256픽셀 루프 및 `CIImage(bitmapData:...)` 생성을 수행한 뒤 캐시에 저장합니다.

```swift
    private nonisolated(unsafe) static let gradientMapCache = NSCache<NSString, CIImage>()

    private static func gradientMapImage(stops: [GradientStop]) -> CIImage? {
        let key = stops.map { "\($0.position):\($0.red),\($0.green),\($0.blue)" }
            .joined(separator: "|") as NSString
        if let cached = gradientMapCache.object(forKey: key) {
            return cached
        }

        let width = 256
        let height = 1
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for index in 0..<width {
            let value = CGFloat(index) / CGFloat(width - 1)
            let color = interpolatedColor(at: value, stops: stops)
            let offset = index * 4
            pixels[offset] = UInt8(min(max(color.red * 255, 0), 255).rounded())
            pixels[offset + 1] = UInt8(min(max(color.green * 255, 0), 255).rounded())
            pixels[offset + 2] = UInt8(min(max(color.blue * 255, 0), 255).rounded())
            pixels[offset + 3] = UInt8.max
        }

        let created = CIImage(
            bitmapData: Data(pixels),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        )
        gradientMapCache.setObject(created, forKey: key)
        return created
    }
```

---

## Phase 2: 미디어 I/O — `ThumbnailGenerator` 정적 `CIContext` 공유

### 목표
- [`ThumbnailGenerator.generate(for:at:size:)`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Media/ThumbnailGenerator.swift#L11-L50)가 호출될 때마다 무거운 `CIContext(options: RenderColorConfiguration.contextOptions)`를 매번 생성·파괴하던 병목을 제거하고, 스레드 안전한 정적 `sharedContext`를 공유합니다.

### 2.1 [`Sources/MovieCutCore/Media/ThumbnailGenerator.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Media/ThumbnailGenerator.swift)
* **위치**: 라인 8~20
* **수정 내용**:
  - `#if canImport(AVFoundation)` 블록 내에 `private static let sharedContext = CIContext(options: RenderColorConfiguration.contextOptions)`를 선언하고, `generate(for:at:size:)` 내부의 `let context = CIContext(...)`를 `let context = Self.sharedContext`로 교체합니다.

```swift
public struct ThumbnailGenerator: Sendable {
    public static let defaultSize = CGSize(width: 160, height: 90)
    #if canImport(AVFoundation)
    private static let sharedContext = CIContext(options: RenderColorConfiguration.contextOptions)
    #endif

    public static func generate(for asset: MediaAsset, at time: TimeInterval, size: CGSize) -> Data? {
        #if canImport(AVFoundation)
        let context = Self.sharedContext
```

---

## Phase 3: 타임라인 데이터 모델 및 스냅 엔진 (Zero-Allocation Snapping & Flatten Fast-Path)

### 목표
1. **`SnapEngine`**: `snap(time:timeline:)` 호출 시마다 `flatMap`, `map`, `filter`로 3단계 임시 배열을 힙에 할당하던 것을 **Zero-Allocation 2중 루프**로 변경합니다.
2. **`TimelineView` 드래그 스냅 캐싱**: 120Hz 드래그 이벤트마다 `allClips(excluding:)` + `flatMap` + `sortedMarkers.map(\.time)` 배열을 반복 생성하던 것을, 드래그 시작(`beginClipDrag`) 시 정렬된 스냅 포인트 배열(`cachedDragSnapPoints`) **1회 생성** + 드래그 중 재사용으로 전환합니다.
3. **`FlattenedTimelineCache`**: 직전과 동일한 `Project` 값으로 `update(for:)`가 중복 호출될 때 불필요한 `CompoundFlattener.flatten` 재실행을 스킵합니다.

---

### 3.1 [`Sources/MovieCutCore/Models/SnapEngine.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Models/SnapEngine.swift)
* **위치**: 라인 17~29 (`snap(time:timeline:)`)
* **수정 내용**:
  - 배열 할당 없이 모든 트랙·클립의 `start`와 `end`를 직접 순회하며 `threshold` 이내의 최소 거리 후보만 추적하도록 수정합니다(동일 거리일 때는 더 작은 `point` 선택 계약 유지).

```swift
    /// Returns the nearest clip boundary within the snap threshold.
    public func snap(time: TimeInterval, timeline: Timeline) -> TimeInterval? {
        var bestPoint: TimeInterval?
        var bestDistance = TimeInterval.greatestFiniteMagnitude

        for track in timeline.tracks {
            for clip in track.clips {
                let candidates = (clip.timelineRange.start, clip.timelineRange.end)
                for point in [candidates.0, candidates.1] {
                    let distance = abs(point - time)
                    guard distance <= threshold else { continue }
                    if distance < bestDistance || (distance == bestDistance && point < (bestPoint ?? .greatestFiniteMagnitude)) {
                        bestDistance = distance
                        bestPoint = point
                    }
                }
            }
        }
        return bestPoint
    }
```

---

### 3.2 [`Sources/MovieCutCore/Rendering/FlattenedTimelineCache.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Rendering/FlattenedTimelineCache.swift)
* **위치**: 라인 20~50
* **수정 내용**:
  - `private var lastProject: Project?`를 추가하여 `update(for project: Project)` 호출 시 `if let snapshot, lastProject == project { return }`이면 재계산을 생략하고, `clear()`에서 `lastProject = nil`도 함께 초기화합니다.

---

### 3.3 [`App/MovieCutMac/TimelineView.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutMac/TimelineView.swift)
* **위치**: 라인 20~35 (`@State` 선언부), 라인 1683, 1737, 1776, 1804~1823 (`beginClipDrag`, `endClipDrag`), 라인 1912~1957 (`snappedTimeWithGuide`, `snappedTime`)
* **수정 내용**:
  1. `@State private var cachedDragSnapPoints: [TimeInterval] = []`를 추가합니다.
  2. `beginClipDrag(_ clip: Clip)`에서 `draggedClipId != clip.id`일 때 해당 클립을 제외한 모든 클립의 시작/끝점과 마커, 플레이헤드, `0.0`을 모아 `cachedDragSnapPoints`에 **단 1회**만 구성하고, `endClipDrag()`에서 `cachedDragSnapPoints.removeAll(keepingCapacity: true)`로 비웁니다.
  3. `snappedTimeWithGuide(_ rawTime: Double, allClips: [Clip]? = nil, threshold: Double = 5.0)`에서 `cachedDragSnapPoints`가 비어 있지 않으면 배열 재할당 없이 즉시 `cachedDragSnapPoints`를 순회하도록 수정하고, `moveGesture`, `leftTrimGesture`, `rightTrimGesture`에서 `allClips(excluding: clip.id)` 호출 없이 캐시를 사용하도록 변경합니다.

```swift
    private func beginClipDrag(_ clip: Clip) {
        if draggedClipId != clip.id {
            dragInitialTimelineRange = clip.timelineRange
            dragInitialSourceRange = clip.sourceRange
            var points: [TimeInterval] = [viewModel.playheadTime, 0.0]
            for track in viewModel.currentProject.timeline.tracks {
                for other in track.clips where other.id != clip.id {
                    points.append(other.timelineRange.start)
                    points.append(other.timelineRange.start + other.timelineRange.duration)
                }
            }
            for marker in sortedMarkers {
                points.append(marker.time)
            }
            cachedDragSnapPoints = points
        }
        isDragging = true
        draggedClipId = clip.id
        viewModel.selectedClipId = clip.id
    }
```

---

## Phase 4: 오디오 DSP — `AudioGraphLimiter` $O(N)$ 슬라이딩 윈도우 및 `AudioGraphCompressor` 초월함수 최적화

### 목표
1. **`AudioGraphLimiter.apply`**: 매 샘플마다 `lookAheadFrames`(최대 2,400프레임)를 다시 스캔하던 $O(N \times W)$ 중첩 루프를 **프레임별 피크 사전 계산 + 만료 시에만 재스캔하는 $O(N)$ 슬라이딩 윈도우 알고리즘**으로 교체하여, 결과는 **비트 단위까지 100% 동일**하면서 연산 속도를 수백 배 가속합니다.
2. **`AudioGraphCompressor.apply`**: 루프 밖에서 `thresholdLinear = pow(10.0, parameters.thresholdDb / 20.0)`를 미리 계산하여 Threshold 이하 샘플에서 `log10` 호출을 스킵하고, `envelopeDb == 0`일 때 `pow(10.0, ...)` 호출을 스킵합니다.

---

### 4.1 [`Sources/MovieCutCore/Audio/AudioGraphLimiter.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Audio/AudioGraphLimiter.swift)
* **위치**: 라인 48~80 (`AudioGraphLimiter.apply`)
* **수정 내용**:

```swift
        var interleaved = audio.interleaved
        var smoothedGain: Double = 1.0
        let frameCount = audio.frameCount

        // 1. 프레임별 채널 최대 피크를 O(N)으로 1회 사전 계산
        var framePeaks = [Double](repeating: 0, count: frameCount)
        for f in 0..<frameCount {
            var peak: Double = 0
            let base = f * channelCount
            for ch in 0..<channelCount {
                let magnitude = abs(Double(interleaved[base + ch]))
                if magnitude > peak { peak = magnitude }
            }
            framePeaks[f] = peak
        }

        // 2. O(N) 슬라이딩 윈도우 [frame ... scanEnd] 최대값 추적
        var maxPeak: Double = -1
        var maxPeakIndex: Int = -1

        for frame in 0..<frameCount {
            let scanEnd = min(frame + lookAheadFrames, frameCount - 1)
            if maxPeakIndex >= frame {
                let incoming = framePeaks[scanEnd]
                if incoming >= maxPeak {
                    maxPeak = incoming
                    maxPeakIndex = scanEnd
                }
            } else {
                maxPeak = 0
                maxPeakIndex = frame
                var s = frame
                while s <= scanEnd {
                    let candidate = framePeaks[s]
                    if candidate >= maxPeak {
                        maxPeak = candidate
                        maxPeakIndex = s
                    }
                    s += 1
                }
            }
            let windowPeak = maxPeak

            // The target gain: never above 1, bring the peak to the ceiling.
            let targetGain = min(1.0, windowPeak > 0 ? ceilingLinear / windowPeak : 1.0)

            // Instant attack (look-ahead already pre-rolled); smooth release.
            if targetGain < smoothedGain {
                smoothedGain = targetGain
            } else {
                smoothedGain = releaseCoeff * smoothedGain + (1 - releaseCoeff) * targetGain
            }

            // Apply.
            let base = frame * channelCount
            for channel in 0..<channelCount {
                let index = base + channel
                interleaved[index] = Float(Double(interleaved[index]) * smoothedGain)
            }
        }
```

---

### 4.2 [`Sources/MovieCutCore/Audio/AudioGraphCompressor.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/Sources/MovieCutCore/Audio/AudioGraphCompressor.swift)
* **위치**: 라인 56~97 (`AudioGraphCompressor.apply`)
* **수정 내용**:
  - 루프 밖에서 `let thresholdLinear = pow(10.0, parameters.thresholdDb / 20.0)`를 계산합니다.
  - `peak > thresholdLinear`일 때만 `let peakDb = 20 * log10(peak)`를 계산하고, 그렇지 않으면 `gainReductionDb = 0`으로 즉시 처리합니다(Threshold 이하에서는 `peakDb <= parameters.thresholdDb`가 수학적으로 자명하므로 `log10` 불필요).
  - `envelopeDb == 0`이면 `pow(10.0, envelopeDb / 20.0)` 대신 `1.0`을 사용합니다.

```swift
        let sampleRate = audio.sampleRate
        let channelCount = audio.channels
        let attackCoeff = exp(-1.0 / (parameters.attackSeconds * sampleRate))
        let releaseCoeff = exp(-1.0 / (parameters.releaseSeconds * sampleRate))
        let makeupLinear = pow(10.0, parameters.makeupGainDb / 20.0)
        let thresholdLinear = pow(10.0, parameters.thresholdDb / 20.0)

        var interleaved = audio.interleaved
        var envelopeDb: Double = 0  // the smoothed gain-reduction level

        for frame in 0..<audio.frameCount {
            let base = frame * channelCount
            var peak: Double = 0
            for channel in 0..<channelCount {
                let sample = abs(Double(interleaved[base + channel]))
                if sample > peak { peak = sample }
            }

            var gainReductionDb: Double = 0
            if peak > thresholdLinear {
                let peakDb = 20 * log10(peak)
                if peakDb > parameters.thresholdDb {
                    let excessDb = peakDb - parameters.thresholdDb
                    let compressedDb = excessDb / parameters.ratio
                    gainReductionDb = -(excessDb - compressedDb)
                }
            }

            if gainReductionDb < envelopeDb {
                envelopeDb = attackCoeff * envelopeDb + (1 - attackCoeff) * gainReductionDb
            } else {
                envelopeDb = releaseCoeff * envelopeDb + (1 - releaseCoeff) * gainReductionDb
            }

            let envLinear = envelopeDb == 0 ? 1.0 : pow(10.0, envelopeDb / 20.0)
            let linearGain = envLinear * makeupLinear
            for channel in 0..<channelCount {
                let index = base + channel
                interleaved[index] = Float(Double(interleaved[index]) * linearGain)
            }
        }
```

---

## Phase 5: UI/UX — 웨이브폼 Canvas 단일 `Path` 배치 드로잉 및 썸네일 `NSImage` 캐싱

### 목표
1. **`TimelineView.waveformCanvas(for:selected:)`**: 200개 막대에 대해 `context.fill(Path(rect), ...)`를 200번 개별 호출하던 것을 단일 `batchPath`에 `addRect`로 모은 뒤 **`context.fill(batchPath, ...)` 단 1회 호출**로 병합합니다.
2. **`TimelineView.thumbnailImage(for:)`**: 뷰가 리렌더링될 때마다 `NSImage(data: thumbnailData)`로 PNG 데이터를 반복 디코딩하던 것을 정적 `NSCache<NSString, NSImage>`로 캐싱합니다.

---

### 5.1 [`App/MovieCutMac/TimelineView.swift`](file:///Users/cool-mini4/MyDev/automation/movie_cut/App/MovieCutMac/TimelineView.swift)
* **위치**: 라인 1527~1600 (`thumbnailImage(for:)`, `waveformCanvas(for:selected:)`)
* **수정 내용**:
  1. `TimelineView` 내부에 `private nonisolated(unsafe) static let decodedThumbnailCache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 128; return c }()`를 추가하고, `thumbnailImage(for:)`에서 `"\(clip.assetId?.uuidString ?? clip.id.uuidString):\(thumbnailData.count)" as NSString` 키로 캐시된 `NSImage`를 반환합니다.
  2. `waveformCanvas(for:selected:)`의 `Canvas` 클로저 내부 루프에서 `var batchPath = Path()`에 `batchPath.addRect(rect)`만 수행한 뒤 루프 종료 후 `context.fill(batchPath, with: .color(.white.opacity(selected ? 0.36 : 0.24)))`를 **단 1회** 호출합니다.

```swift
    private nonisolated(unsafe) static let decodedThumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()

    private func thumbnailImage(for clip: Clip) -> NSImage? {
        guard
            clip.kind == .video || clip.kind == .image,
            let thumbnailData = viewModel.thumbnailData(for: clip)
        else {
            return nil
        }
        let key = "\((clip.assetId ?? clip.id).uuidString):\(thumbnailData.count)" as NSString
        if let cached = Self.decodedThumbnailCache.object(forKey: key) {
            return cached
        }
        guard let decoded = NSImage(data: thumbnailData) else {
            return nil
        }
        Self.decodedThumbnailCache.setObject(decoded, forKey: key)
        return decoded
    }
```

---

## 최소 검증 프로토콜 (Lightweight Verification Protocol)

각 Phase 구현 후 아래의 가벼운 명령어만 실행하여 검증하십시오(전체 테스트나 UI 테스트 실행 금지).

1. **Phase 1 완료 후**:
   ```bash
   swift test --filter "MaskPixelProcessorTests|VisualEffectPixelProcessorTests"
   ```
2. **Phase 2 & 3 완료 후**:
   ```bash
   swift test --filter "ThumbnailProxyStaticContractTests|CoreFeatureTests"
   ```
3. **Phase 4 완료 후**:
   ```bash
   swift test --filter "AudioGraphCompressorTests|AudioGraphLimiterReverbTests|AudioGraphMasterChainTests"
   ```
4. **Phase 5 완료 후 (최종 빌드 검증)**:
   ```bash
   swift build
   ```
