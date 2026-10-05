import Foundation
import Testing
@testable import MovieCutCore

@Suite("Photo Montage Planner Tests")
struct PhotoMontagePlannerTests {

    private func makePhotos(count: Int) -> [MediaAsset] {
        (0..<count).map { idx in
            MediaAsset(
                id: UUID(),
                originalURL: URL(fileURLWithPath: "/tmp/photo_\(idx).jpg"),
                kind: .image
            )
        }
    }

    private func makeMusic() -> MediaAsset {
        MediaAsset(
            id: UUID(),
            originalURL: URL(fileURLWithPath: "/tmp/bgm.m4a"),
            kind: .audio,
            duration: 60.0
        )
    }

    @Test("Planning 3 photos for 15s generates 3 video clips of 5s each with keyframes")
    func plan3Photos15s() throws {
        let photos = makePhotos(count: 3)
        let revision = SessionRevision()

        let plan = try PhotoMontagePlanner.plan(
            photos: photos,
            music: nil,
            targetDuration: 15.0,
            baseRevision: revision
        )

        #expect(plan.targetDuration == 15.0)
        #expect(plan.targetCanvas == .portrait9x16)

        // 1 canvas + 1 track creation + 3 * (register + addClip + setKeyframes) = 1 + 1 + 9 = 11 actions
        #expect(plan.actions.count == 11)
        #expect(plan.actions[0] == .setCanvas(canvas: .portrait9x16))
    }

    @Test("Planning 3 photos and 1 music track for 15s compiles and applies to session with single undo/redo")
    func planPhotosAndMusicEndToEnd() async throws {
        let photos = makePhotos(count: 3)
        let music = makeMusic()

        let initialProject = Project(name: "MontageTest", timeline: Timeline(canvasSize: CGSize(width: 1920, height: 1080)))
        let session = EditorSession(project: initialProject)
        let snapshot = await session.snapshotWithRevision()

        let plan = try PhotoMontagePlanner.plan(
            photos: photos,
            music: music,
            targetDuration: 15.0,
            baseRevision: snapshot.revision
        )

        let prepared = try await EditingPlanCompiler.compile(
            plan.actions,
            for: snapshot.project,
            baseRevision: snapshot.revision,
            planId: plan.planId
        )

        #expect(prepared.expectedDuration == 15.0)

        // Dispatch to session as a single undo unit
        let newRev = try await session.dispatch(
            prepared.batchCommand,
            expectedRevision: snapshot.revision
        )
        #expect(newRev.value == 1)

        let project = await session.snapshot()
        #expect(project.timeline.tracks.count == 2) // Video track + Audio track
        #expect(project.timeline.duration == 15.0)
        #expect(project.canvas == .portrait9x16)

        let videoTrack = project.timeline.tracks.first(where: { $0.kind == .video })
        #expect(videoTrack != nil)
        #expect(videoTrack?.clips.count == 3)

        let audioTrack = project.timeline.tracks.first(where: { $0.kind == .audio })
        #expect(audioTrack != nil)
        #expect(audioTrack?.clips.count == 1)

        let audioClip = audioTrack?.clips.first
        #expect(audioClip?.timelineRange.duration == 15.0)
        #expect(audioClip?.fadeOutDuration == 1.5)

        // Verify single undo restores empty timeline and original canvas
        try await session.undo()
        let undone = await session.snapshot()
        #expect(undone.timeline.tracks.isEmpty)
        #expect(undone.timeline.duration == 0)
        #expect(undone.canvas == initialProject.canvas)

        // Verify single redo restores full 15s timeline and portrait canvas
        try await session.redo()
        let redone = await session.snapshot()
        #expect(redone.timeline.tracks.count == 2)
        #expect(redone.timeline.duration == 15.0)
        #expect(redone.canvas == .portrait9x16)
    }

