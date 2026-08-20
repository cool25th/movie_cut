import Foundation
import Testing
@testable import MovieCutCore

/// G-24 P2-G24-3 — registration estimation on SYNTHETIC images with
/// analytically known offsets, plus the smoothing and correction math.
@Suite("Stabilization Registration (G-24)")
struct StabilizationRegistrationTests {
    /// A deterministic textured image (gradient + stripes) so SAD is
    /// discriminative across shifts.
    private func syntheticImage(width: Int, height: Int) -> [UInt8] {
        (0..<height).flatMap { y in
            (0..<width).map { x in
                UInt8(clamping: (x * 3 + y * 7 + ((x / 8 + y / 8) % 2) * 40) % 256)
            }
        }
    }

    /// Shifts an image by whole pixels (nearest).
    private func shifted(_ image: [UInt8], width: Int, height: Int, dx: Int, dy: Int) -> [UInt8] {
        (0..<height).flatMap { y in
            (0..<width).map { x in
                let sy = y - dy
                let sx = x - dx
                guard sx >= 0, sx < width, sy >= 0, sy < height else { return UInt8(0) }
                return image[sy * width + sx]
            }
        }
    }

    @Test("a known 5-pixel shift is recovered within ±1 pixel")
    func knownShiftRecovery() {
        let width = 96
        let height = 72
        let base = syntheticImage(width: width, height: height)
        let shiftedImage = shifted(base, width: width, height: height, dx: 5, dy: -3)
        let result = StabilizationRegistration.estimateTranslation(
            previous: base, current: shiftedImage, width: width, height: height
        )
        // The shift is (5, -3): estimate should recover within ±1.
        #expect(abs(result.dx - 5) <= 1, "dx: \(result.dx)")
        #expect(abs(result.dy - (-3)) <= 1, "dy: \(result.dy)")
        #expect(result.confidence > 0.3, "textured shift must be confident: \(result.confidence)")
    }

    @Test("a half-pixel bilinear shift is recovered within a third of a pixel")
    func subPixelShiftRecovery() {
        let width = 96
        let height = 72
        let base = syntheticImage(width: width, height: height)
        // Bilinear-shift by (2.5, −1.5): the integer SAD minimum alone
        // quantizes to ±1px; the parabolic refinement must land near the
        // true offset (the #9 real-render gate exposed the noise floor).
        let shiftedImage: [UInt8] = (0..<height).flatMap { y in
            (0..<width).map { x in
                let sy = Double(y) + 1.5
                let sx = Double(x) - 2.5
                let x0 = Int(sx.rounded(.down)), y0 = Int(sy.rounded(.down))
                let fx = sx - Double(x0), fy = sy - Double(y0)
                func sample(_ xx: Int, _ yy: Int) -> Double {
                    guard xx >= 0, xx < width, yy >= 0, yy < height else { return 0 }
                    return Double(base[yy * width + xx])
                }
                let value = sample(x0, y0) * (1 - fx) * (1 - fy)
                    + sample(x0 + 1, y0) * fx * (1 - fy)
                    + sample(x0, y0 + 1) * (1 - fx) * fy
                    + sample(x0 + 1, y0 + 1) * fx * fy
                return UInt8(clamping: Int(value.rounded()))
            }
        }
        let result = StabilizationRegistration.estimateTranslation(
            previous: base, current: shiftedImage, width: width, height: height
        )
        #expect(abs(result.dx - 2.5) <= 1.0 / 3, "dx: \(result.dx)")
        #expect(abs(result.dy - (-1.5)) <= 1.0 / 3, "dy: \(result.dy)")
    }

    @Test("identical images give zero displacement and zero confidence")
    func identicalImages() {
        let image = syntheticImage(width: 64, height: 48)
        let result = StabilizationRegistration.estimateTranslation(
            previous: image, current: image, width: 64, height: 48
        )
        #expect(result.dx == 0 && result.dy == 0)
        #expect(result.confidence == 0, "no improvement over zero offset")
    }

    @Test("empty or mismatched buffers are safe")
    func degenerateBuffers() {
        let empty = StabilizationRegistration.estimateTranslation(
            previous: [], current: [], width: 0, height: 0
        )
        #expect(empty.dx == 0 && empty.dy == 0 && empty.confidence == 0)
    }

    // MARK: - Smoothing

    @Test("smoothing reduces a spike's magnitude")
    func smoothingReducesSpikes() {
        var results = (0..<20).map { i in
            StabilizationRegistration.RegistrationResult(dx: 1.0, dy: 0, confidence: 0.8)
        }
        results[10] = .init(dx: 20, dy: 0, confidence: 0.8)
        let smoothed = StabilizationRegistration.smooth(results, window: 5)
        #expect(smoothed.count == results.count)
        #expect(smoothed[10].dx < 10, "the spike must be pulled at least 50% toward the mean")
        #expect(smoothed[5].dx == 1.0, "interior uniform regions are stable")
        // The total variance drops.
        let beforeVariance = results.map { ($0.dx - 1.9) * ($0.dx - 1.9) }.reduce(0, +)
        let afterVariance = smoothed.map { ($0.dx - 1.9) * ($0.dx - 1.9) }.reduce(0, +)
        #expect(afterVariance < beforeVariance)
    }

    @Test("smoothing is identity for window ≤ 1 or single elements")
    func smoothingEdgeCases() {
        let single: [StabilizationRegistration.RegistrationResult] = [.init(dx: 3, dy: 1, confidence: 0.5)]
        #expect(StabilizationRegistration.smooth(single, window: 5) == single)
        let pair: [StabilizationRegistration.RegistrationResult] = [
            .init(dx: 0, dy: 0, confidence: 1),
            .init(dx: 4, dy: 2, confidence: 1),
        ]
        #expect(StabilizationRegistration.smooth(pair, window: 1) == pair)
    }

    // MARK: - Correction + crop

    @Test("the correction inverts the displacement and respects the crop ceiling")
    func correctionMath() {
        // 100px diagonal, 8px displacement → normalized 0.08 < 15%.
        let small = StabilizationRegistration.RegistrationResult(dx: 6, dy: -4, confidence: 0.9)
        let smallCorrection = StabilizationRegistration.correction(for: small, frameDiagonal: 100)
        #expect(smallCorrection.cropFraction == small.displacementMagnitude / 100)
        #expect(smallCorrection.dx == -small.dx)
        #expect(smallCorrection.dy == -small.dy)

        // 50px displacement on 100px diagonal → normalized 0.5, clamped to 15%.
        let large = StabilizationRegistration.RegistrationResult(dx: 40, dy: 30, confidence: 0.9)
        let largeCorrection = StabilizationRegistration.correction(for: large, frameDiagonal: 100)
        #expect(largeCorrection.cropFraction == 0.15)
        #expect(abs(largeCorrection.dx) < abs(-large.dx), "the correction is clamped")
    }

    @Test("zero displacement yields zero correction")
    func zeroCorrection() {
        let zero = StabilizationRegistration.RegistrationResult(dx: 0, dy: 0, confidence: 0)
        let correction = StabilizationRegistration.correction(for: zero, frameDiagonal: 100)
        #expect(correction.dx == 0 && correction.dy == 0 && correction.cropFraction == 0)
    }
}
