import CoreGraphics
import Foundation
import Testing
import MovieCutCore

@Test func clipMutationSetsProperties() {
    var clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
    clip.opacity = 0.5
    clip.volume = 1.5
    clip.playbackRate = 2.0
    clip.isReversed = true
    #expect(clip.opacity == 0.5)
    #expect(clip.volume == 1.5)
    #expect(clip.playbackRate == 2.0)
    #expect(clip.isReversed == true)
}

@Test func clipColorCorrectionRoundTrip() {
    var clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
    let correction = ColorCorrection(brightness: 0.2, contrast: 1.3, saturation: 0.8, warmth: 0.1, tint: -0.1)
    clip.colorCorrection = correction
    #expect(clip.colorCorrection?.brightness == 0.2)
    #expect(clip.colorCorrection?.contrast == 1.3)
}

@Test func clipMaskRoundTrip() {
    var clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
    let mask = Mask(
        shape: .rectangle,
        position: CGPoint(x: 0, y: 0),
        size: CGSize(width: 1, height: 1),
        feather: 10,
        inverted: true
    )
    clip.mask = mask
    #expect(clip.mask?.shape == .rectangle)
    #expect(clip.mask?.feather == 10)
    #expect(clip.mask?.inverted == true)
}

@Test func clipTransitionRoundTrip() {
    var clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
    let transition = Transition(type: .crossDissolve, duration: 0.5)
    clip.transition = transition
    #expect(clip.transition?.type == .crossDissolve)
    #expect(clip.transition?.duration == 0.5)
}

@Test func timelineDurationCalculation() {
    let track1 = Track(kind: .video, name: "V1", zIndex: 0, clips: [
        Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5)),
        Clip(kind: .video, sourceRange: TimeRange(start: 5, duration: 3), timelineRange: TimeRange(start: 5, duration: 3))
    ])
    let track2 = Track(kind: .audio, name: "A1", zIndex: 1, clips: [
        Clip(kind: .audio, sourceRange: TimeRange(start: 0, duration: 10), timelineRange: TimeRange(start: 0, duration: 10))
    ])
    let timeline = Timeline(tracks: [track1, track2])
    #expect(timeline.duration == 10.0)
}

@Test func emptyTimelineDurationIsZero() {
    let timeline = Timeline(tracks: [])
    #expect(timeline.duration == 0)
}

@Test func projectEncodeDecodeRoundTrip() throws {
    let project = Project(name: "Test", timeline: Timeline(tracks: [Track(kind: .video, name: "V1", zIndex: 0)]))
    let data = try JSONEncoder().encode(project)
    let decoded = try JSONDecoder().decode(Project.self, from: data)
    #expect(decoded.name == "Test")
    #expect(decoded.timeline.tracks.count == 1)
    #expect(decoded.id == project.id)
}

@Test func moveClipCommandAppliesAndInverts() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [
            Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
        ])
    ]))
    let clipId = project.timeline.tracks[0].clips[0].id
    let trackId = project.timeline.tracks[0].id
    let cmd = MoveClipCommand(clipId: clipId, sourceTrackId: trackId, targetTrackId: trackId, newTimelineRange: TimeRange(start: 3, duration: 5))
    let result: CommandResult = try cmd.apply(to: &project)
    #expect(project.timeline.tracks[0].clips[0].timelineRange.start == 3)
    let undo = try cmd.invert(from: result)
    _ = try undo.apply(to: &project)
    #expect(project.timeline.tracks[0].clips[0].timelineRange.start == 0)
}

@Test func trimClipCommandAppliesAndInverts() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [
            Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 10), timelineRange: TimeRange(start: 0, duration: 10))
        ])
    ]))
    let clipId = project.timeline.tracks[0].clips[0].id
    let trackId = project.timeline.tracks[0].id
    let cmd = TrimClipCommand(clipId: clipId, trackId: trackId, newSourceRange: TimeRange(start: 2, duration: 6), newTimelineRange: TimeRange(start: 2, duration: 6))
    let result: CommandResult = try cmd.apply(to: &project)
    #expect(project.timeline.tracks[0].clips[0].sourceRange.start == 2)
    #expect(project.timeline.tracks[0].clips[0].sourceRange.duration == 6)
    let undo = try cmd.invert(from: result)
    _ = try undo.apply(to: &project)
    #expect(project.timeline.tracks[0].clips[0].sourceRange.start == 0)
    #expect(project.timeline.tracks[0].clips[0].sourceRange.duration == 10)
}

@Test func copyClipCommandCreatesDuplicate() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [
            Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
        ])
    ]))
    let clipId = project.timeline.tracks[0].clips[0].id
    let trackId = project.timeline.tracks[0].id
    let cmd = CopyClipCommand(clipId: clipId, targetTrackId: trackId, targetStartTime: 5)
    _ = try cmd.apply(to: &project)
    #expect(project.timeline.tracks[0].clips.count == 2)
    #expect(project.timeline.tracks[0].clips[1].timelineRange.start == 5)
}

