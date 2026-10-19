# Guru Architecture Refactoring Plan — Round 5 (V5)

> **목적**: Round 1(`49a0668`), Round 2(`4ea4653`), Round 3(`84e2500`), Round 4(`bfa18bd`) 완료 이후 코드베이스 전수 감사에서 추가로 발굴된 **키프레임 그래프 에디터의 커스텀 베지어(Cubic Bezier) 누락·유실 기능 버그 2건**과 **오디오 엔진(`AVAudioEngine` 브리지 및 오프라인 렌더러) 샘플 루프 병목, 하이라이트 분석 윈도우 스캔 할당, 컬러 커브 UI 및 배경 제거 합성기의 프레임당 중복 연산**을 해결하기 위한 자기완결형(Self-contained) 작업 지시서입니다.

---

## ⚠️ [절대 준수] 테스트 실행 정책 (Strict Test Policy)

작업 중 CPU/메모리 과부하 및 장시간 블로킹을 방지하기 위해 다음 규칙을 **절대적으로 준수**하십시오:

1. **전체 테스트 실행 절대 금지**: `swift test` (필터 없는 전체 실행)는 **절대 실행하지 마십시오**.
2. **UI / E2E / 성능 벤치마크 스위트 실행 금지**: `MovieCutUITests`, `--e2e-*` 플래그가 필요한 테스트, 대용량 미디어 렌더링 벤치마크는 실행하지 마십시오.
3. **타겟팅된 단일/소수 스위트만 실행**: 각 Phase 완료 시 본 문서에 명시된 `swift test --filter "<SuiteName>"` 명령어만 실행하여 빠르게 검증하십시오.
4. **SwiftTesting 매크로 플러그인 유의**: CommandLineTools 환경에서 간헐적으로 `TestingMacros` 로드 경고가 발생할 경우 동일 `swift test --filter` 명령을 1회 재시도하십시오.

---

## 작업 개요 (4 Phases)

| Phase | 대상 도메인 | 핵심 수정 파일 | 핵심 목표 |
| :--- | :--- | :--- | :--- |
| **Phase 1** | 키프레임 그래프 수학 & 제스처 (Domain 1 & 3) | `Sources/MovieCutCore/Editing/KeyframeGraphMath.swift`<br>`Tests/MovieCutCoreTests/KeyframeGraphMathTests.swift` | 1. `polyline(for:samplesPerSegment:)`에서 `.custom` 보간 시 `customCurve: left.customCurve`가 누락되어 선형(Linear)으로 그려지던 버그 수정<br>2. `moved(keyframes:id:time:value:)` 드래그 시 `customCurve: $0.customCurve`가 누락되어 베지어 핸들이 `nil`로 증발하던 버그 수정<br>3. `polyline`, `displayRange`, `hitTest`의 불필요한 중간 배열 할당(`.map`, `.filter`) 제거 및 회귀 테스트 추가 |
| **Phase 2** | 오디오 그래프 엔진 & 오프라인 렌더러 (Domain 4) | `Sources/MovieCutCore/Audio/AudioGraphEngines.swift`<br>`Sources/MovieCutCore/Audio/AudioGraphRendering.swift` | 1. `AudioGraphAVAudioEngineRenderer.precomputedStripBuffer`에서 전체 타임라인 윈도우를 무조건 순회하던 루프를 활성 교집합(`activation.sampleRange`) 및 Mute/Solo 조기 종료로 제한 (오프라인 렌더러와 100% 비트 동일 유지)<br>2. `resolvedStrips`의 $O(N^2)$ 선형 탐색을 Dictionary 인덱싱으로 $O(1)$화<br>3. 48kHz 샘플마다 호출되던 `automationValue`의 $O(P)$ 정렬 검사(`isSorted`)를 스트립/버스 루프 외부 1회 사전 정렬(`ensureSorted` + `automationValuePresorted`)로 호이스팅 |
| **Phase 3** | 미디어 분석 (하이라이트 스코어링 & 스태빌라이제이션) (Domain 2) | `Sources/MovieCutCore/Analysis/HighlightScorer.swift`<br>`Sources/MovieCutCore/Analysis/StabilizationRegistration.swift` | 1. `HighlightScorer.makeCandidate`에서 슬라이딩 윈도우마다 이미 정렬된 `scenes`와 `energy`에 `.filter { ... }.count`를 호출해 힙 배열을 할당하던 문제를 $O(\log N)$ 이진 탐색(`countInRange`)으로 교체<br>2. `StabilizationRegistration.smooth`의 `.enumerated().map` 클로저 할당을 `reserveCapacity` 기반 루프로 최적화 |
| **Phase 4** | 컬러 커브 평가기/UI & 인물 배경제거 합성기 (Domain 1 & 5) | `Sources/MovieCutCore/Rendering/CurveEvaluator.swift`<br>`App/MovieCutMac/Inspector/ColorCurvesView.swift`<br>`Sources/MovieCutCore/Rendering/PersonSegmentationCompositor.swift` | 1. `ColorCurvesView.curveCanvas`에서 65개 샘플 루프마다 `CurveEvaluator.evaluate`를 호출해 매번 정규화·정렬·탄젠트 배열을 재생성하던 병목을 루프 외부 `CurveEvaluator.prepare` 1회 호출 + `evaluatePrecomputed`로 교체<br>2. `CurveEvaluator.monotoneTangents`의 중간 `slopes` 배열 할당 제거<br>3. `PersonSegmentationCompositor`의 프레임당 `CGColorSpaceCreateDeviceRGB()` 및 투명/화이트 `CIImage` 반복 생성을 정적 프로퍼티로 캐싱 |

