import Foundation
import Testing

/// Regression lock for the color-grade export wiring (Phase 2A). Behavioral
/// evidence is the golden tests + `run_e2e_export.sh` (which confirms the grade
/// shifts the exported average color); this guards the source wiring from silent
/// removal in plain `swift test`.
@Suite("Color Grade Export Wiring Static Contract")
struct ColorGradeExportWiringStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("custom compositor applies the shared color-grade processor")
    func compositorAppliesGrade() throws {
        let source = try source("App/MovieCutMac/Export/CustomVideoCompositor.swift")
        #expect(source.contains("ColorGradePixelProcessor.apply(colorGrade, to: image)"))
        #expect(source.contains("effect?.colorGrade ?? instruction.colorGrade"))
    }

    @Test("export threads the clip color grade and triggers the custom compositor")
    func exportThreadsGrade() throws {
        let source = try source("App/MovieCutMac/Export/ExportEngine.swift")
        #expect(source.contains("colorGrade: clip.colorGrade"))
        #expect(source.contains("clip.colorGrade != nil"))
    }

    @Test("the color grade is a persisted clip property and command")
    func modelAndCommand() throws {
        let clip = try source("Sources/MovieCutCore/Models/Clip.swift")
        #expect(clip.contains("public var colorGrade: ColorGrade?"))
        let command = try source("Sources/MovieCutCore/Commands/SetClipPropertyCommand.swift")
        #expect(command.contains("case colorGrade(ColorGrade?)"))
    }
}
