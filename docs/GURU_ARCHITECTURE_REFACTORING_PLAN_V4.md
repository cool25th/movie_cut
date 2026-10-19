# MovieCut — Guru Architecture Refactoring Plan (Round 4 / V4)

> **목적**: 본 문서는 Round 1(`GURU_ARCHITECTURE_REFACTORING_PLAN.md`), Round 2(`GURU_ARCHITECTURE_REFACTORING_PLAN_V2.md`), Round 3(`GURU_ARCHITECTURE_REFACTORING_PLAN_V3.md`) 완료 이후 남은 **심층 프레임/샘플/타임라인 핫패스(Keyframe 6× 필터·정렬, `.cube` 3D LUT 파서의 55만 회 `String` 힙 할당, `SpeedRampCurve` 매 호출 적분 재계산, `BeatDetectionProvider` / `SilenceDetectionProvider` PCM 디코드 복사 병목, `CenterChannelVocalSeparator` 블록당 4× 배열 할당, `ScopeViews` / `HistogramView` / `IOSTimelineView` UI 핫패스)**를 제거하기 위한 **독립 실행형(Self-Contained) 상세 작업 명세서**입니다.

---

## ⚠️ 절대 준수 규칙 (Testing & Execution Constraints)

1. **전체 테스트 실행 절대 금지**:
   - `swift test` (필터 없는 전체 실행) **절대 금지**
   - `MovieCutUITests` 및 `--e2e-*` 플래그 실행 **절대 금지**
   - 무거운 통합/퍼포먼스 스위트(`CommandTortureTests`, `MotionTrackingAnalysisPerfTests`, `SceneChangeDetectionMeasurementTests`, `TranscriptSearchMeasurementTests`, `AIPhotoMontageE2ETests`) 실행 **절대 금지**
2. **단계별 최소 타겟 검증만 수행**:
   - 각 Phase 완료 시 본 문서에 명시된 **단일 `--filter` 명령어(1~3초 내외 소요)**만 실행하거나 `swift build`로 컴파일 확인만 수행합니다.
3. **기존 공개 API 시그니처 및 부동소수점 수치 결정론 100% 보존**:
   - 외부에서 호출하는 public 메서드/프로퍼티 시그니처와 에러 타입, 출력 수치 계약을 절대 깨뜨리지 마십시오.

---

## Phase 1: 렌더링 파이프라인 — `CustomCompositionClipEffect` 키프레임 사전 그룹화·정렬 + `.cube` LUT 무할당 파싱 + `AutoColorAnalyzer` 단일 패스 통합

### 1-A. `CustomCompositionClipEffect` 키프레임 사전 그룹화·정렬 및 $O(\log K)$ 이진 탐색
- **파일**: `Sources/MovieCutCore/Rendering/CustomCompositionClipEffect.swift`
- **문제점**:
  - `animationState(at:)`(L118-129) 호출 시 매 비디오 프레임(60fps)마다 `Self.hasVisualAnimation`(`keyframes.contains`), `Self.keyframedTransform`(`keyframes.contains` + `.positionX`, `.positionY`, `.scaleX`, `.scaleY`, `.rotation` 5회 `keyframedValue` 호출), `.opacity` 1회 `keyframedValue` 호출이 발생합니다.
  - `keyframedValue(for:defaultValue:keyframes:at:)`(L201-245)는 매 호출마다 `keyframes.filter { $0.property == property }.sorted { $0.time < $1.time }`를 수행하여 **프레임당 클립 1개 기준 12개의 힙 배열 할당(6× filter + 6× sorted)과 6번의 $O(K \log K)$ 정렬**을 반복합니다.
