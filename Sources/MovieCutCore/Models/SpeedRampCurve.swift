import Foundation

/// Computes source/output time mappings for a speed ramp.
public struct SpeedRampCurve: Sendable {
    /// Speed-ramp points sorted by normalized source time.
    public let points: [SpeedRampPoint]

    /// One ramp segment with its boundaries, rates, and pre-integrated
    /// output-time bookkeeping — the mapping queries previously re-walked
    /// and re-integrated every segment on EVERY call; the curve is an
    /// immutable value, so the table is built once at init.
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

    /// Creates a speed-ramp curve with points sorted by time.
    public init(points: [SpeedRampPoint]) {
        let sortedPoints = points.enumerated().sorted { lhs, rhs in
            if lhs.element.time == rhs.element.time {
                return lhs.offset < rhs.offset
            }
            return lhs.element.time < rhs.element.time
        }.map(\.element)

        let normalized: [SpeedRampPoint] = sortedPoints.reduce(into: []) { result, point in
            if result.last?.time == point.time {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
        self.points = normalized

        // Pre-integrate the segment table once (identical accumulation
        // order to the previous per-call loops, so the values are
        // bit-identical).
        var builtSegments: [PrecomputedSegment] = []
        builtSegments.reserveCapacity(normalized.count)
        var segmentStart: TimeInterval = 0
        var startRate = Self.rate(atStartFor: normalized)
        var outputStart: TimeInterval = 0
        for point in normalized where point.time > segmentStart {
            let segmentEnd = point.time
            let endRate = Self.sanitizedRate(point.rate)
            let outputDuration = Self.integralOfReciprocalRate(
                from: segmentStart,
                to: segmentEnd,
                startRate: startRate,
                endRate: endRate,
                segmentEnd: segmentEnd
            )
            builtSegments.append(PrecomputedSegment(
                sourceStart: segmentStart,
                sourceEnd: segmentEnd,
                startRate: startRate,
                endRate: endRate,
                outputStart: outputStart,
                outputDuration: outputDuration
            ))
            outputStart += outputDuration
            segmentStart = segmentEnd
            startRate = endRate
        }
        self.segments = builtSegments
        self.initialRate = normalized.first.map { Self.sanitizedRate($0.rate) } ?? 1
        self.trailingSourceStart = segmentStart
        self.trailingOutputStart = outputStart
        self.trailingRate = startRate
    }

    /// Maps source time to output time by integrating the reciprocal playback rate.
    public func timeMapping(sourceTime: TimeInterval) -> TimeInterval {
        guard points.first != nil else {
            return sourceTime
        }

        if sourceTime <= 0 {
            return sourceTime / initialRate
        }

        // First segment whose end boundary is at or after sourceTime.
        if !segments.isEmpty {
            var low = 0
            var high = segments.count - 1
            while low < high {
                let mid = (low + high) / 2
                if segments[mid].sourceEnd < sourceTime {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            let segment = segments[low]
            if sourceTime <= segment.sourceEnd {
                return segment.outputStart + Self.integralOfReciprocalRate(
                    from: segment.sourceStart,
                    to: sourceTime,
                    startRate: segment.startRate,
                    endRate: segment.endRate,
                    segmentEnd: segment.sourceEnd
                )
            }
        }

        return trailingOutputStart + (sourceTime - trailingSourceStart) / trailingRate
    }

    /// Maps output time back to source time.
    public func inverseMapping(outputTime: TimeInterval) -> TimeInterval {
        guard points.first != nil else {
            return outputTime
        }

        if outputTime <= 0 {
            return outputTime * initialRate
        }

        // First segment whose accumulated output end is at or after outputTime.
        if !segments.isEmpty {
            var low = 0
            var high = segments.count - 1
            while low < high {
                let mid = (low + high) / 2
                if segments[mid].outputStart + segments[mid].outputDuration < outputTime {
                    low = mid + 1
                } else {
                    high = mid
                }
            }
            let segment = segments[low]
            if outputTime <= segment.outputStart + segment.outputDuration {
                return Self.sourceOffset(
                    forOutputOffset: outputTime - segment.outputStart,
                    segmentStart: segment.sourceStart,
                    segmentEnd: segment.sourceEnd,
                    startRate: segment.startRate,
                    endRate: segment.endRate
                )
            }
        }

        return trailingSourceStart + (outputTime - trailingOutputStart) * trailingRate
    }

    /// Returns true when every point uses normal 1.0x playback.
    public func isConstant() -> Bool {
        points.allSatisfy { abs($0.rate - 1) <= Self.epsilon }
    }

    /// A linear identity curve with normal 1.0x playback.
    public static let linear = SpeedRampCurve(points: [
        SpeedRampPoint(time: 0, rate: 1)
    ])

    private static let epsilon = 1.0e-9
    private static let minimumRate = 1.0e-6

    private static func rate(atStartFor points: [SpeedRampPoint]) -> Double {
        for point in points where point.time <= 0 {
            return sanitizedRate(point.rate)
        }
        return sanitizedRate(points[0].rate)
    }

    private static func sanitizedRate(_ rate: Double) -> Double {
        max(rate, minimumRate)
    }

    private static func integralOfReciprocalRate(
        from startTime: TimeInterval,
        to endTime: TimeInterval,
        startRate: Double,
        endRate: Double,
        segmentEnd: TimeInterval
    ) -> TimeInterval {
        let duration = segmentEnd - startTime
        let elapsed = endTime - startTime
        guard duration > epsilon, elapsed > 0 else {
            return 0
        }

        if abs(endRate - startRate) <= epsilon {
            return elapsed / startRate
        }

        let slope = (endRate - startRate) / duration
        let rateAtEndTime = startRate + slope * elapsed
        return log(rateAtEndTime / startRate) / slope
    }

    private static func sourceOffset(
        forOutputOffset outputOffset: TimeInterval,
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval,
        startRate: Double,
        endRate: Double
    ) -> TimeInterval {
        let duration = segmentEnd - segmentStart
        guard duration > epsilon, outputOffset > 0 else {
            return segmentStart
        }

        if abs(endRate - startRate) <= epsilon {
            return segmentStart + outputOffset * startRate
        }

        let slope = (endRate - startRate) / duration
        let elapsed = startRate * (exp(slope * outputOffset) - 1) / slope
        return segmentStart + min(max(elapsed, 0), duration)
    }
}
