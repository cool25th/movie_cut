import Foundation
import Testing
@testable import MovieCutCore

@Suite("Core feature verification")
struct CoreFeatureTests {
    @Test("Add clip command adds clip to track")
    func addClipCommandAddsClipToTrack() async throws {
        let track = makeTrack()
        let clip = makeClip()
        let session = EditorSession(project: makeProject(tracks: [track]))

        try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))

        let snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks.first?.clips == [clip])
    }

    @Test("Delete clip command removes clip")
    func deleteClipCommandRemovesClip() async throws {
        let track = makeTrack()
        let clip = makeClip()
        let session = EditorSession(project: makeProject(tracks: [track]))

        try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
        try await session.dispatch(DeleteClipCommand(clipId: clip.id))

        let snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks.first?.clips.isEmpty == true)
    }

    @Test("Split clip command creates two clips")
    func splitClipCommandCreatesTwoClips() async throws {
        let track = makeTrack()
        let clip = makeClip(
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10)
        )
        let trailingClipId = UUID()
        let session = EditorSession(project: makeProject(tracks: [track]))

        try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
        try await session.dispatch(SplitClipCommand(
            clipId: clip.id,
            trackId: track.id,
            splitTime: 5,
            newClipId: trailingClipId
        ))

        let clips = await session.snapshot().timeline.tracks[0].clips
        #expect(clips.count == 2)
        #expect(clips[0].id == clip.id)
        #expect(clips[0].sourceRange == TimeRange(start: 0, duration: 5))
        #expect(clips[0].timelineRange == TimeRange(start: 0, duration: 5))
        #expect(clips[1].id == trailingClipId)
        #expect(clips[1].sourceRange == TimeRange(start: 5, duration: 5))
        #expect(clips[1].timelineRange == TimeRange(start: 5, duration: 5))
    }

    @Test("Undo reverses last command")
    func undoReversesLastCommand() async throws {
        let track = makeTrack()
        let clip = makeClip()
        let session = EditorSession(project: makeProject(tracks: [track]))

        try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
        try await session.undo()

        let snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks.first?.clips.isEmpty == true)
    }

    @Test("Redo restores undone command")
    func redoRestoresUndoneCommand() async throws {
        let track = makeTrack()
        let clip = makeClip()
        let session = EditorSession(project: makeProject(tracks: [track]))

        try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
        try await session.undo()
        try await session.redo()

        let snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks.first?.clips == [clip])
    }

    @Test("Import media command adds asset")
    func importMediaCommandAddsAsset() async throws {
        let asset = makeAsset()
        let session = EditorSession(project: makeProject())

        try await session.dispatch(ImportMediaCommand(asset: asset))

        let snapshot = await session.snapshot()
        #expect(snapshot.mediaLibrary.assets[asset.id] == asset)
    }

    @Test("Project save and load round-trip preserves all data")
    func projectSaveAndLoadRoundTripPreservesAllData() async throws {
        let asset = makeAsset()
        let clip = makeClip(assetId: asset.id, effects: [
            Effect(type: .brightness, parameters: ["amount": 0.25])
        ])
        let tracks = [
            makeTrack(kind: .video, name: "Video 1", zIndex: 0, clips: [clip]),
            makeTrack(kind: .audio, name: "Audio 1", zIndex: 1)
        ]
        let project = makeProject(
            name: "Stored Project",
            mediaLibrary: MediaLibrary(assets: [asset.id: asset]),
            tracks: tracks,
            markers: [Marker(time: 3.5, name: "Beat", color: "#FF0000")]
        )
        let store = ProjectStore()
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutCoreFeatureTests-\(UUID().uuidString)")
        let projectURL = directoryURL.appendingPathComponent("project.moviecut.json")
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        try await store.save(project, to: projectURL)
        let loadedProject = try await store.load(from: projectURL)

        #expect(loadedProject == project)
    }

    @Test("Project JSON encoding includes all fields")
    func projectJSONEncodingIncludesAllFields() throws {
        let asset = makeAsset()
        let project = makeProject(
            mediaLibrary: MediaLibrary(assets: [asset.id: asset]),
            tracks: [makeTrack(clips: [makeClip(assetId: asset.id)])],
            markers: [Marker(time: 1.25, name: "Intro")]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = try encoder.encode(project)
        let decodedProject = try JSONDecoder().decode(Project.self, from: data)
        let jsonObject = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(decodedProject == project)
        #expect(Set(jsonObject.keys) == [
            "id",
            "name",
            "createdAt",
            "updatedAt",
            "appVersion",
            "schemaVersion",
            "mediaLibrary",
            "timeline",
            "markers",
            "canvas",
            "exportSettings",
            "playbackSettings"
        ])
    }

    @Test("Timeline duration equals sum of clip durations on longest track")
    func timelineDurationEqualsSumOfClipDurationsOnLongestTrack() {
        let videoTrack = makeTrack(kind: .video, name: "Video", clips: [
            makeClip(sourceRange: TimeRange(start: 0, duration: 3), timelineRange: TimeRange(start: 0, duration: 3)),
            makeClip(sourceRange: TimeRange(start: 3, duration: 5), timelineRange: TimeRange(start: 3, duration: 5))
        ])
        let audioTrack = makeTrack(kind: .audio, name: "Audio", clips: [
            makeClip(kind: .audio, sourceRange: TimeRange(start: 0, duration: 2), timelineRange: TimeRange(start: 0, duration: 2)),
            makeClip(kind: .audio, sourceRange: TimeRange(start: 2, duration: 4), timelineRange: TimeRange(start: 2, duration: 4))
        ])
        let timeline = Timeline(tracks: [videoTrack, audioTrack])

        #expect(timeline.duration == 8)
    }

    @Test("Track zIndex ordering preserved")
    func trackZIndexOrderingPreserved() {
        let topTrack = makeTrack(name: "Top", zIndex: 20)
        let bottomTrack = makeTrack(name: "Bottom", zIndex: 0)
        let middleTrack = makeTrack(name: "Middle", zIndex: 10)
        let timeline = Timeline(tracks: [topTrack, bottomTrack, middleTrack])

        #expect(timeline.tracks.map(\.id) == [topTrack.id, bottomTrack.id, middleTrack.id])
        #expect(timeline.tracks.map(\.zIndex) == [20, 0, 10])
        #expect(timeline.tracks.sorted { $0.zIndex < $1.zIndex }.map(\.name) == ["Bottom", "Middle", "Top"])
    }

    @Test("Clip transform default is identity")
    func clipTransformDefaultIsIdentity() {
        let transform = ClipTransform()

        #expect(transform.position == .zero)
        #expect(transform.offset == .zero)
        #expect(transform.scale == CGSize(width: 1, height: 1))
        #expect(transform.rotation == 0)
        #expect(transform.anchorPoint == CGPoint(x: 0.5, y: 0.5))
    }

    @Test("Clip effects can be set and retrieved")
    func clipEffectsCanBeSetAndRetrieved() {
        let effects = [
            Effect(type: .brightness, parameters: ["amount": 0.2]),
            Effect(type: .blur, parameters: ["radius": 3])
        ]
        let clip = makeClip(effects: effects)

        #expect(clip.effects == effects)
    }

    @Test("Clip volume defaults to 1.0")
    func clipVolumeDefaultsToOne() {
        let clip = makeClip()

        #expect(clip.volume == 1.0)
    }

    @Test("Clip playback rate defaults to 1.0")
    func clipPlaybackRateDefaultsToOne() {
        let clip = makeClip()

        #expect(clip.playbackRate == 1.0)
    }

    @Test("TimeRange contains time correctly")
    func timeRangeContainsTimeCorrectly() {
        let range = TimeRange(start: 2, duration: 5)
        let emptyRange = TimeRange(start: 4, duration: 0)

        #expect(range.contains(1.999) == false)
        #expect(range.contains(2) == true)
        #expect(range.contains(4.5) == true)
        #expect(range.contains(6.999) == true)
        #expect(range.contains(7) == false)
        #expect(range.contains(7.001) == false)
        #expect(emptyRange.contains(4) == false)
    }

    @Test("CanvasPreset aspect ratios computed correctly")
    func canvasPresetAspectRatiosComputedCorrectly() {
        let portrait = CanvasPreset(aspectRatio: .portrait9x16)
        let landscape = CanvasPreset(aspectRatio: .landscape16x9)
        let square = CanvasPreset(aspectRatio: .square1x1)

        #expect(portrait.size == CGSize(width: 1080, height: 1920))
        #expect(landscape.size == CGSize(width: 1920, height: 1080))
        #expect(square.size == CGSize(width: 1080, height: 1080))
        #expect(aspectRatio(of: portrait) == 9.0 / 16.0)
        #expect(aspectRatio(of: landscape) == 16.0 / 9.0)
        #expect(aspectRatio(of: square) == 1.0)
    }

    @Test("ExportSettings default values")
    func exportSettingsDefaultValues() {
        let settings = ExportSettings()

        #expect(settings.codec == .h264)
        #expect(settings.resolution == .p1080)
        #expect(settings.frameRate == .fps30)
        #expect(settings.audioCodec == .aac)
        #expect(settings.containerFormat == .mp4)
        #expect(settings.quality == .high)
        #expect(settings.videoBitrateMbps == nil)
    }

    @Test("Delete marker command removes marker from project and timeline")
    func deleteMarkerCommandRemovesMarkerFromProjectAndTimeline() async throws {
        let marker = Marker(time: 4.25, name: "Hook", color: "#FFD60A")
        let session = EditorSession(project: makeProject(markers: [marker]))

        try await session.dispatch(DeleteMarkerCommand(markerId: marker.id))

        let snapshot = await session.snapshot()
        #expect(snapshot.markers.isEmpty)
        #expect(snapshot.timeline.markers.isEmpty)

        try await session.undo()

        let restored = await session.snapshot()
        #expect(restored.markers == [marker])
        #expect(restored.timeline.markers == [marker])
    }

    @Test("Update marker command renames marker in project and timeline")
    func updateMarkerCommandRenamesMarkerInProjectAndTimeline() async throws {
        let marker = Marker(time: 7.5, name: "Old Name", color: "#FF9500")
        let updatedMarker = Marker(id: marker.id, time: marker.time, name: "New Name", color: marker.color)
        let session = EditorSession(project: makeProject(markers: [marker]))

        try await session.dispatch(UpdateMarkerCommand(markerId: marker.id, marker: updatedMarker))

        let snapshot = await session.snapshot()
        #expect(snapshot.markers == [updatedMarker])
        #expect(snapshot.timeline.markers == [updatedMarker])

        try await session.undo()

        let restored = await session.snapshot()
        #expect(restored.markers == [marker])
        #expect(restored.timeline.markers == [marker])
    }

    @Test("Canvas and export commands persist vertical social preset values")
    func canvasAndExportCommandsPersistVerticalSocialPresetValues() async throws {
        let session = EditorSession(project: makeProject())
        let canvas = CanvasPreset(aspectRatio: .portrait9x16, frameRate: .fps60)
        let exportSettings = ExportSettings(
            resolution: .p1080,
            frameRate: .fps60,
            codec: .h264,
            audioCodec: .aac
        )

        try await session.dispatch(SetProjectCanvasCommand(canvas: canvas))
        try await session.dispatch(SetProjectExportSettingsCommand(exportSettings: exportSettings))

        let snapshot = await session.snapshot()
        #expect(snapshot.canvas == canvas)
        #expect(snapshot.timeline.aspectRatio == .portrait9x16)
        #expect(snapshot.timeline.canvasSize == CGSize(width: 1080, height: 1920))
        #expect(snapshot.timeline.frameRate == Rational(numerator: 60, denominator: 1))
        #expect(snapshot.exportSettings == exportSettings)
    }

    private func makeProject(
        name: String = "Core Feature Project",
        mediaLibrary: MediaLibrary = MediaLibrary(),
        tracks: [Track] = [],
        markers: [Marker] = []
    ) -> Project {
        Project(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            appVersion: "0.1.0",
            mediaLibrary: mediaLibrary,
            timeline: Timeline(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                frameRate: Rational(numerator: 30, denominator: 1),
                canvasSize: CGSize(width: 1920, height: 1080),
                aspectRatio: .landscape16x9,
                tracks: tracks,
                markers: markers
            ),
            markers: markers,
            canvas: CanvasPreset(aspectRatio: .landscape16x9, frameRate: .fps30),
            exportSettings: ExportSettings(resolution: .p1080, frameRate: .fps30, codec: .h264, audioCodec: .aac)
        )
    }

    private func makeTrack(
        id: UUID = UUID(),
        kind: TrackKind = .video,
        name: String = "Video 1",
        zIndex: Int = 0,
        clips: [Clip] = []
    ) -> Track {
        Track(id: id, kind: kind, name: name, zIndex: zIndex, clips: clips)
    }

    private func makeClip(
        id: UUID = UUID(),
        assetId: UUID? = nil,
        kind: ClipKind = .video,
        sourceRange: TimeRange = TimeRange(start: 0, duration: 4),
        timelineRange: TimeRange = TimeRange(start: 0, duration: 4),
        effects: [Effect] = []
    ) -> Clip {
        Clip(
            id: id,
            assetId: assetId,
            kind: kind,
            sourceRange: sourceRange,
            timelineRange: timelineRange,
            effects: effects
        )
    }

    private func makeAsset(id: UUID = UUID()) -> MediaAsset {
        MediaAsset(
            id: id,
            originalURL: URL(fileURLWithPath: "/tmp/moviecut-fixture-\(id.uuidString).mov"),
            kind: .video,
            duration: 12.5,
            metadata: MediaMetadata(width: 1920, height: 1080, frameRate: 30, codec: "h264", fileSize: 1_024)
        )
    }

    private func aspectRatio(of preset: CanvasPreset) -> Double {
        Double(preset.size.width / preset.size.height)
    }
}
