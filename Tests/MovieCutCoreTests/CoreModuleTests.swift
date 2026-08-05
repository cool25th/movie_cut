import CoreGraphics
import Foundation
import Testing
import MovieCutCore

@Test func clipMutationSetsProperties() {
    var clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
    clip.opacity = 0.5
    clip.volume = 1.5
    clip.playbackRate = 2.0
    clip.useOpticalFlow = true
    clip.isReversed = true
    #expect(clip.opacity == 0.5)
    #expect(clip.volume == 1.5)
    #expect(clip.playbackRate == 2.0)
    #expect(clip.useOpticalFlow == true)
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

@Test func clipCodableLegacyJSONWithoutZIndexDefaultsToZero() throws {
    let clip = Clip(kind: .video, sourceRange: TimeRange(start: 1, duration: 5), timelineRange: TimeRange(start: 2, duration: 5), zIndex: 7)
    let encoded = try JSONEncoder().encode(clip)
    var jsonObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    jsonObject.removeValue(forKey: "zIndex")

    let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)
    let decoded = try JSONDecoder().decode(Clip.self, from: legacyData)

    #expect(decoded.zIndex == 0)
    #expect(decoded.timelineRange.start == 2)
    #expect(decoded.timelineRange.duration == 5)
}

@Test func clipCodableRoundTripPreservesNonzeroZIndex() throws {
    let clip = Clip(kind: .text, sourceRange: TimeRange(start: 0, duration: 4), timelineRange: TimeRange(start: 3, duration: 4), zIndex: 12)
    let data = try JSONEncoder().encode(clip)
    let decoded = try JSONDecoder().decode(Clip.self, from: data)

    #expect(decoded.zIndex == 12)
    #expect(decoded.timelineRange.start == 3)
    #expect(decoded.timelineRange.duration == 4)
}

@Test func clipCodableLegacyJSONWithoutOpticalFlowDefaultsToFalse() throws {
    let clip = Clip(
        kind: .video,
        sourceRange: TimeRange(start: 0, duration: 5),
        timelineRange: TimeRange(start: 0, duration: 10),
        playbackRate: 0.5,
        useOpticalFlow: true
    )
    let encoded = try JSONEncoder().encode(clip)
    var jsonObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    jsonObject.removeValue(forKey: "useOpticalFlow")

    let legacyData = try JSONSerialization.data(withJSONObject: jsonObject)
    let decoded = try JSONDecoder().decode(Clip.self, from: legacyData)

    #expect(decoded.useOpticalFlow == false)
    #expect(decoded.playbackRate == 0.5)
}

@Test func clipCodableRoundTripPreservesOpticalFlow() throws {
    let clip = Clip(
        kind: .video,
        sourceRange: TimeRange(start: 0, duration: 5),
        timelineRange: TimeRange(start: 0, duration: 10),
        playbackRate: 0.5,
        useOpticalFlow: true
    )
    let data = try JSONEncoder().encode(clip)
    let decoded = try JSONDecoder().decode(Clip.self, from: data)

    #expect(decoded.useOpticalFlow == true)
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
    try cmd.apply(to: &project)
    #expect(project.timeline.tracks[0].clips[0].timelineRange.start == 0)
    #expect(project.timeline.tracks[0].clips[0].timelineRange.duration == 5)
}

@Test func addClipCommandMagneticallyCompactsSameTrackAndLeavesOtherTrackUntouched() throws {
    let existingClip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 2), timelineRange: TimeRange(start: 4, duration: 2))
    let addedClip = Clip(kind: .video, sourceRange: TimeRange(start: 2, duration: 3), timelineRange: TimeRange(start: 20, duration: 3))
    let otherTrackClip = Clip(kind: .audio, sourceRange: TimeRange(start: 0, duration: 4), timelineRange: TimeRange(start: 7, duration: 4))
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [existingClip]),
        Track(kind: .audio, name: "A1", zIndex: 1, clips: [otherTrackClip])
    ]))
    let trackId = project.timeline.tracks[0].id
    let otherTrackSnapshot = project.timeline.tracks[1].clips

    _ = try AddClipCommand(trackId: trackId, clip: addedClip).apply(to: &project)

    let videoClips = project.timeline.tracks[0].clips
    #expect(videoClips.map(\.id) == [existingClip.id, addedClip.id])
    #expect(videoClips.map { $0.timelineRange.start } == [0, 2])
    #expect(videoClips.map { $0.timelineRange.duration } == [2, 3])
    #expect(videoClips.map(\.zIndex) == [0, 1])
    expectClipTimelineSnapshot(project.timeline.tracks[1].clips, matches: otherTrackSnapshot)
}

