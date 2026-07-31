import Foundation
import Testing

@Suite("iOS Parity Matrix Static Contract")
struct IOSParityMatrixStaticContractTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("iOS compositor audit remains honest about shared render paths")
    func iosCompositorAuditMatchesCurrentCodeShape() throws {
        let iosCompositor = try source("App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift")
        let iosPreview = try source("App/MovieCutiOS/Views/PreviewView.swift")

        // Positive contract: the shared Core render processors that ARE wired
        // into iOS must be present. (Negative source assertions were removed so
        // implementing TransitionPixelProcessor / PersonSegmentationCompositor /
        // SpeedRampCurve on iOS does not turn this test red — those gaps are
        // tracked in docs/PLATFORM_PARITY_MATRIX.md, not pinned in tests.)
        #expect(iosCompositor.contains("ColorCorrectionPixelProcessor.apply"))
        #expect(iosCompositor.contains("ColorGradePixelProcessor.apply"))
        #expect(iosCompositor.contains("VisualEffectPixelProcessor.apply"))
        #expect(iosCompositor.contains("MaskPixelProcessor.apply"))
        #expect(iosCompositor.contains("TextOverlayPixelProcessor.apply"))
        #expect(iosCompositor.contains("CanvasBackgroundPixelProcessor.compose"))

        #expect(iosPreview.contains("ColorCorrectionPixelProcessor.apply"))
        #expect(iosPreview.contains("ColorGradePixelProcessor.apply"))
    }
}
