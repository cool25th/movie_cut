import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

@Suite("Clipboard commands")
struct ClipboardCommandTests {
    @Test("PasteClips anchors earliest clip and preserves relative offsets with new IDs")
    func pasteClipsPreservesOffsets() throws {
        let first = clip(start: 2, duration: 3)
        let second = clip(start: 7, duration: 2)
        let track = Track(kind: .video, name: "Video 1", clips: [first, second])
        let payload = try ClipboardPayload(
            project: project(tracks: [track]),
            clipIds: [first.id, second.id]
        )
        var destination = project(tracks: [Track(id: track.id, kind: .video, name: "Video 1")])

        _ = try PasteClipsCommand(payload: payload, anchorTime: 10).apply(to: &destination)

        let pasted = destination.timeline.tracks[0].clips.sorted { $0.timelineRange.start < $1.timelineRange.start }
        #expect(pasted.map(\.timelineRange.start) == [10, 15])
        #expect(pasted.map(\.timelineRange.duration) == [3, 2])
        #expect(Set(pasted.map(\.id)).isDisjoint(with: [first.id, second.id]))
    }

    @Test("PasteClips avoids occupied original track without modifying existing clips")
    func pasteClipsUsesNonoverlappingCompatibleTrack() throws {
        let sourceClip = clip(start: 0, duration: 4)
        let sourceTrack = Track(kind: .video, name: "Video 1", clips: [sourceClip])
        let payload = try ClipboardPayload(project: project(tracks: [sourceTrack]), clipIds: [sourceClip.id])
        let blocker = clip(start: 10, duration: 4)
        let original = Track(id: sourceTrack.id, kind: .video, name: "Video 1", clips: [blocker])
        let alternate = Track(kind: .video, name: "Video 2")
        var destination = project(tracks: [original, alternate])

        _ = try PasteClipsCommand(payload: payload, anchorTime: 10).apply(to: &destination)

        #expect(destination.timeline.tracks[0].clips == [blocker])
        #expect(destination.timeline.tracks[1].clips.count == 1)
        #expect(destination.timeline.tracks[1].clips[0].timelineRange == TimeRange(start: 10, duration: 4))
    }

    @Test("PasteClips is one undo and redo step")
    func pasteClipsUndoRedoRestoresExactProjects() async throws {
        let sourceClip = clip(start: 1, duration: 2)
        let track = Track(kind: .video, name: "Video 1", clips: [sourceClip])
        let initial = project(tracks: [track])
        let payload = try ClipboardPayload(project: initial, clipIds: [sourceClip.id])
        let session = EditorSession(project: initial)

        try await session.dispatch(PasteClipsCommand(payload: payload, anchorTime: 8))
        let pastedState = await session.snapshot()
        #expect(pastedState.timeline.tracks.flatMap(\.clips).count == 2)

        try await session.undo()
        #expect(await session.snapshot() == initial)

        try await session.redo()
        #expect(await session.snapshot() == pastedState)
    }

