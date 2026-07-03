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

    @Test("G-09 Inc 2 audit records every Mac-only or deferred iOS gap with a reason")
    func matrixRecordsDeferredGapsWithReasons() throws {
        let matrix = try source("docs/PLATFORM_PARITY_MATRIX.md")

        for required in [
            "2026-07-04 재감사",
            "G-09 Inc 2",
            "Mac-only 또는 iOS defer 항목",
            "정지프레임",
            "speed ramp",
            "역재생",
            "크로마키",
            "전환 two-source",
            "배경제거 Vision",
            "자동저장/크래시 복구",
            "노이즈감소 apply",
            "ProRes/GIF/스틸 export"
        ] {
            #expect(matrix.contains(required))
        }

        let explicitDeferredLines = matrix.split(separator: "\n").filter {
            $0.hasPrefix("- Mac-only 또는 iOS defer 항목:")
        }
        #expect(explicitDeferredLines.count >= 12)
        for deferredLine in explicitDeferredLines {
            #expect(deferredLine.contains("사유"), "deferred row must carry a reason: \(deferredLine)")
        }
    }

    @Test("iOS compositor audit remains honest about shared and missing render paths")
    func iosCompositorAuditMatchesCurrentCodeShape() throws {
        let iosCompositor = try source("App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift")
        let iosPreview = try source("App/MovieCutiOS/Views/PreviewView.swift")
        let matrix = try source("docs/PLATFORM_PARITY_MATRIX.md")

        #expect(iosCompositor.contains("ColorCorrectionPixelProcessor.apply"))
        #expect(iosCompositor.contains("ColorGradePixelProcessor.apply"))
        #expect(iosCompositor.contains("VisualEffectPixelProcessor.apply"))
        #expect(iosCompositor.contains("MaskPixelProcessor.apply"))
        #expect(iosCompositor.contains("TextOverlayPixelProcessor.apply"))
        #expect(iosCompositor.contains("CanvasBackgroundPixelProcessor.compose"))
        #expect(!iosCompositor.contains("TransitionPixelProcessor.apply"))
        #expect(!iosCompositor.contains("PersonSegmentationCompositor"))

        #expect(iosPreview.contains("ColorCorrectionPixelProcessor.apply"))
        #expect(iosPreview.contains("ColorGradePixelProcessor.apply"))
        #expect(!iosPreview.contains("SpeedRampCurve"))

        #expect(matrix.contains("TransitionPixelProcessor` 및 two-source instruction path 미배선"))
        #expect(matrix.contains("PersonSegmentationCompositor` 미사용"))
        #expect(matrix.contains("SpeedRampCurve` 미사용"))
    }
}
