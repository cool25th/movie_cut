import Foundation
import Testing
@testable import MovieCutCore

/// G-24 P2-G24-1 — the DoD metrics' math pinned to analytic values (the
/// same functions the P2-G24-6 E2E will reuse on measured displacements).
@Suite("Stabilization Metrics (G-24)")
struct StabilizationMetricsTests {
    // MARK: - Median

    @Test("median: odd/even/empty/single")
    func medianCases() {
        #expect(StabilizationMetrics.median([]) == 0)
        #expect(StabilizationMetrics.median([5]) == 5)
        #expect(StabilizationMetrics.median([1, 9, 3]) == 3)
        #expect(StabilizationMetrics.median([1, 2, 3, 10]) == 2.5)
        #expect(StabilizationMetrics.median([0.1, 0.9, 0.5, 0.5]) == 0.5)
    }

    // MARK: - Report math

    private let input: [StabilizationMetrics.Frame] = (0..<10).map { i in
        .init(displacement: 0.02 + Double(i % 3) * 0.01, isSceneCut: i == 4)
    }

    @Test("a perfect correction halves nothing residual (ratio 0, DoD green)")
    func perfectCorrection() {
        let residual = input.map { frame in StabilizationMetrics.Frame(displacement: 0) }
        let report = StabilizationMetrics.report(
            input: input, residual: residual,
            severeThreshold: 0.05,
            cropFractions: Array(repeating: 0.05, count: 10)
        )
        #expect(report.inputShakeMedian > 0)
        #expect(report.residualShakeMedian == 0)
        #expect(report.reductionRatio == 0)
        #expect(report.severeWobbleFraction == 0)
        #expect(report.sceneCutErrors == 0)
        #expect(report.cropFractionMedian == 0.05)
        #expect(report.meetsDoD())
    }

    @Test("a 50% reduction exactly hits the DoD boundary; 60% passes")
    func reductionBoundary() {
        // Input median 0.03 → residual median 0.015 = ratio 0.5.
        let residual = input.map { frame in StabilizationMetrics.Frame(displacement: 0.015) }
        let boundary = StabilizationMetrics.report(
            input: input, residual: residual,
            severeThreshold: 0.05, cropFractions: [0.1]
        )
        #expect(abs(boundary.reductionRatio - 0.5) < 1e-12)
        #expect(boundary.meetsDoD(), "exactly 50% is the DoD, not beyond it")

        let better = input.map { frame in StabilizationMetrics.Frame(displacement: 0.012) }
        let passing = StabilizationMetrics.report(
            input: input, residual: better,
            severeThreshold: 0.05, cropFractions: [0.1]
        )
        #expect(passing.reductionRatio < 0.5)
        #expect(passing.meetsDoD())
    }

    @Test("severe wobble: >3% of frames above the threshold fails the DoD")
    func severeWobble() {
        // 1 of 10 frames at 0.09 (severe) = 10% > 3%.
        var residual = input.map { frame in StabilizationMetrics.Frame(displacement: 0.01) }
        residual[3] = .init(displacement: 0.09)
        let report = StabilizationMetrics.report(
            input: input, residual: residual,
            severeThreshold: 0.05, cropFractions: [0.1]
        )
        #expect(abs(report.severeWobbleFraction - 0.1) < 1e-12)
        #expect(report.meetsDoD() == false)
    }

    @Test("scene-cut errors: warping across a boundary is a DoD failure")
    func sceneCutErrors() {
        let residual = input.map { frame in StabilizationMetrics.Frame(displacement: 0.005) }
        let report = StabilizationMetrics.report(
            input: input, residual: residual,
            severeThreshold: 0.05, cropFractions: [0.1],
            stabilizedAcrossSceneCut: [false, false, false, false, true, false, false, false, false, false]
        )
        #expect(report.sceneCutErrors == 1)
        #expect(report.meetsDoD() == false)
    }

    @Test("crop: a median above 15% fails the DoD")
    func cropCeiling() {
        let residual = input.map { frame in StabilizationMetrics.Frame(displacement: 0.005) }
        let report = StabilizationMetrics.report(
            input: input, residual: residual,
            severeThreshold: 0.05,
            cropFractions: Array(repeating: 0.16, count: 10)
        )
        #expect(report.cropFractionMedian > 0.15)
        #expect(report.meetsDoD() == false)
    }

    // MARK: - Adaptive crop

    @Test("adaptive crop clamps at the ceiling")
    func adaptiveCropClamp() {
        #expect(StabilizationMetrics.adaptiveCrop(displacement: 0.05) == 0.05)
        #expect(StabilizationMetrics.adaptiveCrop(displacement: 0.30) == 0.15)
        #expect(StabilizationMetrics.adaptiveCrop(displacement: -0.1) == 0)
        #expect(StabilizationMetrics.adaptiveCrop(displacement: 0.30, maxCrop: 0.2) == 0.2)
    }
}
