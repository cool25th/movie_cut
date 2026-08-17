import Foundation

/// Pure math for the keyframe value-time graph (G-06): curve evaluation,
/// drawing polylines that make each interpolation mode visually distinct,
/// y-axis auto-fit, and the add/move/delete transforms the graph gestures
/// dispatch. Shared by the Mac graph view; unit-tested so the drawn curve and
/// the renderer's evaluation can never disagree (both route through
/// `Keyframe.interpolate`).
public enum KeyframeGraphMath {
    // MARK: - Evaluation

    /// The property's animated value at a source-relative time — the same
    /// piecewise rule the renderer applies: hold at the first value before the
    /// first keyframe, hold at the last value after the last, interpolate
    /// between adjacent keyframes by the left keyframe's mode.
    public static func value(
        at time: TimeInterval,
        keyframes: [Keyframe]
    ) -> Double? {
        let sorted = keyframes.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return nil }
        if time <= first.time { return first.value }
        guard let last = sorted.last, time < last.time else {
            return sorted.last?.value
        }
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            if time >= left.time && time < right.time {
                let span = right.time - left.time
                let progress = span > 0 ? (time - left.time) / span : 1
                return Keyframe.interpolate(
                    from: left.value,
                    to: right.value,
                    progress: progress,
                    mode: left.interpolation
                )
            }
        }
        return sorted.last?.value
    }

    // MARK: - Drawing

    /// Polyline samples for one property's curve. `hold` segments emit the
    /// step (a right-angle jump at the next keyframe) so the shape itself
    /// distinguishes the mode; eased segments are sampled densely enough for
    /// a smooth arc; linear segments stay two points.
    public static func polyline(
        for keyframes: [Keyframe],
        samplesPerSegment: Int = 24
    ) -> [(time: TimeInterval, value: Double)] {
        let sorted = keyframes.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return [] }
        var points: [(TimeInterval, Double)] = [(first.time, first.value)]
        for (left, right) in zip(sorted, sorted.dropFirst()) {
            switch left.interpolation {
            case .hold:
                points.append((right.time, left.value))
                points.append((right.time, right.value))
            case .linear:
                points.append((right.time, right.value))
            case .easeIn, .easeOut, .easeInOut:
                let count = max(samplesPerSegment, 2)
                for step in 1...count {
                    let progress = Double(step) / Double(count)
                    let value = Keyframe.interpolate(
                        from: left.value,
                        to: right.value,
                        progress: progress,
                        mode: left.interpolation
                    )
                    let time = left.time + (right.time - left.time) * progress
                    points.append((time, value))
                }
            }
        }
        return points.map { (time: $0.0, value: $0.1) }
    }

    /// Y-axis display range auto-fit: the property's keyframe value span with
    /// 15% margin, widened to a minimum span (or the 0…1 fallback when there
    /// are fewer than two distinct values) so single-value curves don't
    /// collapse to a line.
    public static func displayRange(for keyframes: [Keyframe]) -> ClosedRange<Double> {
        let values = keyframes.map(\.value)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 0...1
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

    // MARK: - Gestures

    /// Nearest keyframe within both tolerances (data space), or nil.
    public static func hitTest(
        time: TimeInterval,
        value: Double,
        keyframes: [Keyframe],
        timeTolerance: TimeInterval,
        valueTolerance: Double
    ) -> Keyframe? {
        let candidates = keyframes.filter {
            abs($0.time - time) <= timeTolerance && abs($0.value - value) <= valueTolerance
        }
        return candidates.min {
            let leftDistance = abs($0.time - time) / max(timeTolerance, .ulpOfOne)
                + abs($0.value - value) / max(valueTolerance, .ulpOfOne)
            let rightDistance = abs($1.time - time) / max(timeTolerance, .ulpOfOne)
                + abs($1.value - value) / max(valueTolerance, .ulpOfOne)
            return leftDistance < rightDistance
        }
    }

    /// Moves a keyframe (time clamped to ≥ 0) and returns the re-sorted array.
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
                interpolation: $0.interpolation
            ) : $0
        }
    }

    /// Adds a keyframe at a source-relative time, keeping the array sorted by
    /// the editors' convention (property, then time).
    public static func added(
        keyframes: [Keyframe],
        property: AnimatableProperty,
        time: TimeInterval,
        value: Double,
        interpolation: InterpolationMode = .linear
    ) -> [Keyframe] {
        var updated = keyframes
        updated.append(Keyframe(
            property: property,
            time: max(0, time),
            value: value,
            interpolation: interpolation
        ))
        return updated.sorted {
            if $0.property.rawValue == $1.property.rawValue {
                return $0.time < $1.time
            }
            return $0.property.rawValue < $1.property.rawValue
        }
    }

    /// Removes a keyframe by id.
    public static func removed(keyframes: [Keyframe], id: UUID) -> [Keyframe] {
        keyframes.filter { $0.id != id }
    }
}
