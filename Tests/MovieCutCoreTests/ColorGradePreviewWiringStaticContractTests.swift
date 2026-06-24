import Foundation
import Testing

/// Regression lock for the color-grade preview wiring (Phase 2A increment 3).
/// Preview shares `CustomVideoCompositor` with export (whose grade application is
/// proven by `run_e2e_export.sh`), so this only guards that `PlaybackEngine`
/// threads `clip.colorGrade` into the composition and triggers the custom
/// compositor for grade-only clips.
@Suite("Color Grade Preview Wiring Static Contract")
struct ColorGradePreviewWiringStaticContractTests {
    private func playback() throws -> String {
        try String(contentsOfFile: "App/MovieCutMac/Playback/PlaybackEngine.swift", encoding: .utf8)
    }

    @Test("preview threads the clip color grade into its composition")
    func threadsGrade() throws {
        let source = try playback()
        #expect(source.contains("colorGrade: clip.colorGrade"))
        #expect(source.contains("colorGrade: clipInstruction.colorGrade"))
    }

    @Test("a grade-only clip routes preview through the custom compositor")
    func gradeTriggersCustomCompositor() throws {
        let source = try playback()
        #expect(source.contains("clipInstruction.colorGrade != nil"))
        #expect(source.contains("mutableVideoComposition.customVideoCompositorClass = CustomVideoCompositor.self"))
    }
}