---

## Phase 1: `KeyframeGraphMath` 커스텀 베지어 버그 수정 및 무할당 최적화 (Domain 1 & 3)

### 1.1 문제 진단
1. **`polyline`에서 `.custom` 베지어 곡선 누락 버그 (`KeyframeGraphMath.swift:62-75`)**:
   - `KeyframeGraphMath.value(at:keyframes:)`(L30-36)는 `customCurve: left.customCurve`를 정상 전달하지만, 정작 그래프 UI(`KeyframeGraphView`)가 폴리라인을 그릴 때 호출하는 `polyline(for:samplesPerSegment:)`(L66-71)에서는 `customCurve` 인자를 생략하여 기본값 `nil`이 전달됩니다.
   - 그 결과 사용자가 커스텀 3차 베지어 곡선(`InterpolationMode.custom`)을 설정해도 그래프 뷰에서는 무조건 직선(Linear)으로 렌더링되어 렌더러 출력과 UI 그래프가 불일치합니다.
2. **`moved`에서 키프레임 드래그 시 `customCurve` 데이터 증발 버그 (`KeyframeGraphMath.swift:122-137`)**:
   - `KeyframeGraphMath.moved(keyframes:id:time:value:)`가 이동된 `Keyframe`을 재생성할 때 `customCurve: $0.customCurve`를 누락하여, 사용자가 그래프 에디터에서 커스텀 베지어 키프레임을 조금만 드래그해도 베지어 제어점 데이터가 `nil`로 유실됩니다.
3. **불필요한 중간 힙 배열 할당 (`polyline`, `displayRange`, `hitTest`)**:
   - `polyline`이 `[(TimeInterval, Double)]` 배열을 만든 뒤 반환 직전 `points.map { (time: $0.0, value: $0.1) }`로 전체 배열을 한 번 더 복사합니다.
   - `displayRange`가 `keyframes.map(\.value)`로 배열을 할당한 뒤 `min()`, `max()`로 2회 스캔합니다.
   - `hitTest`가 `keyframes.filter { ... }`로 후보 배열을 힙에 할당한 뒤 `.min`을 호출합니다.

### 1.2 수정 지침 (`Sources/MovieCutCore/Editing/KeyframeGraphMath.swift`)
- `polyline(for:samplesPerSegment:)`:
  - `var points: [(time: TimeInterval, value: Double)] = []`로 선언하고 `points.reserveCapacity(sorted.count * max(samplesPerSegment, 2))`를 예약한 뒤 직접 튜플을 추가하여 마지막 `.map` 복사를 제거하십시오.
  - `Keyframe.interpolate` 호출 시 `customCurve: left.customCurve`를 반드시 전달하십시오.
- `displayRange(for:)`:
  - `keyframes.map(\.value)` 없이 단일 루프에서 `minimum`과 `maximum`을 동시에 계산하십시오.
- `hitTest(time:value:keyframes:timeTolerance:valueTolerance:)`:
  - `.filter` 배열 할당 없이 단일 루프에서 허용 오차(`timeTolerance`, `valueTolerance`) 내의 최소 거리 키프레임을 찾으십시오.