    @Test("Short music (4s) loops to fill 15s target without exceeding asset duration")
    func planShortAudioLoopsProperly() async throws {
        let photos = makePhotos(count: 3)
        let shortMusic = MediaAsset(
            id: UUID(),
            originalURL: URL(fileURLWithPath: "/tmp/short_bgm.wav"),
            kind: .audio,
            duration: 4.0
        )

        let session = EditorSession(project: Project(name: "LoopTest"))
        let snapshot = await session.snapshotWithRevision()

        let plan = try PhotoMontagePlanner.plan(
            photos: photos,
            music: shortMusic,
            targetDuration: 15.0,
            baseRevision: snapshot.revision
        )

        let prepared = try await EditingPlanCompiler.compile(
            plan.actions,
            for: snapshot.project,
            baseRevision: snapshot.revision
        )

        try await session.dispatch(prepared.batchCommand, expectedRevision: snapshot.revision)

        let project = await session.snapshot()
        let audioTrack = project.timeline.tracks.first(where: { $0.kind == .audio })
        #expect(audioTrack != nil)

        // 15s with 4s loops: 4s + 4s + 4s + 3s = 4 clips
        guard let clips = audioTrack?.clips else {
            Issue.record("Missing audio clips")
            return
        }
        #expect(clips.count == 4)

        // Verify each clip respects asset duration (<= 4.0)
        for clip in clips {
            #expect(clip.sourceRange.duration <= 4.0 + 0.001)
            #expect(clip.sourceRange.end <= 4.0 + 0.001)
        }

        #expect(clips[0].timelineRange == TimeRange(start: 0, duration: 4))
        #expect(clips[0].fadeInDuration == 0.5)
        #expect(clips[0].fadeOutDuration == PhotoMontagePlanner.Limits.junctionFadeDuration)

        // Junction chunks carry anti-click micro-fades on BOTH edges.
        #expect(clips[1].timelineRange == TimeRange(start: 4, duration: 4))
        #expect(clips[1].fadeInDuration == PhotoMontagePlanner.Limits.junctionFadeDuration)
        #expect(clips[1].fadeOutDuration == PhotoMontagePlanner.Limits.junctionFadeDuration)

        #expect(clips[2].timelineRange == TimeRange(start: 8, duration: 4))
        #expect(clips[2].fadeInDuration == PhotoMontagePlanner.Limits.junctionFadeDuration)
        #expect(clips[2].fadeOutDuration == PhotoMontagePlanner.Limits.junctionFadeDuration)

        #expect(clips[3].timelineRange == TimeRange(start: 12, duration: 3))
        #expect(clips[3].sourceRange == TimeRange(start: 0, duration: 3))
        #expect(clips[3].fadeInDuration == PhotoMontagePlanner.Limits.junctionFadeDuration)
        #expect(clips[3].fadeOutDuration == 1.5)

        // Verify single undo / redo
        try await session.undo()
        let undone = await session.snapshot()
        #expect(undone.timeline.tracks.isEmpty)

        try await session.redo()
        let redone = await session.snapshot()
        #expect(redone.timeline.tracks.count == 2)
        #expect(redone.timeline.duration == 15.0)
    }

    // MARK: - Input limits (AI-03a M2)

