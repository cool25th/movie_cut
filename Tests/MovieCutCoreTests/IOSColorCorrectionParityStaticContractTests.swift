import Foundation
import Testing

/// Locks the Phase 1 fix for the Mac/iOS color-correction divergence: iOS now
/// delegates color correction (incl. warmth/tint) to the shared Core
/// `ColorCorrectionPixelProcessor` instead of reimplementing it inline with the
/// opposite warmth sign. Guards against regressing back to a divergent inline
/// path. (iOS can't be built on every host, so this is the regression net.)
@Suite("iOS Color Correction Parity Static Contract")
struct IOSColorCorrectionParityStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("iOS export compositor delegates color correction to the shared processor")
    func compositorDelegates() throws {
        let source = try source("App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift")
        #expect(source.contains("ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)"))
    }

    @Test("iOS preview delegates color correction to the shared processor")
    func previewDelegates() throws {
        let source = try source("App/MovieCutiOS/Views/PreviewView.swift")
        #expect(source.contains("ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)"))
    }

    @Test("iOS no longer hardcodes the divergent inline warmth formula")
    func noDivergentInlineWarmth() throws {
        let preview = try source("App/MovieCutiOS/Views/PreviewView.swift")
        let compositor = try source("App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift")
        // The old inline path used `6500 + colorCorrection.warmth * 1500` (opposite
        // sign / scale from the Core processor). It must not reappear.
        #expect(!preview.contains("6500 + colorCorrection.warmth"))
        #expect(!compositor.contains("6500 + colorCorrection.warmth"))
    }
}