- `moved(keyframes:id:time:value:)`:
  - `Keyframe` 생성자에 `customCurve: $0.customCurve`를 전달하여 커스텀 베지어 제어점을 보존하십시오.

```swift
    public static func polyline(
        for keyframes: [Keyframe],
        samplesPerSegment: Int = 24
    ) -> [(time: TimeInterval, value: Double)] {
        let sorted = keyframes.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return [] }
        let count = max(samplesPerSegment, 2)
        var points: [(time: TimeInterval, value: Double)] = []
        points.reserveCapacity(1 + max(0, sorted.count - 1) * count)
        points.append((time: first.time, value: first.value))
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            switch left.interpolation {
            case .hold:
                points.append((time: right.time, value: left.value))
                points.append((time: right.time, value: right.value))
            case .linear:
                points.append((time: right.time, value: right.value))
            case .easeIn, .easeOut, .easeInOut, .custom:
                for step in 1...count {
                    let progress = Double(step) / Double(count)
                    let value = Keyframe.interpolate(
                        from: left.value,
                        to: right.value,
                        progress: progress,
                        mode: left.interpolation,
                        customCurve: left.customCurve
                    )
                    let time = left.time + (right.time - left.time) * progress
                    points.append((time: time, value: value))
                }
            }
        }
        return points
    }

    public static func displayRange(for keyframes: [Keyframe]) -> ClosedRange<Double> {
        guard let first = keyframes.first else {
            return 0...1
        }
        var minimum = first.value
        var maximum = first.value
        for keyframe in keyframes.dropFirst() {
            if keyframe.value < minimum { minimum = keyframe.value }
            if keyframe.value > maximum { maximum = keyframe.value }
        }
        let span = maximum - minimum
        let minimumSpan = 0.1
        guard span >= minimumSpan else {
            let center = (minimum + maximum) / 2
            return (center - minimumSpan / 2)...(center + minimumSpan / 2)
        }
        let margin = span * 0.15
        return (minimum - margin)...(maximum + margin)
    }

    public static func hitTest(
        time: TimeInterval,
        value: Double,
        keyframes: [Keyframe],
        timeTolerance: TimeInterval,
        valueTolerance: Double
    ) -> Keyframe? {
        let safeTimeTol = max(timeTolerance, .ulpOfOne)
        let safeValueTol = max(valueTolerance, .ulpOfOne)
        var best: Keyframe?
        var bestDistance = Double.infinity
        for candidate in keyframes {
            let dt = abs(candidate.time - time)
            let dv = abs(candidate.value - value)
            guard dt <= timeTolerance, dv <= valueTolerance else { continue }
            let distance = dt / safeTimeTol + dv / safeValueTol
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    public static func moved(
        keyframes: [Keyframe],
        id: UUID,
        time: TimeInterval,
        value: Double
    ) -> [Keyframe] {
        keyframes.map {
            $0.id == id ? Keyframe(
                id: $0.id,
                property: $0.property,
                time: max(0, time),
                value: value,
                interpolation: $0.interpolation,
                customCurve: $0.customCurve
            ) : $0
        }
    }
```

### 1.3 단위 테스트 추가 (`Tests/MovieCutCoreTests/KeyframeGraphMathTests.swift`)
- `KeyframeGraphMathTests`에 다음 검증을 수행하는 테스트 메서드를 추가하십시오:
  1. `.custom` 보간 키프레임(`CubicBezierCurve(x1: 0.9, y1: 0.0, x2: 1.0, y2: 0.2)` 등 비대칭 베지어)에 대해 `KeyframeGraphMath.polyline`의 중점 샘플 값이 선형 중점과 다르고 `KeyframeGraphMath.value(at:keyframes:)`와 정확히 일치하는지 검증.
  2. `KeyframeGraphMath.moved` 호출 후에도 대상 키프레임의 `customCurve`가 유실되지 않고 그대로 유지되는지 검증.

### 1.4 Phase 1 검증 명령어
```bash
swift test --filter "KeyframeGraphMathTests|KeyframeBezierTests"
```

---

## Phase 2: `AudioGraphEngines` & `AudioGraphRendering` 샘플 루프 최적화 (Domain 4)

