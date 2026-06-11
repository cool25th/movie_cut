import Foundation
import Testing
@testable import MovieCutCore

/// Behavioral coverage for F-04 clip link groups: model persistence,
/// group/ungroup commands, undo, and validation.
@Suite("Clip Grouping")
struct ClipGroupingTests {
    @Test("legacy clip JSON without groupId decodes as ungrouped")
    func legacyClipDecodesUngrouped() throws {
        let clip = makeClip()
        var encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(clip)
        ) as! [String: Any]
        encoded.removeValue(forKey: "groupId")
        let legacyData = try JSONSerialization.data(withJSONObject: encoded)

        let decoded = try JSONDecoder().decode(Clip.self, from: legacyData)
        #expect(decoded.groupId == nil)
    }

    @Test("groupId round-trips through encode/decode")
    func groupIdRoundTrips() throws {
        let groupId = UUID()
        var clip = makeClip()
        clip.groupId = groupId

        let decoded = try JSONDecoder().decode(Clip.self, from: JSONEncoder().encode(clip))
        #expect(decoded.groupId == groupId)
    }

    @Test("group command links clips across tracks")
    func groupCommandLinksClips() async throws {
        let videoClip = makeClip()
        let audioClip = makeClip(kind: .audio)
        let videoTrack = Track(kind: .video, name: "V1", zIndex: 0, clips: [videoClip])
        let audioTrack = Track(kind: .audio, name: "A1", zIndex: 1, clips: [audioClip])
        let session = EditorSession(project: makeProject(tracks: [videoTrack, audioTrack]))

        let groupId = UUID()
        try await session.dispatch(
            GroupClipsCommand(clipIds: [videoClip.id, audioClip.id], groupId: groupId)
        )

        let snapshot = await session.snapshot()
        let groupIds = snapshot.timeline.tracks.flatMap(\.clips).map(\.groupId)
        #expect(groupIds == [groupId, groupId])
    }

    @Test("ungroup command clears membership and undo restores it")
    func ungroupAndUndoRestoresMembership() async throws {
        let first = makeClip()
        let second = makeClip(timelineRange: TimeRange(start: 4, duration: 4))
        let track = Track(kind: .video, name: "V1", zIndex: 0, clips: [first, second])
        let session = EditorSession(project: makeProject(tracks: [track]))

        let groupId = UUID()
        try await session.dispatch(
            GroupClipsCommand(clipIds: [first.id, second.id], groupId: groupId)
        )
        try await session.dispatch(
            GroupClipsCommand(clipIds: [first.id, second.id], groupId: nil)
        )

        var snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks[0].clips.allSatisfy { $0.groupId == nil })

        try await session.undo()
        snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks[0].clips.allSatisfy { $0.groupId == groupId })

        try await session.undo()
        snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks[0].clips.allSatisfy { $0.groupId == nil })
    }

    @Test("grouping a single clip is rejected")
    func groupingSingleClipRejected() async throws {
        let clip = makeClip()
        let track = Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
        let session = EditorSession(project: makeProject(tracks: [track]))

        await #expect(throws: EditorCommandError.self) {
            try await session.dispatch(
                GroupClipsCommand(clipIds: [clip.id], groupId: UUID())
            )
        }
    }

    @Test("grouping an unknown clip id is rejected")
    func groupingUnknownClipRejected() async throws {
        let clip = makeClip()
        let track = Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
        let session = EditorSession(project: makeProject(tracks: [track]))

        await #expect(throws: EditorCommandError.self) {
            try await session.dispatch(
                GroupClipsCommand(clipIds: [clip.id, UUID()], groupId: UUID())
            )
        }
    }

    @Test("invert regroups clips that had heterogeneous prior membership")
    func invertRestoresHeterogeneousMembership() throws {
        let previousGroup = UUID()
        var grouped = makeClip()
        grouped.groupId = previousGroup
        let ungrouped = makeClip(timelineRange: TimeRange(start: 4, duration: 4))
        var project = makeProject(tracks: [
            Track(kind: .video, name: "V1", zIndex: 0, clips: [grouped, ungrouped])
        ])

        let command = GroupClipsCommand(clipIds: [grouped.id, ungrouped.id], groupId: UUID())
        let result = try command.apply(to: &project)
        let inverse = try command.invert(from: result)
        _ = try inverse.apply(to: &project)

        let clips = project.timeline.tracks[0].clips
        #expect(clips.first { $0.id == grouped.id }?.groupId == previousGroup)
        #expect(clips.first { $0.id == ungrouped.id }?.groupId == nil)
    }

    // MARK: - Helpers

    private func makeProject(tracks: [Track]) -> Project {
        Project(
            id: UUID(),
            name: "Grouping Project",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            appVersion: "0.1.0",
            schemaVersion: 1,
            mediaLibrary: MediaLibrary(),
            timeline: Timeline(
                id: UUID(),
                frameRate: Rational(numerator: 30, denominator: 1),
                canvasSize: CGSize(width: 1920, height: 1080),
                aspectRatio: .landscape16x9,
                tracks: tracks,
                markers: []
            ),
            markers: [],
            canvas: CanvasPreset(aspectRatio: .landscape16x9, frameRate: .fps30),
            exportSettings: ExportSettings(resolution: .p1080, frameRate: .fps30, codec: .h264, audioCodec: .aac)
        )
    }

    private func makeClip(
        kind: ClipKind = .video,
        timelineRange: TimeRange = TimeRange(start: 0, duration: 4)
    ) -> Clip {
        Clip(
            kind: kind,
            sourceRange: TimeRange(start: 0, duration: timelineRange.duration),
            timelineRange: timelineRange
        )
    }
}
