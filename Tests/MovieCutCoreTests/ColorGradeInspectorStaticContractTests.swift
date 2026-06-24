import Foundation
import Testing

/// Regression lock for the color-grade inspector UI (Phase 2A increment 4).
/// The slider → `updateSelectedColorGrade` → command → compositor path is already
/// proven end-to-end (`run_e2e_export.sh`); this guards that the controls are
/// present and bound.
@Suite("Color Grade Inspector Static Contract")
struct ColorGradeInspectorStaticContractTests {
    private func source() throws -> String {
        try String(contentsOfFile: "App/MovieCutMac/Inspector/InspectorEffectsSection.swift", encoding: .utf8)
    }

    @Test("the inspector exposes a color grade section with lift/gamma/gain")
    func sectionExposed() throws {
        let source = try source()
        #expect(source.contains("private var colorGradeSection"))
        #expect(source.contains("colorGradeSection"))
        #expect(source.contains("Lift · shadows"))
        #expect(source.contains("Gamma · midtones"))
        #expect(source.contains("Gain · highlights"))
    }

    @Test("grade controls bind to the color-grade command path")
    func controlsBindToCommand() throws {
        let source = try source()
        #expect(source.contains("colorGradeBinding(keyPath: \\.lift.red)"))
        #expect(source.contains("colorGradeBinding(keyPath: \\.gamma)"))
        #expect(source.contains("colorGradeBinding(keyPath: \\.gain.blue)"))
        #expect(source.contains("updateSelectedColorGrade(clamped)"))
        #expect(source.contains("updateSelectedColorGrade(nil)"))
    }
}
