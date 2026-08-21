import CoreGraphics
import Foundation

/// G-24 P2-G24-1 — pure math for measuring stabilization quality against
/// the backlog §0.5 DoD numbers. No Vision, no rendering, no I/O — every
/// function is deterministic on its inputs so unit tests pin analytic
/// values and the E2E (P2-G24-6) reuses the SAME functions on measured
/// displacement sequences.
///
/// Model: stabilization is a sequence of per-frame DISPLACEMENTS (the
/// camera shake, in normalized canvas units) before and after correction.
/// The metrics are:
///
/// - **residualShakeMedian**: the median frame-to-frame displacement
///   magnitude — the DoD's "잔류 흔들림 중앙값" (target: −50% vs input).
/// - **cropFraction**: the fraction of the canvas the adaptive crop
///   removes to realize the correction (target: median ≤ 15%).
/// - **severeWobbleFraction**: frames whose displacement exceeds
///   `severeThreshold` — the DoD's "심각 워블" (target: ≤ 3%).
/// - **sceneCutErrors**: frames flagged as stabilized motion AT a scene
///   boundary (target: 0 — segmentation is the defense).
public enum StabilizationMetrics {
    /// One frame's measured camera displacement, in normalized canvas
    /// units (0…1 diagonal). `isSceneCut` marks a detected scene boundary.
    public struct Frame: Sendable, Equatable {
        public var displacement: Double
        public var isSceneCut: Bool

        public init(displacement: Double, isSceneCut: Bool = false) {
            self.displacement = max(0, displacement)
            self.isSceneCut = isSceneCut
        }
    }

    /// The quality report the DoD gates on.
    public struct Report: Sendable, Equatable {
        /// Median frame-to-frame displacement magnitude.
        public var residualShakeMedian: Double
        /// The input's median displacement (for the −50% comparison).
        public var inputShakeMedian: Double
        /// Reduction ratio (residual / input) — the DoD's "50%↓" is
        /// `reductionRatio <= 0.5`.
        public var reductionRatio: Double
        /// Fraction of frames above the severe threshold.
        public var severeWobbleFraction: Double
        /// Frames stabilized ACROSS a scene cut (must be 0).
        public var sceneCutErrors: Int
        /// The median crop fraction the correction needs.
        public var cropFractionMedian: Double

        public init(
            residualShakeMedian: Double,
            inputShakeMedian: Double,
            reductionRatio: Double,
            severeWobbleFraction: Double,
            sceneCutErrors: Int,
            cropFractionMedian: Double
        ) {
            self.residualShakeMedian = residualShakeMedian
            self.inputShakeMedian = inputShakeMedian
            self.reductionRatio = reductionRatio
            self.severeWobbleFraction = severeWobbleFraction
            self.sceneCutErrors = sceneCutErrors
            self.cropFractionMedian = cropFractionMedian
        }

        /// The backlog §0.5 DoD as one predicate:
        /// residual −50%·crop ≤ 15%·severe wobble ≤ 3%·scene-cut errors 0.
        public func meetsDoD() -> Bool {
            reductionRatio <= 0.5
                && cropFractionMedian <= 0.15
                && severeWobbleFraction <= 0.03
                && sceneCutErrors == 0
        }
    }

    /// Median of a double collection (even counts average the middle pair).
    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[mid]
        }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// The full report for a before/after displacement pair.
    ///
    /// - Parameters:
    ///   - input: the pre-stabilization displacements.
    ///   - residual: the post-stabilization displacements (same length;
    ///     scene-cut flags copied from `input`).
    ///   - severeThreshold: the displacement above which a frame counts as
    ///     severe wobble (normalized units; the fixture pins this).
    ///   - cropFractions: the per-frame crop each correction needs (0…1).
    ///   - stabilizedAcrossSceneCut: which frames the CORRECTOR chose to
    ///     warp across a boundary (segmentation should make this all false).
    public static func report(
        input: [Frame],
        residual: [Frame],
        severeThreshold: Double,
        cropFractions: [Double],
        stabilizedAcrossSceneCut: [Bool] = []
    ) -> Report {
        let inputMedian = median(input.map(\.displacement))
        let residualMedian = median(residual.map(\.displacement))
        let ratio = inputMedian > 0 ? residualMedian / inputMedian : (residualMedian == 0 ? 0 : 1)

        let severeCount = residual.filter { $0.displacement > severeThreshold }.count
        let severeFraction = residual.isEmpty ? 0 : Double(severeCount) / Double(residual.count)

        // Scene-cut errors: corrector-warped frames the input flags as cuts.
        var cutErrors = 0
        for (index, warped) in stabilizedAcrossSceneCut.enumerated() {
            if warped, index < input.count, input[index].isSceneCut {
                cutErrors += 1
            }
        }

        return Report(
            residualShakeMedian: residualMedian,
            inputShakeMedian: inputMedian,
            reductionRatio: ratio,
            severeWobbleFraction: severeFraction,
            sceneCutErrors: cutErrors,
            cropFractionMedian: median(cropFractions)
        )
    }

    /// The adaptive crop for one frame's correction: the displacement the
    /// warp must absorb, clamped to `maxCrop` (the DoD's 15% ceiling).
    public static func adaptiveCrop(
        displacement: Double,
        maxCrop: Double = 0.15
    ) -> Double {
        min(max(0, displacement), maxCrop)
    }
}