### 2.1 문제 진단
1. **`AudioGraphAVAudioEngineRenderer.precomputedStripBuffer` 전체 윈도우 무차별 순회 (`AudioGraphEngines.swift:206-227`)**:
   - `AudioGraphOfflineRenderer.render`(`AudioGraphRendering.swift:152-186`)는 뮤트/비솔로 버스를 즉시 건너뛰고 `start = max(absoluteRange.lowerBound, activation.sampleRange.lowerBound)` ~ `end = min(absoluteRange.upperBound, activation.sampleRange.upperBound)` 교집합 프레임만 순회합니다.
   - 반면 `AudioGraphAVAudioEngineRenderer.precomputedStripBuffer`는 모든 클립 스트립에 대해 **타임라인 전체 윈도우(`0..<window.count`)**를 처음부터 끝까지 순회하며 매 프레임 `stripFrame`을 호출합니다. 클립이 50개이고 각 클립이 전체 타임라인의 2% 길이만 차지해도 50개 스트립 모두 전체 길이를 렌더링하므로 CPU 연산량이 50배 폭증합니다.
2. **`AudioGraphAVAudioEngineRenderer.resolvedStrips` $O(N^2)$ 선형 탐색 (`AudioGraphEngines.swift:177-201`)**:
   - `spec.clipStrips.first(where:)`와 `spec.sources.first(where:)`를 중첩 루프 안에서 반복 호출합니다.
3. **`AudioGraphOfflineRenderer.automationValue` 샘플당 $O(P)$ 정렬 검증 (`AudioGraphRendering.swift:250-260`)**:
   - 48,000Hz 샘플마다 `strip.gain`, `strip.pan`, `bus.fader`, `masterFader`에 대해 `automationValue`가 호출되며, 포인트가 2개 이상이면 매 샘플마다 `for index in 1..<points.count` 루프로 정렬 여부를 다시 검사합니다.

### 2.2 수정 지침 (`Sources/MovieCutCore/Audio/AudioGraphRendering.swift` & `Sources/MovieCutCore/Audio/AudioGraphEngines.swift`)
1. `Sources/MovieCutCore/Audio/AudioGraphRendering.swift`:
   - `ensureSorted(_ points: [AudioGraphAutomationPoint]) -> [AudioGraphAutomationPoint]` 헬퍼를 추가하여 정렬 여부를 1회만 확인하고 필요 시 정렬된 배열을 반환하도록 작성하십시오.
   - 이미 정렬된 배열에 대해 `isSorted` 재검사 없이 즉시 이진 탐색을 수행하는 `automationValuePresorted(_ sorted: [AudioGraphAutomationPoint], at position: Int64) -> Double`을 추가하고, 기존 `automationValue(_:at:)`는 `automationValuePresorted(ensureSorted(points), at: position)`을 호출하도록 리팩터링하십시오.
   - `stripFramePresorted` (또는 `stripFrame` 내부에서 사전 정렬된 커브를 받을 수 있는 오버로드/헬퍼)를 추가하여 `AudioGraphOfflineRenderer.render`와 `AudioGraphAVAudioEngineRenderer.precomputedStripBuffer`가 루프 진입 전 `ensureSorted`를 1회만 호출하고 프레임 루프에서는 정렬 검사를 생략하도록 구성하십시오.

```swift
    static func ensureSorted(_ points: [AudioGraphAutomationPoint]) -> [AudioGraphAutomationPoint] {
        guard points.count > 1 else { return points }
        for index in 1..<points.count where points[index - 1].samplePosition > points[index].samplePosition {
            return points.sorted { $0.samplePosition < $1.samplePosition }
        }
        return points
    }

    static func automationValuePresorted(_ sorted: [AudioGraphAutomationPoint], at position: Int64) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0].value }

        if position <= sorted[0].samplePosition { return sorted[0].value }
        if position >= sorted[sorted.count - 1].samplePosition { return sorted[sorted.count - 1].value }

        var low = 0
        var high = sorted.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if sorted[mid].samplePosition <= position {
                low = mid
            } else {
                high = mid - 1
            }
        }
        let lower = sorted[low]
        let upper = sorted[low + 1]
        let span = upper.samplePosition - lower.samplePosition
        guard span > 0 else { return upper.value }
        let t = Double(position - lower.samplePosition) / Double(span)
        return lower.value + (upper.value - lower.value) * t
    }

    static func automationValue(_ points: [AudioGraphAutomationPoint], at position: Int64) -> Double {
        automationValuePresorted(ensureSorted(points), at: position)
    }
```

