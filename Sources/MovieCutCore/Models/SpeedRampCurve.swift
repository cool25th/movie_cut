import Foundation

/// Computes source/output time mappings for a speed ramp.
public struct SpeedRampCurve: Sendable {
    /// Speed-ramp points sorted by normalized source time.
    public let points: [SpeedRampPoint]

    /// Creates a speed-ramp curve with points sorted by time.
    public init(points: [SpeedRampPoint]) {
        let sortedPoints = points.enumerated().sorted { lhs, rhs in
            if lhs.element.time == rhs.element.time {
                return lhs.offset < rhs.offset
            }
            return lhs.element.time < rhs.element.time
        }.map(\.element)

        self.points = sortedPoints.reduce(into: []) { result, point in
            if result.last?.time == point.time {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
    }

    /// Maps source time to output time by integrating the reciprocal playback rate.
    public func timeMapping(sourceTime: TimeInterval) -> TimeInterval {
        guard let firstPoint = points.first else {
            return sourceTime
        }

        if sourceTime <= 0 {
            return sourceTime / Self.sanitizedRate(firstPoint.rate)
        }

        var outputTime: TimeInterval = 0
        var segmentStart: TimeInterval = 0
        var startRate = Self.rate(atStartFor: points)

        for point in points where point.time > segmentStart {
            let segmentEnd = point.time
            let endRate = Self.sanitizedRate(point.rate)
            if sourceTime <= segmentEnd {
                return outputTime + Self.integralOfReciprocalRate(
                    from: segmentStart,
                    to: sourceTime,
                    startRate: startRate,
                    endRate: endRate,
                    segmentEnd: segmentEnd
                )
            }

            outputTime += Self.integralOfReciprocalRate(
                from: segmentStart,
                to: segmentEnd,
                startRate: startRate,
                endRate: endRate,
                segmentEnd: segmentEnd
            )
            segmentStart = segmentEnd
            startRate = endRate
        }

        return outputTime + (sourceTime - segmentStart) / startRate
    }

    /// Maps output time back to source time.
    public func inverseMapping(outputTime: TimeInterval) -> TimeInterval {
        guard let firstPoint = points.first else {
            return outputTime
        }

        if outputTime <= 0 {
            return outputTime * Self.sanitizedRate(firstPoint.rate)
        }

        var accumulatedOutputTime: TimeInterval = 0
        var segmentStart: TimeInterval = 0
        var startRate = Self.rate(atStartFor: points)

        for point in points where point.time > segmentStart {
            let segmentEnd = point.time
            let endRate = Self.sanitizedRate(point.rate)
            let segmentOutputTime = Self.integralOfReciprocalRate(
                from: segmentStart,
                to: segmentEnd,
                startRate: startRate,
                endRate: endRate,
                segmentEnd: segmentEnd
            )

            if outputTime <= accumulatedOutputTime + segmentOutputTime {
                return Self.sourceOffset(
                    forOutputOffset: outputTime - accumulatedOutputTime,
                    segmentStart: segmentStart,
                    segmentEnd: segmentEnd,
                    startRate: startRate,
                    endRate: endRate
                )
            }

            accumulatedOutputTime += segmentOutputTime
            segmentStart = segmentEnd
            startRate = endRate
        }

        return segmentStart + (outputTime - accumulatedOutputTime) * startRate
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
