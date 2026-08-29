import Foundation
import Testing
@testable import MovieCutCore

/// Covers the color-scope pixel reductions (Phase 2A increment 6).
@Suite("Scope Analyzer")
struct ScopeAnalyzerTests {
    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int) -> [UInt8] {
        var pixels = [UInt8]()
        pixels.reserveCapacity(count * 4)
        for _ in 0..<count { pixels.append(contentsOf: [r, g, b, 255]) }
        return pixels
    }

    @Test("rec.709 luma of pure channels")
    func lumaWeights() {
        #expect(ScopeAnalyzer.luma(red: 255, green: 0, blue: 0) == 54)
        #expect(ScopeAnalyzer.luma(red: 0, green: 255, blue: 0) == 182)
        #expect(ScopeAnalyzer.luma(red: 0, green: 0, blue: 255) == 18)
        #expect(ScopeAnalyzer.luma(red: 255, green: 255, blue: 255) == 255)
    }

    @Test("pure red lands in the top red bin and bottom green/blue bins")
    func redHistogram() {
        let histogram = ScopeAnalyzer.histogram(rgba: solid(255, 0, 0, count: 10), binCount: 64)
        #expect(histogram.red[63] == 10)
        #expect(histogram.red[0] == 0)
        #expect(histogram.green[0] == 10)
        #expect(histogram.blue[0] == 10)
        // Luma of pure red (54) falls in bin 13.
        #expect(histogram.luma[13] == 10)
        #expect(histogram.red.reduce(0, +) == 10)
    }

    @Test("white concentrates every channel in the top bin")
    func whiteHistogram() {
        let histogram = ScopeAnalyzer.histogram(rgba: solid(255, 255, 255, count: 5), binCount: 64)
        #expect(histogram.red[63] == 5)
        #expect(histogram.green[63] == 5)
        #expect(histogram.blue[63] == 5)
        #expect(histogram.luma[63] == 5)
    }

    @Test("black concentrates every channel in the bottom bin")
    func blackHistogram() {
        let histogram = ScopeAnalyzer.histogram(rgba: solid(0, 0, 0, count: 7), binCount: 32)
        #expect(histogram.red[0] == 7)
        #expect(histogram.luma[0] == 7)
        #expect(histogram.red.count == 32)
    }

    @Test("neutral gray lands at the vectorscope center")
    func grayVectorscope() {
        let scope = ScopeAnalyzer.vectorscope(rgba: solid(128, 128, 128, count: 9), size: 48)
        let center = 24 * 48 + 24
        #expect(scope.counts[center] == 9)
        #expect(scope.counts.reduce(0, +) == 9)
    }

    @Test("saturated red spreads away from the vectorscope center")
    func redVectorscope() {
        let scope = ScopeAnalyzer.vectorscope(rgba: solid(255, 0, 0, count: 6), size: 48)
        let center = 24 * 48 + 24
        #expect(scope.counts[center] == 0)
        #expect(scope.counts.reduce(0, +) == 6)
        // Red pushes the R-Y (y) axis to its upper edge.
        let redCell = scope.counts.firstIndex(of: 6)
        #expect(redCell != nil && redCell! / 48 >= 40)
    }

    @Test("luma waveform has the requested shape and bins each column")
    func waveformShape() {
        let waveform = ScopeAnalyzer.lumaWaveform(
            rgba: solid(255, 255, 255, count: 4),
            width: 2, height: 2, columns: 2, levels: 4
        )
        #expect(waveform.count == 2)
        #expect(waveform[0].count == 4)
        // White luma (255) -> top level; each 2px-tall column has 2 white pixels.
        #expect(waveform[0][3] == 2)
        #expect(waveform[1][3] == 2)
        #expect(waveform[0][0] == 0)
    }

    // MARK: - RGB parade (CA-28)

    /// A 4px-wide, 1px-tall row whose red channel ramps 0→255 left to right;
    /// green/blue stay 0.
    private func redRampRow() -> [UInt8] {
        var pixels = [UInt8]()
        pixels.reserveCapacity(4 * 4)
        for x in 0..<4 {
            pixels.append(contentsOf: [UInt8(x * 85), 0, 0, 255])
        }
        return pixels
    }

    @Test("RGB parade separates channels: pure red tops R, bottoms G and B")
    func paradeSeparatesChannels() {
        let parade = ScopeAnalyzer.rgbParade(
            rgba: solid(255, 0, 0, count: 4),
            width: 2, height: 2, columns: 2, levels: 4
        )
        #expect(parade.red.count == 2)
        #expect(parade.red[0].count == 4)
        // Pure red: every pixel's R=255 lands in the top level of both columns.
        #expect(parade.red[0][3] == 2)
        #expect(parade.red[1][3] == 2)
        // …while G and B collapse to the bottom level.
        #expect(parade.green[0][0] == 2)
        #expect(parade.blue[1][0] == 2)
        #expect(parade.green.reduce(0) { $0 + $1.reduce(0, +) } == 4)
    }

    @Test("RGB parade tracks a horizontal red ramp across columns")
    func paradeTracksXRamp() {
        let parade = ScopeAnalyzer.rgbParade(
            rgba: redRampRow(),
            width: 4, height: 1, columns: 4, levels: 4
        )
        // x=0 (R=0) → level 0; x=1 (R=85) → 85*4/256 = 1; x=2 (R=170) → 2;
        // x=3 (R=255) → top level 3. One pixel per column.
        #expect(parade.red[0][0] == 1)
        #expect(parade.red[1][1] == 1)
        #expect(parade.red[2][2] == 1)
        #expect(parade.red[3][3] == 1)
        // Blue stays at the bottom everywhere on the ramp row.
        for column in 0..<4 {
            #expect(parade.blue[column][0] == 1)
        }
    }

    @Test("RGB parade bins each channel independently per pixel")
    func paradeMixedPixel() {
        // One pixel (R=255, G=0, B=128): R top level, G bottom, B exactly
        // level 2 (128*4/256 = 2) — a white-balance skew shows as B lagging R.
        let parade = ScopeAnalyzer.rgbParade(
            rgba: solid(255, 0, 128, count: 1),
            width: 1, height: 1, columns: 1, levels: 4
        )
        #expect(parade.red[0][3] == 1)
        #expect(parade.green[0][0] == 1)
        #expect(parade.blue[0][2] == 1)
    }

    @Test("RGB parade guards degenerate geometry like the luma waveform")
    func paradeDegenerateGeometry() {
        let empty = ScopeAnalyzer.rgbParade(rgba: [], width: 0, height: 0, columns: 4, levels: 4)
        #expect(empty.red.isEmpty && empty.green.isEmpty && empty.blue.isEmpty)
        let zeroLevels = ScopeAnalyzer.rgbParade(
            rgba: solid(1, 2, 3, count: 1), width: 1, height: 1, columns: 4, levels: 0
        )
        #expect(zeroLevels.red.isEmpty)
    }
}
