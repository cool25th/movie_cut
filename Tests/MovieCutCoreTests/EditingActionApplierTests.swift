import Foundation
import Testing
@testable import MovieCutCore

/// P3 increment 2 — the applier: typed actions compile to REAL commands,
/// a script applies as ONE undo unit, fail-closed scripts never mutate, and
/// undo recovers the pre-script project completely (the pre-registered
/// "undo recovery 100%" criterion's machine leg).
@Suite("Editing action applier (P3 increment 2)")
struct EditingActionApplierTests {

    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutCoreTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    private func makeProject() -> (Project, UUID) {
        let clipId = UUID()
        let clip = Clip(
            id: clipId,
            assetId: UUID(), kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10)
        )
        let project = Project(
            name: "applier",
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: [clip]),
            ])
        )
        return (project, clipId)
    }

    private func volume(of clipId: UUID, in project: Project) -> Double? {
        for track in project.timeline.tracks {
            if let clip = track.clips.first(where: { $0.id == clipId }) {
                return clip.volume
            }
        }
        return nil
    }

    @Test("Pure actions compile to the real command types with mapped fields")
    func compileMapping() async throws {
        let (project, clipId) = makeProject()
        let actions: [EditingActionDSL.Action] = [
            .deleteTimelineRange(start: 2, end: 6),
            .setVolume(clipId: clipId, volume: 0.5),
            .setSpeed(clipId: clipId, rate: 2),
            .applyAudioPreset(clipId: clipId, preset: .voiceEnhance),
        ]
        let batch = try await EditingActionApplier.compile(actions, for: project)

        #expect(batch.commands.count == 4)
        guard let autoCut = batch.commands[0] as? AutoCutCommand else {
            Issue.record("expected AutoCutCommand, got \(type(of: batch.commands[0]))")
            return
        }
        #expect(autoCut.removableRanges == [TimeRange(start: 2, duration: 4)])

        guard let volume = batch.commands[1] as? SetVolumeCommand else {
            Issue.record("expected SetVolumeCommand")
            return
        }
        #expect(volume.clipId == clipId)
        #expect(volume.volume == 0.5)

        guard let speed = batch.commands[2] as? SetClipSpeedCommand else {
            Issue.record("expected SetClipSpeedCommand")
            return
        }
        #expect(speed.clipId == clipId)
        #expect(speed.change == .constantRate(2))

        guard let property = batch.commands[3] as? SetClipPropertyCommand else {
            Issue.record("expected SetClipPropertyCommand")
            return
        }
        guard case let .equalizer(settings) = property.property else {
            Issue.record("expected .equalizer property")
            return
        }
        #expect(settings?.preset == .voiceEnhance)
        #expect(settings?.bands == EqualizerPreset.voiceEnhance.bands)
    }

    @Test("A script applies as ONE undo unit and undo recovers the project completely")
    func atomicApplyAndFullUndo() async throws {
        let (project, clipId) = makeProject()
        let before = project
        let session = EditorSession(project: project)

        let report = try await EditingActionApplier.apply([
            .deleteTimelineRange(start: 2, end: 6),
            .setVolume(clipId: clipId, volume: 0.5),
        ], to: session)

        #expect(report.actionCount == 2)
        #expect(report.undoUnits == 1, "the whole script must be a single undo unit")
        let dispatched = await session.commandCount
        #expect(dispatched == 1)

        // AutoCut is position-preserving (no ripple): removing [2,6) from one
        // 10s clip leaves [0,2) and [6,10) segments; the extent stays 10s.
        let after = await session.snapshot()
        let clips = after.timeline.tracks.flatMap(\.clips).sorted { $0.timelineRange.start < $1.timelineRange.start }
        #expect(clips.count == 2)
        #expect(clips.map(\.timelineRange.start) == [0, 6])
        #expect(clips.map(\.timelineRange.end) == [2, 10])
        #expect(volume(of: clipId, in: after) == 0.5, "the surviving left segment keeps the original id")

        try await session.undo()
        let restored = await session.snapshot()
        let restoredClips = restored.timeline.tracks.flatMap(\.clips)
        #expect(restoredClips.count == before.timeline.tracks.flatMap(\.clips).count)
        #expect(restoredClips.first?.timelineRange == before.timeline.tracks.flatMap(\.clips).first?.timelineRange)
        #expect(volume(of: clipId, in: restored) == volume(of: clipId, in: before))
    }

    @Test("One invalid action rejects the whole script before any mutation")
    func failClosedScript() async throws {
        let (project, clipId) = makeProject()
        let session = EditorSession(project: project)

        await #expect(throws: EditingActionDSL.PlanningError.self) {
            try await EditingActionApplier.apply([
                .setVolume(clipId: clipId, volume: 0.2),
                .deleteClip(clipId: UUID()),  // not in the project
            ], to: session)
        }

        let dispatched = await session.commandCount
        #expect(dispatched == 0, "nothing dispatched")
        let untouched = await session.snapshot()
        #expect(volume(of: clipId, in: untouched) == 1.0, "the valid prefix never applied")
    }

    @Test("keepRange compiles to the inverse auto-cut and applies")
    func keepRangeInverseCut() async throws {
        let (project, _) = makeProject()
        let session = EditorSession(project: project)

        try await EditingActionApplier.apply([
            .keepTimelineRange(start: 2, end: 6),
        ], to: session)

        // Keeping [2,6) cuts the inverse: exactly one clip, spanning [2,6).
        let after = await session.snapshot()
        let clips = after.timeline.tracks.flatMap(\.clips)
        #expect(clips.count == 1)
        #expect(clips.first?.timelineRange.start ?? -1 == 2)
        #expect(clips.first?.timelineRange.end ?? -1 == 6)
        #expect(abs(after.timeline.duration - 6) < 0.001, "extent = kept segment's end")
    }

    @Test("duckBackground runs the on-device service and compiles a real ducking command")
    func duckBackgroundRealAnalysis() async throws {
        let voiceURL = Self.repoRoot.appendingPathComponent("Tests/Fixtures/duck_voice_1000hz_1s_mono.wav")
        let bgmURL = Self.repoRoot.appendingPathComponent("Tests/Fixtures/duck_bgm_220hz_4s_mono.wav")
        let voiceAsset = MediaAsset(originalURL: voiceURL, kind: .audio, duration: 1)
        let bgmAsset = MediaAsset(originalURL: bgmURL, kind: .audio, duration: 4)

        let voice = Clip(assetId: voiceAsset.id, kind: .audio,
                         sourceRange: TimeRange(start: 0, duration: 1),
                         timelineRange: TimeRange(start: 0, duration: 1))
        let bgm = Clip(assetId: bgmAsset.id, kind: .audio,
                       sourceRange: TimeRange(start: 0, duration: 4),
                       timelineRange: TimeRange(start: 0, duration: 4))
        let project = Project(
            name: "agent-duck",
            mediaLibrary: MediaLibrary(assets: [voiceAsset.id: voiceAsset, bgmAsset.id: bgmAsset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .audio, name: "A", zIndex: 0, clips: [voice, bgm]),
            ])
        )
        let session = EditorSession(project: project)

        try await EditingActionApplier.apply([
            .duckBackground(speechClipId: voice.id),
        ], to: session)

        let after = await session.snapshot()
        let bgmClip = after.timeline.tracks.flatMap(\.clips).first { $0.id == bgm.id }
        #expect(bgmClip?.duckingRanges.isEmpty == false, "the overlapping BGM must carry ducking ranges")
        #expect(bgmClip?.duckingLevel != nil)

        try await session.undo()
        let restored = await session.snapshot()
        let restoredBgm = restored.timeline.tracks.flatMap(\.clips).first { $0.id == bgm.id }
        #expect(restoredBgm?.duckingRanges.isEmpty == true, "undo clears the agent's ducking")
        #expect(restoredBgm?.duckingLevel == nil)
    }

    @Test("removeSilence on a continuous tone is a typed failure, not a silent no-op")
    func removeSilenceTypedFailure() async throws {
        let toneURL = Self.repoRoot.appendingPathComponent("Tests/Fixtures/duck_voice_1000hz_1s_mono.wav")
        let asset = MediaAsset(originalURL: toneURL, kind: .audio, duration: 1)
        let clip = Clip(assetId: asset.id, kind: .audio,
                        sourceRange: TimeRange(start: 0, duration: 1),
                        timelineRange: TimeRange(start: 0, duration: 1))
        let project = Project(
            name: "agent-silence",
            mediaLibrary: MediaLibrary(assets: [asset.id: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .audio, name: "A", zIndex: 0, clips: [clip]),
            ])
        )
        let session = EditorSession(project: project)

        // A 1 kHz constant tone has no silence: the real on-device analysis
        // runs and the script is rejected with the typed reason. (Positive
        // silence cases are covered by the engine's own gates.)
        await #expect(throws: EditingActionDSL.PlanningError.noSilenceDetected) {
            try await EditingActionApplier.apply([
                .removeSilence(clipId: clip.id),
            ], to: session)
        }
        let dispatched = await session.commandCount
        #expect(dispatched == 0)
    }
}