- **수정 지침**:
  1. `CustomCompositionClipEffect` 구조체에 사전 계산된 private 저장 프로퍼티 3개를 추가합니다:
     ```swift
     private let hasVisualAnimationFlag: Bool
     private let hasTransformKeyframesFlag: Bool
     private let sortedKeyframesByProperty: [AnimatableProperty: [Keyframe]]
     ```
  2. `init?`(L41-108) 내부에서 `let clampedOpacity = min(max(opacity, 0), 1)` 직후에 `let hasVisual = Self.hasVisualAnimation(transform: transform, opacity: clampedOpacity, keyframes: keyframes)`를 1회 계산하여 `guard` 조건(L80)과 `self.hasVisualAnimationFlag = hasVisual`에 재사용합니다.
  3. `init?` 말미에서 `keyframes`를 속성별로 1회만 그룹화 및 시간순 정렬하여 저장합니다:
     ```swift
     var grouped: [AnimatableProperty: [Keyframe]] = [:]
     var hasTransform = false
     if !keyframes.isEmpty {
         for keyframe in keyframes {
             grouped[keyframe.property, default: []].append(keyframe)
             if Self.transformKeyframeProperties.contains(keyframe.property) {
                 hasTransform = true
             }
         }
         for property in grouped.keys {
             grouped[property]?.sort { $0.time < $1.time }
         }
     }
     self.hasVisualAnimationFlag = hasVisual
     self.hasTransformKeyframesFlag = hasTransform
     self.sortedKeyframesByProperty = grouped
     ```
  4. `animationState(at:)`(L118-129), `keyframedTransform`(L158-199), `keyframedValue`(L201-245)가 `sortedKeyframesByProperty`와 플래그를 사용해 **런타임 힙 할당 0회**로 동작하도록 교체합니다:
     ```swift
     public func animationState(at time: CMTime) -> CustomCompositionAnimationState? {
         guard hasVisualAnimationFlag else {
             return nil
         }

         let rawLocalTime = CMTimeSubtract(time, timeRange.start).seconds
         let localTime = rawLocalTime.isFinite ? max(0, rawLocalTime) : 0
         return CustomCompositionAnimationState(
             transform: Self.keyframedTransform(
                 base: transform,
                 hasTransformKeyframes: hasTransformKeyframesFlag,
                 sortedByProperty: sortedKeyframesByProperty,
                 at: localTime
             ),
             opacity: Self.keyframedValue(
                 for: .opacity,
                 defaultValue: opacity,
                 sortedByProperty: sortedKeyframesByProperty,
                 at: localTime
             )
         )
     }

     private static func keyframedTransform(
         base transform: ClipTransform,
         hasTransformKeyframes: Bool,
         sortedByProperty: [AnimatableProperty: [Keyframe]],
         at localTime: TimeInterval
     ) -> ClipTransform {
         guard hasTransformKeyframes else {
             return transform
         }

         var resolvedTransform = transform
         resolvedTransform.position.x = CGFloat(keyframedValue(
             for: .positionX,
             defaultValue: Double(transform.position.x),
             sortedByProperty: sortedByProperty,
             at: localTime
         ))
         resolvedTransform.position.y = CGFloat(keyframedValue(
             for: .positionY,
             defaultValue: Double(transform.position.y),
             sortedByProperty: sortedByProperty,
             at: localTime
         ))
         resolvedTransform.scale.width = CGFloat(keyframedValue(
             for: .scaleX,
             defaultValue: Double(transform.scale.width),
             sortedByProperty: sortedByProperty,
             at: localTime
         ))
         resolvedTransform.scale.height = CGFloat(keyframedValue(
             for: .scaleY,
             defaultValue: Double(transform.scale.height),
             sortedByProperty: sortedByProperty,
             at: localTime
         ))
         resolvedTransform.rotation = keyframedValue(
             for: .rotation,
             defaultValue: transform.rotation,
             sortedByProperty: sortedByProperty,
             at: localTime
         )
         return resolvedTransform
     }

     private static func keyframedValue(
         for property: AnimatableProperty,
         defaultValue: Double,
         sortedByProperty: [AnimatableProperty: [Keyframe]],
         at localTime: TimeInterval
     ) -> Double {
         guard let propertyKeyframes = sortedByProperty[property],
               let firstKeyframe = propertyKeyframes.first else {
             return defaultValue
         }

         guard localTime >= firstKeyframe.time else {
             return defaultValue
         }

         guard let lastKeyframe = propertyKeyframes.last, localTime < lastKeyframe.time else {
             return propertyKeyframes.last?.value ?? defaultValue
         }

         // Binary search for the first segment whose endKeyframe.time >= localTime
         var low = 0
         var high = propertyKeyframes.count - 2
         while low < high {
             let mid = (low + high) / 2
             if propertyKeyframes[mid + 1].time < localTime {
                 low = mid + 1
             } else {
                 high = mid
             }
         }

         for index in low..<(propertyKeyframes.count - 1) {
             let startKeyframe = propertyKeyframes[index]
             let endKeyframe = propertyKeyframes[index + 1]
             guard localTime >= startKeyframe.time && localTime <= endKeyframe.time else {
                 continue
             }

             let duration = endKeyframe.time - startKeyframe.time
             guard duration > 0 else {
                 return endKeyframe.value
             }

             return Keyframe.interpolate(
                 from: startKeyframe.value,
                 to: endKeyframe.value,
                 progress: (localTime - startKeyframe.time) / duration,
                 mode: startKeyframe.interpolation,
                 customCurve: startKeyframe.customCurve
             )
         }

         return firstKeyframe.value
     }
     ```

