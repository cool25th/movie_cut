import CoreImage
import Foundation
import Testing

@testable import MovieCutCore

/// CA-21 fallout: the histogram extraction returned all zeros for EVERY
/// frame (CIAreaHistogram output misread — detected by the first-ever
/// functional measurement, 2026-09-04), so scene detection never fired.
/// These always-on tests pin the actual math so the provider can never
/// silently regress to "detects nothing" again.
@Suite("SceneChange histogram math")
struct SceneChangeHistogramMathTests {
    private func solid(_ v: CGFloat, size: CGFloat = 64) -> CIImage {
        CIImage(color: CIColor(red: v, green: v, blue: v))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    @Test("histogram of a solid frame concentrates its mass in one bin")
    func solidFrameSingleBin() {
        let provider = SceneChangeProvider()
        let black = provider.computeHistogram(for: solid(0))
        #expect(abs(black.reduce(0, +) - 1.0) < 0.01, "a histogram must sum to ~1 (all-zeros is the 2026-09-04 defect signature)")
        #expect(black[0] > 0.99)
        let white = provider.computeHistogram(for: solid(1))
        #expect(white[63] > 0.99)
    }

    @Test("black→white chi-squared difference exceeds the default threshold; identical frames are ~0")
    func differenceSeparatesChanges() {
        let provider = SceneChangeProvider()
        let black = provider.computeHistogram(for: solid(0))
        let white = provider.computeHistogram(for: solid(1))
        let gray = provider.computeHistogram(for: solid(0.5))
        #expect(provider.histogramDifference(black, white) > provider.changeThreshold,
                "a hard luminance cut must clear the 0.3 default threshold")
        #expect(provider.histogramDifference(black, black) < 0.01)
        #expect(provider.histogramDifference(gray, gray) < 0.01)
    }
}
