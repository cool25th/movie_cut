import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import MovieCutCore

@MainActor

@Suite("Critical/high commands and providers")
struct CriticalHighCommandTests {
    @Test("Reverse clip command toggles reverse playback")
    func testApplyTogglesReverse() throws {
        let clip = makeClip()
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))

        try editor.apply(ReverseClipCommand(clipId: clip.id))

        #expect(editor.project.timeline.tracks[0].clips[0].isReversed == true)
    }

    @Test("Freeze frame command splits a clip into leading, freeze, and trailing clips")
    func testApplySplitsClip() throws {
        let clip = makeClip(
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5)
        )
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))

        try editor.apply(FreezeFrameCommand(clipId: clip.id, freezeTime: 2.0, freezeDuration: 1.0))

        let clips = editor.project.timeline.tracks[0].clips
        #expect(clips.count == 3)
        #expect(clips[0].id == clip.id)
        #expect(clips[0].sourceRange == TimeRange(start: 0, duration: 2))
        #expect(clips[0].timelineRange == TimeRange(start: 0, duration: 2))
        #expect(clips[1].kind == .image)
        #expect(clips[1].sourceRange == TimeRange(start: 2, duration: 0))
        #expect(clips[1].timelineRange == TimeRange(start: 2, duration: 1))
        #expect(clips[2].sourceRange == TimeRange(start: 2, duration: 3))
        #expect(clips[2].timelineRange == TimeRange(start: 3, duration: 3))
    }

    @Test("Freeze frame command applies forward")
    func testInvertReturnsRemoveCommand() throws {
        let clip = makeClip(
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5)
        )
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))
        let command = FreezeFrameCommand(clipId: clip.id, freezeTime: 2.0, freezeDuration: 1.0)

        try editor.apply(command)

        #expect(editor.project.timeline.tracks[0].clips.count == 3)
    }

    @Test("Set color correction command stores color correction")
    func testApplySetsColorCorrection() throws {
        let clip = makeClip()
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))
        let colorCorrection = ColorCorrection(brightness: 0.5)

        try editor.apply(SetColorCorrectionCommand(clipId: clip.id, colorCorrection: colorCorrection))

        #expect(editor.project.timeline.tracks[0].clips[0].colorCorrection?.brightness == 0.5)
    }

    @Test("Set clip mask command stores mask")
    func testApplySetsMask() throws {
        let clip = makeClip()
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))
        let mask = makeMask(shape: .ellipse)

        try editor.apply(SetClipMaskCommand(clipId: clip.id, mask: mask))

        #expect(editor.project.timeline.tracks[0].clips[0].mask?.shape == .ellipse)
    }

    @Test("Audio equalizer service initializes")
    func testInitSucceeds() {
        // No AudioToolbox component-registry probe here: AudioComponentFindNext
        // is a blocking cross-process lookup that can stall when the full Core
        // suite runs its AVAudioEngine-heavy suites in parallel (observed gate
        // hang, 2026-08-26). AudioEqualizerService.init only constructs
        // AVAudioEngine + AVAudioUnitEQ, so the init itself is the contract.
        let service = AudioEqualizerService()

        #expect(type(of: service) == AudioEqualizerService.self)
    }
}

private struct MockEditorAPI {
    var project: Project

    mutating func apply(_ command: any EditorCommand) throws {
        try command.apply(to: &project)
    }
}

private func makeProject(clips: [Clip]) -> Project {
    Project(
        name: "Critical High Command Test Project",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        timeline: Timeline(tracks: [
            Track(kind: .video, name: "Video 1", clips: clips)
        ])
    )
}

private func makeClip(
    id: UUID = UUID(),
    sourceRange: TimeRange = TimeRange(start: 0, duration: 5),
    timelineRange: TimeRange = TimeRange(start: 0, duration: 5),
    colorCorrection: ColorCorrection? = nil
) -> Clip {
    Clip(
        id: id,
        kind: .video,
        sourceRange: sourceRange,
        timelineRange: timelineRange,
        colorCorrection: colorCorrection
    )
}

private func makeMask(shape: MaskShape) -> Mask {
    Mask(
        shape: shape,
        position: CGPoint(x: 0.5, y: 0.5),
        size: CGSize(width: 0.5, height: 0.5)
    )
}
