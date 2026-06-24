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
}