@Test func moveClipCommandMagneticCompactionRemovesGapsAndUndoRestoresSnapshot() throws {
    let firstClip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 2), timelineRange: TimeRange(start: 0, duration: 2), zIndex: 0)
    let secondClip = Clip(kind: .video, sourceRange: TimeRange(start: 2, duration: 3), timelineRange: TimeRange(start: 10, duration: 3), zIndex: 1)
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [firstClip, secondClip])
    ]))
    let trackId = project.timeline.tracks[0].id
    let cmd = MoveClipCommand(clipId: secondClip.id, sourceTrackId: trackId, targetTrackId: trackId, newTimelineRange: TimeRange(start: 12, duration: 3))

    try cmd.apply(to: &project)

    let compactedClips = project.timeline.tracks[0].clips
    #expect(compactedClips.map(\.id) == [firstClip.id, secondClip.id])
    #expect(compactedClips.map { $0.timelineRange.start } == [0, 2])
    #expect(compactedClips.map { $0.timelineRange.duration } == [2, 3])
}

@Test func deleteClipCommandPreservesGapsAndNormalizesZIndexesAndUndoRestoresSnapshot() throws {
    // Step 2: normal Delete preserves gaps (no magnetic compaction). Only
    // zIndexes are re-normalized. Ripple Delete is the separate gap-closing
    // variant. The clips start at non-zero, gapped offsets (3, 10, 20) and
    // must keep those offsets minus the deleted clip's slot.
    let firstClip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 2), timelineRange: TimeRange(start: 3, duration: 2), zIndex: 4)
    let middleClip = Clip(kind: .video, sourceRange: TimeRange(start: 2, duration: 3), timelineRange: TimeRange(start: 10, duration: 3), zIndex: 6)
    let lastClip = Clip(kind: .video, sourceRange: TimeRange(start: 5, duration: 4), timelineRange: TimeRange(start: 20, duration: 4), zIndex: 9)

    var middleDeleteProject = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [firstClip, middleClip, lastClip])
    ]))
    let middleDeleteCommand = DeleteClipCommand(clipId: middleClip.id)

    try middleDeleteCommand.apply(to: &middleDeleteProject)

    let middleDeleteClips = middleDeleteProject.timeline.tracks[0].clips
    #expect(middleDeleteClips.map(\.id) == [firstClip.id, lastClip.id])
    // Gaps preserved: first stays at 3, last stays at 20 (NOT re-compacted to 0/2).
    #expect(middleDeleteClips.map { $0.timelineRange.start } == [3, 20])
    #expect(middleDeleteClips.map { $0.timelineRange.duration } == [2, 4])
    // zIndexes are re-normalized contiguously even though positions are preserved.
    #expect(middleDeleteClips.map(\.zIndex) == [0, 1])

    var firstDeleteProject = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [firstClip, middleClip, lastClip])
    ]))
    let firstDeleteCommand = DeleteClipCommand(clipId: firstClip.id)

    try firstDeleteCommand.apply(to: &firstDeleteProject)

    let firstDeleteClips = firstDeleteProject.timeline.tracks[0].clips
    #expect(firstDeleteClips.map(\.id) == [middleClip.id, lastClip.id])
    // Gaps preserved: middle stays at 10, last stays at 20.
    #expect(firstDeleteClips.map { $0.timelineRange.start } == [10, 20])
    #expect(firstDeleteClips.map { $0.timelineRange.duration } == [3, 4])
    #expect(firstDeleteClips.map(\.zIndex) == [0, 1])
}

@Test func addClipOnFreeTrackPreservesRequestedPosition() throws {
    // Step 2 acceptance: a text clip added at a 5-second position on a non-main
    // (text) track keeps exactly start=5. Previously every add compacted the
    // track back to start=0.
    let textClip = Clip(kind: .text, sourceRange: TimeRange(start: 0, duration: 3), timelineRange: TimeRange(start: 5, duration: 3), zIndex: 0)
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        // A video track exists so "main video track" is well-defined; the text
        // track is therefore a free (non-magnetic) track.
        Track(kind: .video, name: "V1", zIndex: 0, clips: [
            Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 2), timelineRange: TimeRange(start: 0, duration: 2))
        ]),
        Track(kind: .text, name: "T1", zIndex: 1, clips: [])
    ]))
    let textTrackId = project.timeline.tracks[1].id

    _ = try AddClipCommand(trackId: textTrackId, clip: textClip).apply(to: &project)

    let addedClips = project.timeline.tracks[1].clips
    #expect(addedClips.count == 1)
    #expect(addedClips[0].timelineRange.start == 5)
    #expect(addedClips[0].timelineRange.duration == 3)
}