2. `Sources/MovieCutCore/Audio/AudioGraphEngines.swift`:
   - `resolvedStrips`에서 `stripsById`와 `sourcesById` 딕셔너리를 사전 생성하여 $O(1)$ 조회로 변경하십시오. (기존과 동일한 에러 순서 보장을 위해 루프 구조와 `throw AudioGraphRenderError.missingInput` 순서는 그대로 유지하십시오.)
   - `precomputedStripBuffer`에서:
     - `var buffer = [Float](repeating: 0, count: window.count * 2)` 초기화 후, `if item.bus.mute || (anySolo && !item.bus.solo) { return buffer }` 조기 반환을 추가하십시오.
     - `let start = max(window.lowerBound, item.activation.sampleRange.lowerBound)` 및 `let end = min(window.upperBound, item.activation.sampleRange.upperBound)`를 계산하고 `guard end > start else { return buffer }`로 비활성 구간을 즉시 스킵하십시오.
     - `start..<end` 구간에 대해서만 샘플을 계산하여 `let index = Int(frame - window.lowerBound)` 위치(`buffer[index * 2]`, `buffer[index * 2 + 1]`)에 기록하십시오.

### 2.3 Phase 2 검증 명령어
```bash
swift test --filter "AudioGraphRenderingTests|AudioGraphEngineNullTests"
```

---

## Phase 3: `HighlightScorer` 이진 탐색 카운팅 & `StabilizationRegistration` 최적화 (Domain 2)

### 3.1 문제 진단
1. **`HighlightScorer.makeCandidate` 슬라이딩 윈도우마다 `.filter` 배열 할당 (`HighlightScorer.swift:139-143`)**:
   - `scoreHighlights`(L88-89)에서 `sortedScenes`와 `sortedEnergy`는 이미 오름차순 정렬되어 있습니다.
   - 그러나 수백~수천 개의 슬라이딩 윈도우마다 호출되는 `makeCandidate` 내부에서:
     ```swift
     let sceneCount = Double(scenes.filter { $0 >= window.start && $0 < window.end }.count)
     let energyCount = Double(energy.filter { $0 >= window.start && $0 < window.end }.count)
     ```
     를 수행하여 윈도우당 2개의 임시 배열을 힙에 할당하고 전체 마커를 $O(N)$ 선형 스캔합니다.
2. **`StabilizationRegistration.smooth` (`StabilizationRegistration.swift:168-193`)**:
   - `results.enumerated().map` 대신 `reserveCapacity(results.count)`를 사용한 명시적 배열 루프로 클로저 오버헤드를 제거할 수 있습니다.

### 3.2 수정 지침 (`Sources/MovieCutCore/Analysis/HighlightScorer.swift` & `Sources/MovieCutCore/Analysis/StabilizationRegistration.swift`)
1. `Sources/MovieCutCore/Analysis/HighlightScorer.swift`:
   - 정렬된 `[TimeInterval]` 배열에서 `[start, end)` 반열린 구간(`$0 >= start && $0 < end`)에 속하는 원소 개수를 무할당 $O(\log N)$ 이진 탐색으로 계산하는 `countInRange(_ sorted: [TimeInterval], start: TimeInterval, end: TimeInterval) -> Int` 헬퍼를 추가하십시오:
     - `lowerBound`: `sorted[mid] < start`이면 `low = mid + 1`, 아니면 `high = mid` (처음으로 `>= start`인 인덱스)
     - `upperBound`: `sorted[mid] < end`이면 `low = mid + 1`, 아니면 `high = mid` (처음으로 `>= end`인 인덱스)
     - 반환값: `max(0, upperBound - lowerBound)`
   - `makeCandidate`에서 `scenes.filter { ... }.count`와 `energy.filter { ... }.count`를 `countInRange(scenes, start: window.start, end: window.end)` 및 `countInRange(energy, start: window.start, end: window.end)`로 교체하십시오.
2. `Sources/MovieCutCore/Analysis/StabilizationRegistration.swift`:
   - `smooth(_:window:)`에서 `var smoothed: [RegistrationResult] = []`, `smoothed.reserveCapacity(results.count)`를 사용하여 결과를 생성하도록 정리하십시오.

