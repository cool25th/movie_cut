import CoreImage
import Foundation
import MovieCutCore
import Testing

/// Covers on-device auto white balance (Phase 3 increment 1).
@Suite("Auto Color Analyzer")
struct AutoColorAnalyzerTests {
    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int = 16) -> [UInt8] {
        var pixels = [UInt8]()
        for _ in 0..<count { pixels.append(contentsOf: [r, g, b, 255]) }
        return pixels
    }

    @Test("a neutral frame suggests no correction")
    func neutralIsIdentity() {
        let grade = AutoColorAnalyzer.autoWhiteBalanceGrade(rgba: solid(128, 128, 128))
        #expect(abs(grade.gain.red - 1) < 1e-9)
        #expect(abs(grade.gain.green - 1) < 1e-9)
        #expect(abs(grade.gain.blue - 1) < 1e-9)
    }

    @Test("a warm frame suggests cooling: gain pulls red down and blue up")
    func warmSuggestsCooling() {
        let grade = AutoColorAnalyzer.autoWhiteBalanceGrade(rgba: solid(200, 150, 100))
        #expect(grade.gain.red < 1)
        #expect(grade.gain.blue > 1)
        #expect(abs(grade.gain.green - 1) < 0.05)
    }

    private func halfAndHalf(_ a: UInt8, _ b: UInt8, count: Int = 100) -> [UInt8] {
        var pixels = [UInt8]()
        for index in 0..<count {
            let v = index < count / 2 ? a : b
            pixels.append(contentsOf: [v, v, v, 255])
        }
        return pixels
    }

    @Test("a low-contrast frame suggests a contrast stretch (gain up, lift down)")
    func lowContrastStretches() {
        let grade = AutoColorAnalyzer.autoLevelsGrade(rgba: halfAndHalf(64, 192))
        #expect(grade.gain.red > 1)
        #expect(grade.lift.red < 0)
        // Uniform across channels (preserves hue).
        #expect(grade.gain.red == grade.gain.blue)
    }

    @Test("a full-range frame needs no level stretch")
    func fullRangeIsIdentity() {
        let grade = AutoColorAnalyzer.autoLevelsGrade(rgba: halfAndHalf(0, 255))
        #expect(abs(grade.gain.red - 1) < 0.05)
        #expect(abs(grade.lift.red) < 0.05)
    }

    @Test("a flat frame can't be stretched and stays identity")
    func flatFrameIsIdentity() {
        let grade = AutoColorAnalyzer.autoLevelsGrade(rgba: solid(128, 128, 128))
        #expect(grade.isIdentity)
    }

    @Test("applying the suggested grade narrows the channel spread toward neutral")
    func applyingNeutralizes() {
        GoldenPixel.assertRendererFunctional()
        let warm = GoldenPixel.RGBA(200, 150, 100)
        let grade = AutoColorAnalyzer.autoWhiteBalanceGrade(rgba: solid(200, 150, 100))

        let corrected = GoldenPixel.sample(
            ColorGradePixelProcessor.apply(grade, to: GoldenPixel.solid(warm))
        )
        let originalSpread = Int(warm.r) - Int(warm.b)
        let correctedSpread = Int(corrected.r) - Int(corrected.b)
        #expect(correctedSpread < originalSpread)
        #expect(correctedSpread >= 0)
    }
}