@Test func rippleDeleteCommandRemovesClipAndCloses() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [
            Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5)),
            Clip(kind: .video, sourceRange: TimeRange(start: 5, duration: 5), timelineRange: TimeRange(start: 5, duration: 5))
        ])
    ]))
    let clipId = project.timeline.tracks[0].clips[0].id
    let cmd = RippleDeleteCommand(clipId: clipId)
    _ = try cmd.apply(to: &project)
    #expect(project.timeline.tracks[0].clips.count == 1)
    #expect(project.timeline.tracks[0].clips[0].timelineRange.start == 0)
}

@Test func duplicateClipCommandCreatesCopy() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [
            Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
        ])
    ]))
    let clipId = project.timeline.tracks[0].clips[0].id
    let cmd = DuplicateClipCommand(clipId: clipId)
    _ = try cmd.apply(to: &project)
    #expect(project.timeline.tracks[0].clips.count == 2)
}

@Test func editorSessionUndoRedoChain() async throws {
    let project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0)
    ]))
    let session = EditorSession(project: project)
    let trackId = project.timeline.tracks[0].id
    let asset = MediaAsset(originalURL: URL(fileURLWithPath: "/test.mp4"), kind: .video)

    try await session.dispatch(ImportMediaCommand(asset: asset))
    let clip = Clip(assetId: asset.id, kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
    try await session.dispatch(AddClipCommand(trackId: trackId, clip: clip))
    var snapshot = await session.snapshot()
    #expect(snapshot.timeline.tracks[0].clips.count == 1)

    try await session.undo()
    snapshot = await session.snapshot()
    #expect(snapshot.timeline.tracks[0].clips.count == 0)

    try await session.redo()
    snapshot = await session.snapshot()
    #expect(snapshot.timeline.tracks[0].clips.count == 1)
}

@Test func trackPropertiesMutate() {
    var track = Track(kind: .video, name: "V1", zIndex: 0)
    track.isMuted = true
    track.isLocked = true
    track.isHidden = true
    track.name = "Renamed"
    #expect(track.isMuted == true)
    #expect(track.isLocked == true)
    #expect(track.isHidden == true)
    #expect(track.name == "Renamed")
}

@Test("SetTrackProperty zIndex applies and inverts")
func setTrackPropertyZIndexAppliesAndInverts() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .text, name: "Overlay", zIndex: 4)
    ]))
    let trackId = project.timeline.tracks[0].id
    let command = SetTrackPropertyCommand(trackId: trackId, property: .zIndex(12))

    let result = try command.apply(to: &project)
    #expect(project.timeline.tracks[0].zIndex == 12)

    let undo = try command.invert(from: result)
    _ = try undo.apply(to: &project)
    #expect(project.timeline.tracks[0].zIndex == 4)
}

@Test("SetTrackProperty boolean applies and inverts")
func setTrackPropertyBooleanAppliesAndInverts() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "Video", isHidden: false, zIndex: 0)
    ]))
    let trackId = project.timeline.tracks[0].id
    let command = SetTrackPropertyCommand(trackId: trackId, property: .isHidden(true))

    let result = try command.apply(to: &project)
    #expect(project.timeline.tracks[0].isHidden == true)

    let undo = try command.invert(from: result)
    _ = try undo.apply(to: &project)
    #expect(project.timeline.tracks[0].isHidden == false)
}

@Test func clipTextContentRoundTrip() {
    var clip = Clip(kind: .text, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
    let content = TextClipContent(text: "Hello", fontFamily: "Helvetica", fontSize: 24, fontColor: "#FFFFFF")
    clip.textContent = content
    #expect(clip.textContent?.text == "Hello")
    #expect(clip.textContent?.fontSize == 24)
}

@Test func clipEffectsRoundTrip() {
    var clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
    let effect = Effect(id: UUID(), type: .blur, parameters: ["radius": 5.0])
    clip.effects = [effect]
    #expect(clip.effects.count == 1)
    #expect(clip.effects[0].type == .blur)
}

@Test func clipKeyframesRoundTrip() {
    var clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
    let kf = Keyframe(property: .positionX, time: 1.0, value: 100)
    clip.transform = ClipTransform(position: CGPoint(x: 100, y: 200))
    clip.keyframes = [kf]
    #expect(clip.keyframes.count == 1)
    #expect(clip.keyframes[0].time == 1.0)
    #expect(clip.transform.position.x == 100)
    #expect(clip.transform.position.y == 200)
}

@Test func projectMarkersRoundTrip() {
    var project = Project(name: "Test", timeline: Timeline(tracks: []))
    let marker = Marker(id: UUID(), time: 5.0, name: "Chapter 1", color: "red")
    project.markers = [marker]
    #expect(project.markers.count == 1)
    #expect(project.markers[0].time == 5.0)
}