### 3.3 Phase 3 검증 명령어
```bash
swift test --filter "HighlightScorerTests|StabilizationRegistrationTests"
```

---

## Phase 4: `CurveEvaluator` / `ColorCurvesView` 사전 준비 & `PersonSegmentationCompositor` 정적 리소스 캐싱 (Domain 1 & 5)

### 4.1 문제 진단
1. **`ColorCurvesView.curveCanvas` 65회 중복 정규화/정렬 (`ColorCurvesView.swift:146-159`)**:
   - 커브 드래그 중 매 프레임 호출되는 `Path` 블록 안에서 `0...64`(65개 샘플)를 순회하며 `CurveEvaluator.evaluate(points: channelPoints, at: x)`를 호출합니다.
   - `CurveEvaluator.evaluate`는 호출될 때마다 `prepare(points)`를 실행하여 딕셔너리 생성, 정렬, 탄젠트 배열 할당을 65번 반복합니다.
   - `CurveEvaluator`에는 이미 `CurveEvaluator.prepare(_:)`와 `CurveEvaluator.evaluatePrecomputed(normalized:tangents:at:)`가 구현되어 있으므로, 루프 밖에서 `prepare`를 1회만 호출하면 64회의 중복 힙 할당·정렬이 즉시 사라집니다.
2. **`CurveEvaluator.monotoneTangents` 중간 `slopes` 배열 할당 (`CurveEvaluator.swift:117`)**:
   - `let slopes = zip(points, points.dropFirst()).map(secant)`로 중간 배열을 힙에 할당하고 있습니다. 인접 기울기는 루프 내에서 즉시 계산하거나 단일 패스로 처리하면 `slopes` 배열 할당을 제거할 수 있습니다.
3. **`PersonSegmentationCompositor` 프레임당 CoreGraphics/CoreImage 객체 재생성 (`PersonSegmentationCompositor.swift:26, 80, 95, 97`)**:
   - `maskContainsForeground`가 매 프레임 `CGColorSpaceCreateDeviceRGB()`를 생성하고, `removeBackground`와 `applyBackgroundRemoval`이 매 프레임 `CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))` 및 `CIImage(color: .white)`를 재생성합니다.

### 4.2 수정 지침
1. `Sources/MovieCutCore/Rendering/CurveEvaluator.swift`:
   - `monotoneTangents(_ points: [CurvePoint])`에서 `slopes` 배열을 별도 할당하지 않고 `secant`를 직접 계산하여 `tangents` 배열만 1회 할당하도록 최적화하십시오 (수치 결과 100% 동일).
2. `App/MovieCutMac/Inspector/ColorCurvesView.swift`:
   - `curveCanvas`의 `Path` 블록(L146-158)에서 루프 진입 전 `let prepared = CurveEvaluator.prepare(channelPoints)`를 1회 호출하고, 루프 내부에서는 `CurveEvaluator.evaluatePrecomputed(normalized: prepared.normalized, tangents: prepared.tangents, at: x)`를 호출하십시오.
3. `Sources/MovieCutCore/Rendering/PersonSegmentationCompositor.swift`:
   - 정적 프로퍼티로 `private static let deviceRGBColorSpace = CGColorSpaceCreateDeviceRGB()`, `private static let clearImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))`, `private static let whiteImage = CIImage(color: .white)`를 선언하고 `removeBackground`, `maskContainsForeground`, `applyBackgroundRemoval`에서 재사용하십시오.

### 4.3 Phase 4 검증 명령어
```bash
swift test --filter "CurveEvaluatorTests|ColorGradeGoldenTests|BackgroundRemovalTests|BackgroundRemovalGoldenTests"
swift build
```

---

## 최종 통합 스모크 검증 (Final Verification)

4개 Phase 수정이 모두 완료되면 아래의 타겟팅된 통합 명령어 1회로 전체 수정 범위의 정합성을 최종 확인하십시오 (약 1~2초 소요):

```bash
swift test --filter "KeyframeGraphMathTests|KeyframeBezierTests|AudioGraphRenderingTests|AudioGraphEngineNullTests|HighlightScorerTests|StabilizationRegistrationTests|CurveEvaluatorTests|ColorGradeGoldenTests|BackgroundRemovalTests|BackgroundRemovalGoldenTests"
```
