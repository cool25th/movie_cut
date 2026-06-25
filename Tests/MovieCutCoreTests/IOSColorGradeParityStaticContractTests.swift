import Foundation
import Testing

/// Locks the iOS color-grade rendering parity (Phase 2A). iOS export and preview
/// now apply the same shared `ColorGradePixelProcessor` as Mac and thread
/// `clip.colorGrade`. iOS can't be built on every host, so this is the
/// regression net. (Grade is set via the shared `ClipProperty.colorGrade`
/// command; an adjustable iOS grade UI tracks the broader iOS-inspector work.)
@Suite("iOS Color Grade Parity Static Contract")
struct IOSColorGradeParityStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("iOS compositor applies the shared color-grade processor")
    func compositorAppliesGrade() throws {
        let source = try source("App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift")
        #expect(source.contains("ColorGradePixelProcessor.apply(colorGrade, to: image)"))
        #expect(source.contains("effect?.colorGrade ?? instruction.colorGrade"))
    }

    @Test("iOS export threads the clip color grade and triggers the compositor")
    func exportThreadsGrade() throws {
        let source = try source("App/MovieCutiOS/Export/IOSExportEngine.swift")
        #expect(source.contains("colorGrade: clip.colorGrade"))
        #expect(source.contains("clip.colorGrade != nil"))
    }

    @Test("iOS preview applies the shared color-grade processor")
    func previewAppliesGrade() throws {
        let source = try source("App/MovieCutiOS/Views/PreviewView.swift")
        #expect(source.contains("ColorGradePixelProcessor.apply(grade, to: result)"))
        #expect(source.contains("colorGrade != nil"))
    }
}