    @Test("PasteClips remaps selected groups without linking pasted clips to originals")
    func pasteClipsRemapsGroupIds() throws {
        let oldGroupId = UUID()
        var first = clip(start: 0, duration: 1)
        var second = clip(start: 2, duration: 1)
        var unselected = clip(start: 4, duration: 1)
        let ungrouped = clip(start: 6, duration: 1)
        first.groupId = oldGroupId
        second.groupId = oldGroupId
        unselected.groupId = oldGroupId
        let track = Track(kind: .video, name: "Video 1", clips: [first, second, unselected, ungrouped])
        var destination = project(tracks: [track])
        let originalIds = Set([first.id, second.id, unselected.id, ungrouped.id])
        let groupedPayload = try ClipboardPayload(
            project: destination,
            clipIds: [first.id, second.id]
        )

        try PasteClipsCommand(
            payload: groupedPayload,
            anchorTime: 10
        ).apply(to: &destination)

        let clips = destination.timeline.tracks.flatMap(\.clips)
        // Pasted copies carry new ids, so they are the ones not in the original set.
        let pastedGrouped = clips.filter { !originalIds.contains($0.id) }
        #expect(clips.first { $0.id == first.id }?.groupId == oldGroupId)
        #expect(clips.first { $0.id == second.id }?.groupId == oldGroupId)
        #expect(clips.first { $0.id == unselected.id }?.groupId == oldGroupId)
        #expect(pastedGrouped.count == 2)
        let pastedGroupId = try #require(pastedGrouped.first?.groupId)
        #expect(pastedGroupId != oldGroupId)
        #expect(pastedGrouped.allSatisfy { $0.groupId == pastedGroupId })

        let ungroupedPayload = try ClipboardPayload(
            project: destination,
            clipIds: [ungrouped.id]
        )
        let idsAfterFirstPaste = Set(clips.map(\.id))
        try PasteClipsCommand(
            payload: ungroupedPayload,
            anchorTime: 20
        ).apply(to: &destination)
        let pastedUngrouped = try #require(
            destination.timeline.tracks
                .flatMap(\.clips)
                .first { !idsAfterFirstPaste.contains($0.id) }
        )
        #expect(pastedUngrouped.groupId == nil)
    }

    @Test("CutClips removes clips across tracks and one undo restores exact values")
    func cutClipsAcrossTracksUndoExactly() async throws {
        let video = clip(start: 3, duration: 2)
        let audio = clip(kind: .audio, start: 6, duration: 5)
        let survivor = clip(start: 12, duration: 1)
        let initial = project(tracks: [
            Track(kind: .video, name: "Video 1", clips: [video, survivor]),
            Track(kind: .audio, name: "Audio 1", clips: [audio])
        ])
        let session = EditorSession(project: initial)

        try await session.dispatch(CutClipsCommand(clipIds: [video.id, audio.id]))
        let cutState = await session.snapshot()
        #expect(cutState.timeline.tracks[0].clips.map(\.id) == [survivor.id])
        #expect(cutState.timeline.tracks[0].clips[0].timelineRange.start == 12)
        #expect(cutState.timeline.tracks[1].clips.isEmpty)

        try await session.undo()
        #expect(await session.snapshot() == initial)
    }

    @Test("Clipboard payload owns full clip value snapshots")
    func clipboardPayloadPreservesFullClipValues() throws {
        let source = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 4, duration: 6),
            timelineRange: TimeRange(start: 2, duration: 6),
            transform: ClipTransform(
                position: CGPoint(x: 12, y: 34),
                scale: CGSize(width: 1.2, height: 0.8),
                rotation: 17
            ),
            opacity: 0.42,
            keyframes: [Keyframe(property: .opacity, time: 1, value: 0.7, interpolation: .easeInOut)],
            effects: [Effect(type: .blur, parameters: ["radius": 6])]
        )
        var sourceProject = project(tracks: [Track(kind: .video, name: "Video 1", clips: [source])])
        let payload = try ClipboardPayload(project: sourceProject, clipIds: [source.id])
        sourceProject.timeline.tracks[0].clips[0].opacity = 1
        var destination = project(tracks: [Track(
            id: sourceProject.timeline.tracks[0].id,
            kind: .video,
            name: "Video 1"
        )])

        _ = try PasteClipsCommand(payload: payload, anchorTime: 20).apply(to: &destination)

        let pasted = try #require(destination.timeline.tracks[0].clips.first)
        var expected = source
        expected.id = pasted.id
        expected.timelineRange = TimeRange(start: 20, duration: source.timelineRange.duration)
        expected.zIndex = pasted.zIndex
        #expect(pasted == expected)
    }

    private func clip(
        kind: ClipKind = .video,
        start: TimeInterval,
        duration: TimeInterval
    ) -> Clip {
        Clip(
            kind: kind,
            sourceRange: TimeRange(start: 0, duration: duration),
            timelineRange: TimeRange(start: start, duration: duration)
        )
    }

    private func project(tracks: [Track]) -> Project {
        Project(
            name: "Clipboard Tests",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            timeline: Timeline(tracks: tracks)
        )
    }
}
