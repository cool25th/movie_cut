import Foundation
import Testing
@testable import MovieCutCore

@Suite("Project models")
struct ProjectModelTests {
    @Test("Project creation uses default values")
    func projectCreationDefaults() {
        let project = Project(name: "Untitled")

        #expect(project.name == "Untitled")
        #expect(project.schemaVersion == currentSchemaVersion)
        #expect(project.appVersion == "0.1.0")
        #expect(project.mediaLibrary.assets.isEmpty)
        #expect(project.timeline.frameRate == Rational(numerator: 30, denominator: 1))
        #expect(project.markers.isEmpty)
        #expect(project.exportSettings.resolution == .p1080)
    }

    @Test("Timeline tracks can be added and removed")
    func timelineTrackAddRemove() {
        var timeline = Timeline()
        let videoTrack = Track(kind: .video, name: "Video 1", zIndex: 1)

        timeline.tracks.append(videoTrack)
        #expect(timeline.tracks.count == 1)
        #expect(timeline.tracks.first == videoTrack)

        timeline.tracks.removeAll { $0.id == videoTrack.id }
        #expect(timeline.tracks.isEmpty)
    }

    @Test("Clip stores source and timeline ranges")
    func clipSourceAndTimelineRanges() {
        let clip = Clip(
            assetId: UUID(),
            kind: .video,
            sourceRange: TimeRange(start: 2, duration: 5),
            timelineRange: TimeRange(start: 10, duration: 5)
        )

        #expect(clip.sourceRange.start == 2)
        #expect(clip.sourceRange.duration == 5)
        #expect(clip.sourceRange.end == 7)
        #expect(clip.timelineRange.start == 10)
        #expect(clip.timelineRange.end == 15)
    }

    @Test("Project codable round trip preserves values")
    func codableRoundTrip() throws {
        let assetId = UUID()
        let clip = Clip(
            id: UUID(),
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 1, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4),
            transform: ClipTransform(
                position: CGPoint(x: 100, y: 200),
                offset: CGPoint(x: 10, y: 20),
                scale: CGSize(width: 1.2, height: 1.2),
                rotation: 15,
                anchorPoint: CGPoint(x: 0.5, y: 0.5)
            ),
            effects: [Effect(type: .brightness, parameters: ["amount": 0.2])]
        )
        let track = Track(kind: .video, name: "Video 1", zIndex: 1, clips: [clip])
        let asset = MediaAsset(
            id: assetId,
            originalURL: URL(fileURLWithPath: "/tmp/example.mov"),
            kind: .video,
            duration: 4,
            metadata: MediaMetadata(width: 1920, height: 1080, frameRate: 30, codec: "h264")
        )
        let project = Project(
            id: UUID(),
            name: "Round Trip",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(tracks: [track]),
            markers: [Marker(time: 1.5, name: "Marker")],
            exportSettings: ExportSettings(resolution: .p4K, frameRate: .fps60, codec: .hevc, audioCodec: .aac)
        )

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: encoded)

        #expect(decoded == project)
    }

    @Test("EditorSession dispatch supports undo and redo")
    func editorSessionDispatchUndoRedo() async throws {
        let session = EditorSession(project: Project(name: "Session Test"))
        let track = Track(kind: .video, name: "Video 1")

        try await session.dispatch(CreateTrackCommand(track: track))
        var snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks.map(\.id) == [track.id])

        try await session.undo()
        snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks.isEmpty)

        try await session.redo()
        snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks.map(\.id) == [track.id])
    }
}