    @Test("Non-finite target durations are rejected without producing actions")
    func rejectsNonFiniteTargetDuration() {
        let photos = makePhotos(count: 3)
        #expect(throws: EditingActionDSL.PlanningError.self) {
            _ = try PhotoMontagePlanner.plan(
                photos: photos, targetDuration: .infinity, baseRevision: SessionRevision()
            )
        }
        #expect(throws: EditingActionDSL.PlanningError.self) {
            _ = try PhotoMontagePlanner.plan(
                photos: photos, targetDuration: .nan, baseRevision: SessionRevision()
            )
        }
        #expect(throws: EditingActionDSL.PlanningError.self) {
            _ = try PhotoMontagePlanner.plan(
                photos: photos, targetDuration: 0, baseRevision: SessionRevision()
            )
        }
        #expect(throws: EditingActionDSL.PlanningError.self) {
            _ = try PhotoMontagePlanner.plan(
                photos: photos,
                targetDuration: PhotoMontagePlanner.Limits.maxTargetDuration + 1,
                baseRevision: SessionRevision()
            )
        }
    }

    @Test("Too many photos are rejected")
    func rejectsTooManyPhotos() {
        let photos = makePhotos(count: PhotoMontagePlanner.Limits.maxPhotoCount + 1)
        #expect(throws: EditingActionDSL.PlanningError.self) {
            _ = try PhotoMontagePlanner.plan(photos: photos, targetDuration: 15, baseRevision: SessionRevision())
        }
    }

    @Test("Music with unknown duration is rejected, not guessed")
    func rejectsUnknownMusicDuration() {
        let photos = makePhotos(count: 3)
        let unprobed = MediaAsset(
            id: UUID(),
            originalURL: URL(fileURLWithPath: "/tmp/unprobed.m4a"),
            kind: .audio
        )
        #expect(unprobed.duration == nil)
        #expect(throws: EditingActionDSL.PlanningError.self) {
            _ = try PhotoMontagePlanner.plan(
                photos: photos, music: unprobed, targetDuration: 15, baseRevision: SessionRevision()
            )
        }
    }

    @Test("Music shorter than the minimum and excessive loop counts are rejected")
    func rejectsExtremeMusic() {
        let photos = makePhotos(count: 3)
        let tiny = MediaAsset(
            id: UUID(),
            originalURL: URL(fileURLWithPath: "/tmp/tiny.wav"),
            kind: .audio,
            duration: 0.1
        )
        #expect(throws: EditingActionDSL.PlanningError.self) {
            _ = try PhotoMontagePlanner.plan(
                photos: photos, music: tiny, targetDuration: 15, baseRevision: SessionRevision()
            )
        }

        // 0.5s track over 60s needs 120 loops — over the cap.
        let Loops = PhotoMontagePlanner.Limits.maxMusicLoops
        let repetitive = MediaAsset(
            id: UUID(),
            originalURL: URL(fileURLWithPath: "/tmp/loop.wav"),
            kind: .audio,
            duration: 0.5
        )
        #expect(throws: EditingActionDSL.PlanningError.self) {
            _ = try PhotoMontagePlanner.plan(
                photos: photos,
                music: repetitive,
                targetDuration: TimeInterval(Loops + 1) * 0.5,
                baseRevision: SessionRevision()
            )
        }
    }

    // MARK: - Existing-project policy (AI-03a M4)

    @Test("Planning against a timeline with existing clips is rejected")
    func rejectsNonEmptyTimeline() {
        let photos = makePhotos(count: 3)
        var existingTrack = Track(kind: .video, name: "Existing")
        existingTrack.clips = [
            Clip(
                kind: .video,
                sourceRange: TimeRange(start: 0, duration: 5),
                timelineRange: TimeRange(start: 0, duration: 5)
            )
        ]
        #expect(throws: EditingActionDSL.PlanningError.timelineNotEmpty) {
            _ = try PhotoMontagePlanner.plan(
                photos: photos,
                targetDuration: 15,
                existingTracks: [existingTrack],
                baseRevision: SessionRevision()
            )
        }
    }

    @Test("A locked empty track is never reused for placement")
    func skipsLockedEmptyTrack() throws {
        let photos = makePhotos(count: 2)
        let lockedTrack = Track(kind: .video, name: "Locked", isLocked: true)
        let plan = try PhotoMontagePlanner.plan(
            photos: photos,
            targetDuration: 10,
            existingTracks: [lockedTrack],
            baseRevision: SessionRevision()
        )
        // The locked track is skipped: the planner creates its own.
        let createdTrackIds = plan.actions.compactMap { action -> UUID? in
            if case let .createTrack(trackId, _, _) = action { return trackId }
            return nil
        }
        #expect(createdTrackIds.contains(lockedTrack.id) == false)
        #expect(createdTrackIds.count >= 1)
    }
}
