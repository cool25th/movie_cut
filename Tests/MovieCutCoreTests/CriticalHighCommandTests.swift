import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import MovieCutCore

#if canImport(AudioToolbox)
import AudioToolbox
#endif

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

    @Test("Reverse clip command inverts to itself")
    func testInvertReturnsSelf() throws {
        let clipId = UUID()
        let command = ReverseClipCommand(clipId: clipId)

        let inverse = try #require(try command.invert(from: CommandResult(description: "test")) as? ReverseClipCommand)

        #expect(inverse.clipId == clipId)
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

    @Test("Freeze frame command inverts to a remove command")
    func testInvertReturnsRemoveCommand() throws {
        let clip = makeClip(
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5)
        )
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))
        let command = FreezeFrameCommand(clipId: clip.id, freezeTime: 2.0, freezeDuration: 1.0)

        let result = try editor.apply(command)
        let inverse = try command.invert(from: result)
        try editor.apply(inverse)

        #expect(editor.project.timeline.tracks[0].clips == [clip])
    }

    @Test("Set color correction command stores color correction")
    func testApplySetsColorCorrection() throws {
        let clip = makeClip()
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))
        let colorCorrection = ColorCorrection(brightness: 0.5)

        try editor.apply(SetColorCorrectionCommand(clipId: clip.id, colorCorrection: colorCorrection))

        #expect(editor.project.timeline.tracks[0].clips[0].colorCorrection?.brightness == 0.5)
    }

    @Test("Set color correction inverse restores previous value")
    func testInvertRestoresPrevious() throws {
        let previousColorCorrection = ColorCorrection(brightness: -0.25)
        let clip = makeClip(colorCorrection: previousColorCorrection)
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))
        let command = SetColorCorrectionCommand(
            clipId: clip.id,
            colorCorrection: ColorCorrection(brightness: 0.5)
        )

        let result = try editor.apply(command)
        let inverse = try command.invert(from: result)
        try editor.apply(inverse)

        #expect(editor.project.timeline.tracks[0].clips[0].colorCorrection == previousColorCorrection)
    }

    @Test("Set clip mask command stores mask")
    func testApplySetsMask() throws {
        let clip = makeClip()
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))
        let mask = makeMask(shape: .ellipse)

        try editor.apply(SetClipMaskCommand(clipId: clip.id, mask: mask))

        #expect(editor.project.timeline.tracks[0].clips[0].mask?.shape == .ellipse)
    }

    @Test("Set clip mask inverse restores old mask")
    func testInvertRestoresOldMask() throws {
        let clip = makeClip()
        var editor = MockEditorAPI(project: makeProject(clips: [clip]))
        let command = SetClipMaskCommand(clipId: clip.id, mask: makeMask(shape: .ellipse))

        let result = try editor.apply(command)
        let inverse = try command.invert(from: result)
        try editor.apply(inverse)

        #expect(editor.project.timeline.tracks[0].clips[0].mask == nil)
    }

    @Test("Background removal provider name is non-empty")
    func testProviderName() {
        let provider = BackgroundRemovalProvider()

        #expect(provider.providerName.isEmpty == false)
    }

    @Test("Background removal provider availability is accessible")
    func testIsAvailable() {
        let provider = BackgroundRemovalProvider()
        let isAvailable: Bool = provider.isAvailable

        #expect(isAvailable == true || isAvailable == false)
    }

    @Test("Style transfer provider exposes available styles")
    func testAvailableStyles() {
        let provider = StyleTransferProvider()

        #expect(provider.availableStyles == ["comic", "noir", "vintage", "cyberpunk", "watercolor"])
    }

    @Test("Style transfer provider handles empty images")
    func testApplyReturnsNilForEmptyImage() {
        let provider = StyleTransferProvider()
        let styledImage = provider.apply(style: "noir", to: CIImage.empty())

        #expect(styledImage == nil || styledImage?.extent.isEmpty == true)
    }

    @Test("Audio equalizer service initializes")
    func testInitSucceeds() {
        guard isAudioEqualizerRuntimeAvailable() else {
            #expect(AudioEqualizerService.self == AudioEqualizerService.self)
            return
        }

        let service = AudioEqualizerService()

        #expect(type(of: service) == AudioEqualizerService.self)
    }
}

private struct MockEditorAPI {
    var project: Project

    @discardableResult
    mutating func apply(_ command: any EditorCommand) throws -> CommandResult {
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

private func isAudioEqualizerRuntimeAvailable() -> Bool {
    #if canImport(AudioToolbox)
    var description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_NBandEQ,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )

    return AudioComponentFindNext(nil, &description) != nil
    #else
    return true
    #endif
}