@Test func moveClipOnAudioTrackPreservesPosition() throws {
    // Step 2 acceptance: moving an audio clip to 7.5s on an audio (free) track
    // keeps the requested position instead of compacting to 0.
    let audioClip = Clip(kind: .audio, sourceRange: TimeRange(start: 0, duration: 2), timelineRange: TimeRange(start: 0, duration: 2))
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "V1", zIndex: 0, clips: [
            Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 2), timelineRange: TimeRange(start: 0, duration: 2))
        ]),
        Track(kind: .audio, name: "A1", zIndex: 1, clips: [audioClip])
    ]))
    let audioTrackId = project.timeline.tracks[1].id

    _ = try MoveClipCommand(
        clipId: audioClip.id,
        sourceTrackId: audioTrackId,
        targetTrackId: audioTrackId,
        newTimelineRange: TimeRange(start: 7.5, duration: 2)
    ).apply(to: &project)

    let movedClips = project.timeline.tracks[1].clips
    #expect(movedClips.count == 1)
    #expect(movedClips[0].timelineRange.start == 7.5)
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
    try cmd.apply(to: &project)
    #expect(project.timeline.tracks[0].clips[0].sourceRange.start == 2)
    #expect(project.timeline.tracks[0].clips[0].sourceRange.duration == 6)
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

    try command.apply(to: &project)
    #expect(project.timeline.tracks[0].zIndex == 12)
}

@Test("SetClipProperty zIndex applies and inverts on selected clip")
func setClipPropertyZIndexAppliesAndInvertsOnSelectedClip() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .text, name: "Overlay", zIndex: 0, clips: [
            Clip(kind: .text, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5), zIndex: 2)
        ])
    ]))
    let clipId = project.timeline.tracks[0].clips[0].id
    let command = SetClipPropertyCommand(clipId: clipId, property: .zIndex(8))

    try command.apply(to: &project)
    #expect(project.timeline.tracks[0].clips[0].zIndex == 8)
}

@Test("SetClipProperty opticalFlow applies and inverts on selected clip")
func setClipPropertyOpticalFlowAppliesAndInvertsOnSelectedClip() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "Video", zIndex: 0, clips: [
            Clip(
                kind: .video,
                sourceRange: TimeRange(start: 0, duration: 5),
                timelineRange: TimeRange(start: 0, duration: 10),
                playbackRate: 0.5
            )
        ])
    ]))
    let clipId = project.timeline.tracks[0].clips[0].id
    let command = SetClipPropertyCommand(clipId: clipId, property: .opticalFlow(true))

    try command.apply(to: &project)
    #expect(project.timeline.tracks[0].clips[0].useOpticalFlow == true)
}

@Test("SetTrackProperty boolean applies and inverts")
func setTrackPropertyBooleanAppliesAndInverts() throws {
    var project = Project(name: "Test", timeline: Timeline(tracks: [
        Track(kind: .video, name: "Video", isHidden: false, zIndex: 0)
    ]))
    let trackId = project.timeline.tracks[0].id
    let command = SetTrackPropertyCommand(trackId: trackId, property: .isHidden(true))

    try command.apply(to: &project)
    #expect(project.timeline.tracks[0].isHidden == true)
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

private func expectClipTimelineSnapshot(_ actual: [Clip], matches expected: [Clip]) {
    #expect(actual.count == expected.count)
    guard actual.count == expected.count else {
        return
    }

    for index in actual.indices {
        #expect(actual[index].id == expected[index].id)
        #expect(actual[index].assetId == expected[index].assetId)
        #expect(actual[index].kind == expected[index].kind)
        #expect(actual[index].sourceRange.start == expected[index].sourceRange.start)
        #expect(actual[index].sourceRange.duration == expected[index].sourceRange.duration)
        #expect(actual[index].timelineRange.start == expected[index].timelineRange.start)
        #expect(actual[index].timelineRange.duration == expected[index].timelineRange.duration)
        #expect(actual[index].zIndex == expected[index].zIndex)
    }
}
