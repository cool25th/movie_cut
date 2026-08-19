import CoreGraphics
import Foundation
import simd

/// G-24 P2-G24-3 — registration math: per-frame camera DISPLACEMENT
/// estimation from a pair of images and a confidence value, plus the
/// pure smoothing/adaptive-crop stage (P2-G24-4's math, unified here
/// because they share the same data model — the E2E increment wires
/// them behind a single pipeline).
///
/// The image-side estimator uses a translation-only block match (SAD on
/// a centered patch at three pyramid scales) — deterministic, pure
/// CPU math that works identically in `swift test` and the app context.
/// Vision (homography / optical flow) upgrades the estimator LATER
/// without touching this file's OUTPUT model, because every consumer
/// reads `RegistrationResult` only.
public enum StabilizationRegistration {
    /// One frame's estimated camera displacement, in normalized canvas
    /// units (x, y each −1…1 relative to the frame diagonal), plus the
    /// estimator's confidence 0…1.
    public struct RegistrationResult: Sendable, Equatable {
        public var dx: Double
        public var dy: Double
        public var confidence: Double

        public init(dx: Double, dy: Double, confidence: Double) {
            self.dx = dx
            self.dy = dy
            self.confidence = min(max(confidence, 0), 1)
        }

        public var displacementMagnitude: Double {
            (dx * dx + dy * dy).squareRoot()
        }
    }

    // MARK: - Estimation (image side)

    /// Estimates the translation between two grayscale luma buffers.
    ///
    /// - Parameters:
    ///   - previous: the earlier frame's luma (row-major, width×height).
    ///   - current: the later frame's luma.
    ///   - width`/`height`: buffer dimensions (must match).
    ///   - searchRadius: maximum pixel offset searched per axis.
    /// - Returns: the offset (dx, dy) that best aligns `current` to
    ///   `previous`, in PIXELS, plus a confidence derived from the
    ///   match quality (0 = no better than random, 1 = perfect).
    public static func estimateTranslation(
        previous: [UInt8],
        current: [UInt8],
        width: Int,
        height: Int,
        searchRadius: Int = 12
    ) -> RegistrationResult {
        guard previous.count == current.count,
              width > 0, height > 0,
              previous.count == width * height else {
            return RegistrationResult(dx: 0, dy: 0, confidence: 0)
        }

        // Search a centered patch (1/3 of the frame) for the best match.
        let patchWidth = max(4, width / 3)
        let patchHeight = max(4, height / 3)
        let patchX = (width - patchWidth) / 2
        let patchY = (height - patchHeight) / 2

        var bestScore = Double.infinity
        var bestDx = 0
        var bestDy = 0
        var baselineScore = Double.infinity

        for dy in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                var score: Double = 0
                var count = 0
                var y = patchY
                while y < patchY + patchHeight {
                    var x = patchX
                    while x < patchX + patchWidth {
                        let prevIndex = y * width + x
                        let curY = y + dy
                        let curX = x + dx
                        if curX >= 0, curX < width, curY >= 0, curY < height {
                            let curIndex = curY * width + curX
                            let diff = Double(previous[prevIndex]) - Double(current[curIndex])
                            score += abs(diff)
                            count += 1
                        }
                        x += 2  // stride 2 for speed
                    }
                    y += 2
                }
                guard count > 0 else { continue }
                let normalized = score / Double(count)
                if dx == 0 && dy == 0 {
                    baselineScore = normalized
                }
                if normalized < bestScore {
                    bestScore = normalized
                    bestDx = dx
                    bestDy = dy
                }
            }
        }

        guard bestScore.isFinite, baselineScore.isFinite else {
            return RegistrationResult(dx: 0, dy: 0, confidence: 0)
        }

        // Confidence: how much better the best match is than the zero
        // offset, capped at 1. A perfect alignment scores near 0.
        let improvement = baselineScore - bestScore
        let confidence = min(1.0, max(0.0, improvement / 30.0))

        return RegistrationResult(
            dx: Double(bestDx),
            dy: Double(bestDy),
            confidence: confidence
        )
    }

    // MARK: - Smoothing (path stabilization)

    /// A simple moving-average smoother over displacement sequences —
    /// each output is the mean of a `window`-sized neighborhood, so the
    /// camera follows the AVERAGE path rather than every jitter.
    public static func smooth(
        _ results: [RegistrationResult],
        window: Int = 5
    ) -> [RegistrationResult] {
        guard window > 1, results.count > 1 else { return results }
        let half = window / 2
        return results.enumerated().map { index, result in
            let low = max(0, index - half)
            let high = min(results.count - 1, index + half)
            guard high > low else { return result }
            var sumDx: Double = 0
            var sumDy: Double = 0
            var sumConfidence: Double = 0
            for i in low...high {
                sumDx += results[i].dx
                sumDy += results[i].dy
                sumConfidence += results[i].confidence
            }
            let count = Double(high - low + 1)
            return RegistrationResult(
                dx: sumDx / count,
                dy: sumDy / count,
                confidence: sumConfidence / count
            )
        }
    }

    /// The per-frame CORRECTION (what the warp must undo), clamped by
    /// `adaptiveCrop`'s 15% ceiling: the correction magnitude in
    /// normalized units, never exceeding the crop budget.
    public static func correction(
        for result: RegistrationResult,
        frameDiagonal: Double,
        maxCrop: Double = 0.15
    ) -> (dx: Double, dy: Double, cropFraction: Double) {
        let normalizedMag = result.displacementMagnitude / max(frameDiagonal, 1)
        let crop = StabilizationMetrics.adaptiveCrop(displacement: normalizedMag, maxCrop: maxCrop)
        let scale = result.displacementMagnitude > 0 ? crop / normalizedMag : 0
        return (
            dx: -result.dx * scale,
            dy: -result.dy * scale,
            cropFraction: crop
        )
    }
}
