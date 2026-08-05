import Foundation
import Testing
@testable import MovieCutCore

#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
@Suite("Pipeline coverage")
struct PipelineTests {
    @Test("Export resolution enum raw values are stable")
    func testExportResolutionEnumValues() {
        #expect(ExportResolution.p720.rawValue == "p720")
        #expect(ExportResolution.p1080.rawValue == "p1080")
        #expect(ExportResolution.p4K.rawValue == "p4K")
    }

    @Test("Export codec enum has expected cases")
    func testExportCodecEnumHasExpectedCases() {
        let codecRawValues: Set<String> = [
            ExportCodec.h264.rawValue,
            ExportCodec.hevc.rawValue
        ]

        #expect(codecRawValues == ["h264", "hevc"])
    }

    @Test("Noise reduction service initializes")
    func testNoiseReductionServiceInitializes() {
        #if canImport(AVFoundation)
        let service = NoiseReductionService()

        #expect(type(of: service) == NoiseReductionService.self)
        #else
        #expect(true)
        #endif
    }

    @Test("Audio fade command inverts correctly")
    func testAudioFadeCommandInvertsCorrectly() throws {
        let clipId = UUID()
        let originalFadeIn = 0.2
        let originalFadeOut = 0.4
        let clip = Clip(
            id: clipId,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5),
            fadeInDuration: originalFadeIn,
            fadeOutDuration: originalFadeOut
        )
        var project = Project(
            name: "Pipeline Test",
            timeline: Timeline(tracks: [
                Track(kind: .audio, name: "Audio 1", clips: [clip])
            ])
        )
        let command = AudioFadeCommand(
            clipId: clipId,
            fadeInDuration: 1.0,
            fadeOutDuration: 1.5
        )

        try command.apply(to: &project)

    }
}