### 1-B. `CubeLUTParser` Substring 무할당 파싱 및 `data: [Float]` 직접 적재 + `CubeLUTExporter` 정적 `CIContext`
- **파일**: `Sources/MovieCutCore/Rendering/CubeLUTParser.swift`, `Sources/MovieCutCore/Rendering/CubeLUTExporter.swift`
- **문제점**:
  1. `CubeLUTParser.parse(_:)`(L37-92)는 $65^3$ LUT($274,625$개 데이터 라인) 파싱 시 매 라인마다 `rawLine.trimmingCharacters(in: .whitespaces)`(힙 `String` 할당 #1)와 `line.uppercased()`(힙 `String` 할당 #2)를 호출하여 **549,250회 이상의 불필요한 `String` 힙 할당**을 일으키고, 중간 `entries: [(Float, Float, Float)]` 배열(3.3MB)을 만든 뒤 다시 `data: [Float]`(4.4MB)로 복사합니다.
  2. `CubeLUTExporter.bake(dimension:colorCorrection:)`(L115)는 호출마다 `CIContext(options: [.useSoftwareRenderer: true])`를 새로 생성·파괴합니다.
- **수정 지침**:
  1. `CubeLUTParser.swift`의 `parse(_ text: String)`를 `Substring` 기반 무할당 트리밍, 첫 글자가 알파벳일 때만 키워드 대문자 비교, 그리고 `var data: [Float]` 직접 적재 방식으로 교체합니다:
     ```swift
     public static func parse(_ text: String) throws -> CubeLUT {
         var dimension: Int?
         var data: [Float] = []
         var entryCount = 0

         for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
             let line = trimHorizontalWhitespace(rawLine)
             guard let first = line.first, first != "#" else { continue }

             if first.isLetter {
                 let upper = line.uppercased()
                 if upper.hasPrefix("LUT_1D_SIZE") {
                     throw ParseError.unsupported1D
                 }
                 if upper.hasPrefix("LUT_3D_SIZE") {
                     let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Int($0) }
                     guard let size = parts.last else { throw ParseError.missingSize }
                     guard size >= 2, size <= maximumDimension else { throw ParseError.sizeOutOfRange(size) }
                     dimension = size
                     data.reserveCapacity(size * size * size * 4)
                     continue
                 }
                 if upper.hasPrefix("TITLE") || upper.hasPrefix("DOMAIN_") || upper.hasPrefix("LUT_3D_INPUT_RANGE") {
                     continue
                 }
             }

             // Data line: three floats.
             var iterator = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).makeIterator()
             guard let c0 = iterator.next(),
                   let c1 = iterator.next(),
                   let c2 = iterator.next(),
                   let r = Float(c0),
                   let g = Float(c1),
                   let b = Float(c2) else {
                 if entryCount == 0 { continue }
                 throw ParseError.malformedEntry(String(line))
             }
             data.append(r.clamped(to: 0...1))
             data.append(g.clamped(to: 0...1))
             data.append(b.clamped(to: 0...1))
             data.append(1.0)
             entryCount += 1
         }

         guard let dimension else { throw ParseError.missingSize }
         let expected = dimension * dimension * dimension
         guard entryCount == expected else {
             throw ParseError.entryCountMismatch(expected: expected, found: entryCount)
         }

         return CubeLUT(dimension: dimension, data: data)
     }

     private static func trimHorizontalWhitespace(_ slice: Substring) -> Substring {
         var start = slice.startIndex
         var end = slice.endIndex
         while start < end && (slice[start] == " " || slice[start] == "\t") {
             slice.formIndex(after: &start)
         }
         while end > start {
             let prev = slice.index(before: end)
             if slice[prev] == " " || slice[prev] == "\t" {
                 end = prev
             } else {
                 break
             }
         }
         return slice[start..<end]
     }
     ```
  2. `CubeLUTExporter.swift` 내부에 정적 컨텍스트 `private nonisolated(unsafe) static let bakeContext = CIContext(options: [.useSoftwareRenderer: true])`를 선언하고 `bake(dimension:colorCorrection:)`(L115)에서 `bakeContext.render(...)`를 재사용하도록 변경합니다.

### 1-C. `AutoColorAnalyzer.autoEnhanceGrade` 단일 패스(Single-Pass) 통계 통합
- **파일**: `Sources/MovieCutCore/Analysis/AutoColorAnalyzer.swift`
- **문제점**:
  - `autoEnhanceGrade(rgba:)`(L93-107)가 `autoWhiteBalanceGrade(rgba:)`와 `autoLevelsGrade(rgba:)`를 순차 호출하여 동일 `rgba` 바이트 버퍼를 2회 풀 스캔합니다.
- **수정 지침**:
  - `autoWhiteBalanceGrade(rgba:)`와 `autoLevelsGrade(rgba:lowPercentile:highPercentile:)`의 기존 시그니처와 구현은 그대로 유지하되, `autoEnhanceGrade(rgba:)` 내부에서 단일 루프로 `sumRed/sumGreen/sumBlue` 합산과 256-bin `histogram` 집계를 동시에 수행하여 메모리 대역폭을 50% 절감합니다 (계산 수식은 기존 `autoWhiteBalanceGrade` + `autoLevelsGrade` 결합 결과와 100% 비트 동일하게 유지).

### ✅ Phase 1 타겟 검증 명령어
```bash
swift test --filter "CubeLUT|AutoColorAnalyzer|KeyframeBezier|RenderingTests"
```

---

## Phase 2: 미디어 I/O & 분석 디코드 — `BeatDetectionProvider` 및 `SilenceDetectionProvider` Zero-Copy `CMBlockBuffer` 스캔

### 2-A. `BeatDetectionProvider.readMonoSamples` Zero-Copy 포인터 접근 + 단일 스크래치 버퍼 재사용
- **파일**: `Sources/MovieCutCore/Analysis/BeatDetectionProvider.swift`
- **문제점**:
  - `readMonoSamples(at:)`(L154-203)의 `while let buffer = trackOutput.copyNextSampleBuffer()` 루프가 매 오디오 버퍼마다 `var bytes = [UInt8](repeating: 0, count: length)`를 힙에 새로 할당하고 무조건 `CMBlockBufferCopyDataBytes`를 수행합니다. 또한 `detectBeats(monoSamples:sampleRate:)`(L58-75)에서 `energies`와 `flux` 배열에 `reserveCapacity`가 누락되어 있습니다.
- **수정 지침**:
  1. `detectBeats(monoSamples:sampleRate:)`(L58-75)에서 예상 프레임 수 `(monoSamples.count - frameSize) / hopSize + 1`만큼 `energies.reserveCapacity(frameCount)`와 `flux.reserveCapacity(frameCount)`를 추가합니다.
  2. `readMonoSamples(at:)`(L175-199)에서 `WaveformGenerator.decodeWaveform`과 동일한 Zero-Copy `CMBlockBufferGetDataPointer` 패턴과 단일 재사용 `scratchBytes: [UInt8]` 폴백을 적용합니다:
     ```swift
     var samples: [Float] = []
     let durationSeconds = CMTimeGetSeconds(track.timeRange.duration)
     if durationSeconds.isFinite && durationSeconds > 0 {
         samples.reserveCapacity(Int(durationSeconds * Self.analysisSampleRate))
     }
     var scratchBytes: [UInt8] = []
     let invMax = 1.0 / Float(Int16.max)

     func absorb(_ rawBytes: UnsafeRawBufferPointer) {
         var index = 0
         while index + 1 < rawBytes.count {
             let value = Int16(littleEndian: Int16(bitPattern: UInt16(rawBytes[index]) | (UInt16(rawBytes[index + 1]) << 8)))
             samples.append(Float(value) * invMax)
             index += 2
         }
     }

     while let buffer = trackOutput.copyNextSampleBuffer() {
         guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
         let length = CMBlockBufferGetDataLength(blockBuffer)
         guard length >= 2 else { continue }

         var dataPointer: UnsafeMutablePointer<Int8>?
         var dataLength = 0
         var totalLength = 0
         if CMBlockBufferGetDataPointer(
             blockBuffer,
             atOffset: 0,
             lengthAtOffsetOut: &dataLength,
             totalLengthOut: &totalLength,
             dataPointerOut: &dataPointer
         ) == noErr,
            let dataPointer,
            dataLength >= length {
             absorb(UnsafeRawBufferPointer(start: dataPointer, count: length))
         } else {
             if scratchBytes.count < length {
                 scratchBytes = [UInt8](repeating: 0, count: length)
             }
             guard CMBlockBufferCopyDataBytes(
                 blockBuffer,
                 atOffset: 0,
                 dataLength: length,
                 destination: &scratchBytes
             ) == noErr else {
                 continue
             }
             scratchBytes.withUnsafeBytes { raw in
                 absorb(UnsafeRawBufferPointer(rebasing: raw.prefix(length)))
             }
         }
     }
     ```

### 2-B. `SilenceDetectionProvider.decodeSilentRanges` 불필요한 `repeatElement(0)` 확장 및 `removeFirst` 복사 완화
- **파일**: `Sources/MovieCutCore/Analysis/SilenceDetectionProvider.swift`
- **문제점**:
  - `decodeSilentRanges(at:configuration:)`(L180-218)에서 매 `CMSampleBuffer`마다 `pendingBytes.append(contentsOf: repeatElement(0, count: length))`로 전체 바이트를 `pendingBytes`에 복사한 뒤 `pendingBytes.removeFirst(offset)`으로 앞부분을 잘라내어 불필요한 메모리 초기화를 반복합니다.
- **수정 지침**:
  - `CMBlockBufferGetDataPointer`로 연속 버퍼 포인터를 얻을 수 있을 때:
    - `pendingBytes`에 이전 버퍼의 잔여 바이트(`< bytesPerChunk`)가 있다면 `bytesPerChunk - pendingBytes.count`만큼만 채워 1개 청크를 먼저 처리하고 `pendingBytes.removeAll(keepingCapacity: true)`를 호출합니다.
    - 이후 남은 샘플 버퍼 구간은 `UnsafeRawBufferPointer` 슬라이스에서 복사 없이 `bytesPerChunk` 단위로 직접 `computeRMS`를 호출하고, 마지막에 남는 잔여 바이트(`< bytesPerChunk`)만 `pendingBytes`에 저장합니다.
  - 이를 위해 `computeRMS`가 `UnsafeRawBufferPointer`와 `ArraySlice<UInt8>` 모두에서 동일한 수식(`Int16(data[i]) | (Int16(data[i + 1]) << 8)`)으로 동작하도록 오버로드하거나 `withUnsafeBytes`로 위임합니다.

### ✅ Phase 2 타겟 검증 명령어
```bash
swift test --filter "BeatDetectionTests|SilenceDetectionProviderTests|SpeechDuckingServiceTests"
```

---

## Phase 3: 타임라인 & 데이터 모델 — `SpeedRampCurve` 적분 테이블 사전 계산 + `TranscriptSearchIndex` 이진 탐색

### 3-A. `SpeedRampCurve` 세그먼트 적분 테이블 사전 계산 및 $O(\log S)$ 탐색
- **파일**: `Sources/MovieCutCore/Models/SpeedRampCurve.swift`
- **문제점**:
  - `timeMapping(sourceTime:)`(L27-65)와 `inverseMapping(outputTime:)`(L68-108)는 호출될 때마다 `points` 배열을 처음부터 순회하며 매 세그먼트의 `integralOfReciprocalRate`(`log(rateAtEndTime / startRate) / slope`)를 처음부터 다시 계산합니다.
  - `SpeedRampCurve`는 불변(`let points: [SpeedRampPoint]`) 값 타입이므로 세그먼트별 경계 및 누적 출력 시간을 `init(points:)`에서 단 1회만 계산해 두면 이후 모든 `timeMapping` / `inverseMapping` 호출에서 루프 및 초월함수(`log`) 반복 호출을 제거할 수 있습니다.
- **수정 지침**:
  1. `SpeedRampCurve` 내부에 private 세그먼트 구조체와 사전 계산 배열을 추가합니다:
     ```swift
     private struct PrecomputedSegment: Sendable {
         let sourceStart: TimeInterval
         let sourceEnd: TimeInterval
         let startRate: Double
         let endRate: Double
         let outputStart: TimeInterval
         let outputDuration: TimeInterval
     }

     private let segments: [PrecomputedSegment]
     private let initialRate: Double
     private let trailingSourceStart: TimeInterval
     private let trailingOutputStart: TimeInterval
     private let trailingRate: Double
     ```
  2. `init(points:)`에서 정규화된 `self.points`를 만든 직후 `segments`, `initialRate`, `trailingSourceStart`, `trailingOutputStart`, `trailingRate`를 1회 계산합니다 (기존 `timeMapping` / `inverseMapping`의 `segmentStart`, `startRate`, `integralOfReciprocalRate` 수식과 100% 동일하게 구성).
  3. `timeMapping(sourceTime:)`와 `inverseMapping(outputTime:)`는 `segments` 배열에 대해 이진 탐색(또는 세그먼트 탐색)으로 해당 구간 1개만 찾아 그 구간 내부의 부분 적분(`integralOfReciprocalRate` 또는 `sourceOffset`)만 1회 계산하도록 교체합니다.
  4. **주의**: `Tests/MovieCutCoreTests/Phase33SpeedCurveEditorStaticContractTests.swift`가 `SpeedRampCurve.swift`에 UI 마커 문자열(`speedCurveEditor` 등)이 없는지 검사하므로, 주석이나 식별자에 해당 UI 문자열을 절대 포함하지 마십시오.

### 3-B. `TranscriptSearchIndex.Corpus.resolve` $O(\log W)$ 이진 탐색
- **파일**: `Sources/MovieCutCore/Transcription/TranscriptSearchIndex.swift`
- **문제점**:
  - `Corpus.init(items:)`(L70-99)가 생성하는 `cardSpans`와 `wordSpans`는 시작 오프셋(`start`) 기준 순증가·비중첩 구간 배열임에도, `resolve(_:cardSpans:wordSpans:)`(L171-187)는 매 매치마다 `wordSpans`와 `cardSpans`를 처음부터 끝까지 선형 스캔합니다.
- **수정 지침**:
  - `resolve(_:cardSpans:wordSpans:)`(L171-187)에서 `wordSpans`와 `cardSpans`를 각각 $O(\log N)$ 이진 탐색으로 조회하도록 교체합니다:
    ```swift
    private static func resolve(
        _ offset: Int,
        cardSpans: [(start: Int, end: Int, item: Item)],
        wordSpans: [(start: Int, end: Int, card: Int, word: WordTiming)]
    ) -> (item: Item, time: TimeInterval) {
        var wLow = 0
        var wHigh = wordSpans.count - 1
        while wLow <= wHigh {
            let mid = (wLow + wHigh) / 2
            let span = wordSpans[mid]
            if offset < span.start {
                wHigh = mid - 1
            } else if offset >= span.end {
                wLow = mid + 1
            } else {
                let item = cardSpans[span.card].item
                return (item, item.timelineStart + max(0, span.word.startTime))
            }
        }

        var cLow = 0
        var cHigh = cardSpans.count - 1
        var lastPrecedingIndex: Int?
        while cLow <= cHigh {
            let mid = (cLow + cHigh) / 2
            let span = cardSpans[mid]
            if offset < span.start {
                cHigh = mid - 1
            } else {
                lastPrecedingIndex = mid
                if offset < span.end {
                    return (span.item, span.item.timelineStart)
                }
                cLow = mid + 1
            }
        }

        let item = lastPrecedingIndex.map { cardSpans[$0].item } ?? Item(clipId: UUID(), text: "", timelineStart: 0)
        return (item, item.timelineStart)
    }
    ```

### ✅ Phase 3 타겟 검증 명령어
```bash
swift test --filter "ClipTimeMappingTests|SplitClipCommandSpeedTests|Phase33SpeedCurveEditorStaticContractTests|TranscriptSearchIndexTests"
```

---

## Phase 4: 오디오 엔진 — `CenterChannelVocalSeparator` In-Place PCM 버퍼 처리 & `AudioGraphReverb` 패스 최적화

### 4-A. `CenterChannelVocalSeparator.process(buffer:mode:)` 무할당 In-Place 처리
- **파일**: `Sources/MovieCutCore/Audio/VocalSeparationService.swift`
- **문제점**:
  - `VocalSeparationRenderer.render`(4,096프레임 블록 루프)에서 호출하는 `CenterChannelVocalSeparator.process(buffer:mode:)`(L91-112)는 `leftPointer`와 `rightPointer`를 `Array(UnsafeBufferPointer(...))`로 복사(힙 배열 2개 할당)한 뒤, `process(_ frames: StereoFrames, mode:)`를 호출해 또다시 `outLeft`, `outRight`(힙 배열 2개 할당)를 만들고 다시 포인터로 복사합니다. 블록당 총 4개의 `[Float]` 배열 할당·해제가 반복됩니다.
- **수정 지침**:
  - `process(buffer:mode:)`(L91-112)가 중간 `Array` 및 `StereoFrames` 생성 없이 `leftPointer`와 `rightPointer`를 직접 In-Place로 연산하도록 수정합니다(기존 `process(_ frames: StereoFrames, mode:)` 메서드는 그대로 유지):
    ```swift
    func process(buffer: AVAudioPCMBuffer, mode: VocalSeparationMode) -> AVAudioPCMBuffer? {
        guard let channels = buffer.floatChannelData,
              buffer.format.channelCount >= 2,
              buffer.format.commonFormat == .pcmFormatFloat32 else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return buffer }

        let leftPointer = channels[0]
        let rightPointer = channels[1]
        let wet = wetMix
        let dry = 1 - wet

        switch mode {
        case .removeVocals:
            for index in 0..<frameLength {
                let left = leftPointer[index]
                let right = rightPointer[index]
                let mid = (left + right) * 0.5
                leftPointer[index] = left - wet * mid
                rightPointer[index] = right - wet * mid
            }
        case .isolateCenter:
            for index in 0..<frameLength {
                let left = leftPointer[index]
                let right = rightPointer[index]
                let mid = (left + right) * 0.5
                leftPointer[index] = dry * left + wet * mid
                rightPointer[index] = dry * right + wet * mid
            }
        }
        return buffer
    }
    ```

### 4-B. `AudioGraphReverb` 정적 탭 비율 상수화
- **파일**: `Sources/MovieCutCore/Audio/AudioGraphReverb.swift`
- **문제점**:
  - `apply(_:parameters:)`(L41-42) 호출마다 `[1.0, 1.3, 1.7, 2.3, 3.1, 4.7]` 리터럴 배열을 힙에 생성합니다.
- **수정 지침**:
  - `private static let reflectionTapRatios: [Double] = [1.0, 1.3, 1.7, 2.3, 3.1, 4.7]`를 정적 상수로 분리하여 재사용합니다.

### ✅ Phase 4 타겟 검증 명령어
```bash
swift test --filter "VocalSeparationTests|VocalSeparationRendererTests|AudioGraphLimiterReverbTests"
```

---

## Phase 5: SwiftUI & UI 레이어 — `ScopeViews` / `HistogramView` 무할당 피크 계산 및 `IOSTimelineView` 드래그 스냅 최적화

### 5-A. `ScopeViews` (`WaveformView`, `RGBParadeView`) `flatMap` 힙 할당 제거 및 `HistogramView` 중복 피크 스캔 제거
- **파일**: `App/MovieCutMac/Inspector/ScopeViews.swift`, `App/MovieCutMac/Inspector/HistogramView.swift`
- **문제점**:
  1. `ScopeViews.swift`의 `WaveformView.peak`(L9)와 `RGBParadeView.paradePanel`(L120, R/G/B 3회 호출)는 매 Canvas 드로잉마다 `waveform.flatMap { $0 }.max()`를 호출하여 **4,096개짜리 `[Int]` 배열을 4번(총 16,384개 `Int`, 128KB) 힙에 할당·파괴**합니다.
  2. `HistogramView.swift`의 `channelPath(_:size:)`(L30-45)는 R/G/B 3채널 각각에서 계산 프로퍼티 `peak`(L8-13)를 호출하여 768개 빈의 최댓값 스캔을 3회 중복 수행합니다.
- **수정 지침**:
  1. `ScopeViews.swift` 하단에 무할당 최댓값 헬퍼를 추가하고 `WaveformView.peak`와 `RGBParadeView.paradePanel`에서 `waveform.flatMap { $0 }.max()` 대신 호출합니다:
     ```swift
     private func maxWaveformCount(_ waveform: [[Int]]) -> Int {
         var best = 1
         for column in waveform {
             for count in column where count > best {
                 best = count
             }
         }
         return best
     }
     ```
  2. `HistogramView.swift`의 `body`(L16-20)에서 `let scale = peak`를 1회만 계산하여 `channelPath(_:size:scale:)`에 전달합니다.

### 5-B. `IOSTimelineView` 드래그 스냅 포인트 캐싱 및 실시간 정렬 가이드(`snapGuideTime`) 활성화
- **파일**: `App/MovieCutiOS/IOSTimelineView.swift`
- **문제점**:
  1. `snappedTime(_:excluding:)`(L247-273)가 `SnapEngine`을 사용하지 않고 5단계 배열 체이닝(`flatMap` → `filter` → `flatMap` → `map` → `+`)으로 임시 배열을 생성합니다.
  2. `dragGesture(for:)`(L210-240)에서 `snappedTime`을 `.onEnded`에서만 호출하고 직후에 `draggedClipId = nil`, `snapGuideTime = nil`로 초기화하여, L42의 정렬 가이드 오버레이(`if let guideTime = snapGuideTime, draggedClipId != nil`)가 드래그 도중 화면에 절대 표시되지 않는 결함이 있습니다.
- **수정 지침**:
  1. `IOSTimelineView`에 `@State private var cachedDragSnapPoints: [Double]? = nil`을 추가합니다.
  2. `dragGesture(for:)`의 `.onChanged`에서 드래그 시작 시(`if draggedClipId != clip.id`) `SnapEngine().generateSnapPoints(from: viewModel.currentProject.timeline, markers: viewModel.currentProject.markers, playheadTime: viewModel.playheadTime, excludingClipId: clip.id)`를 1회 호출해 `cachedDragSnapPoints`에 저장하고, 드래그 중에도 `let initialStart = dragInitialStartTime ?? clip.timelineRange.start`, `let rawStart = max(0, initialStart + Double(value.translation.width / secondsWidth))`에 대해 `snappedTime(rawStart, excluding: clip.id)`를 호출해 `snapGuideTime`이 실시간으로 갱신되도록 합니다.
  3. `.onEnded`에서 `cachedDragSnapPoints = nil`을 함께 정리하고, `snappedTime(_:excluding:)`는 `cachedDragSnapPoints`가 있으면 재사용하여 무할당 루프로 최근접 스냅 포인트를 찾도록 수정합니다.

### ✅ Phase 5 타겟 검증 명령어
```bash
swift build
```

---

## 최종 원클릭 통합 검증 명령어 (전체 완료 후 1회만 실행)

모든 Phase 수정이 끝난 후, 아래 단일 필터 명령어로 이번 Round 4에서 수정한 핵심 모듈들의 테스트만 빠르게 검증하십시오 (약 2~4초 소요):

```bash
swift test --filter "CubeLUT|AutoColorAnalyzer|KeyframeBezier|BeatDetectionTests|SilenceDetectionProviderTests|ClipTimeMappingTests|TranscriptSearchIndexTests|VocalSeparationTests|VocalSeparationRendererTests|AudioGraphLimiterReverbTests"
```
