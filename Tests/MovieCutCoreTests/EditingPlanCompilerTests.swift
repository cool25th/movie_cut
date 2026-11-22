import Foundation
import Testing
@testable import MovieCutCore

@Suite("EditingPlanCompiler Sequential Assembly Tests")
struct EditingPlanCompilerTests {

    private func makeEmptyProject() -> Project {
        Project(name: "EmptyForCompiler")
    }

    @Test("Sequential actions referencing preceding creations compile and apply atomically")
    func sequentialCompilationSucceeds() async throws {
        let initialProject = makeEmptyProject()
        let session = EditorSession(project: initialProject)
        let snapshot = await session.snapshotWithRevision()

        let trackId = UUID()
        let assetId = UUID()
        let clipId = UUID()

        let asset = MediaAsset(
            id: assetId,
            originalURL: URL(fileURLWithPath: "/tmp/test_photo.jpg"),
            kind: .image
        )

        let actions: [EditingActionDSL.Action] = [
            .createTrack(trackId: trackId, kind: .video, name: "Main Video"),
            .registerAsset(asset: asset),
            .addClip(
                clipId: clipId,
                trackId: trackId,
                assetId: assetId,
                timelineRange: TimeRange(start: 0, duration: 5),
                sourceRange: TimeRange(start: 0, duration: 5),
                kind: .image
            ),
            .setClipTransform(clipId: clipId, transform: ClipTransform(scale: CGSize(width: 1.2, height: 1.2))),
            .setClipKeyframes(clipId: clipId, keyframes: [
                Keyframe(property: .scaleX, time: 0, value: 1.0),
                Keyframe(property: .scaleX, time: 5, value: 1.2),
            ]),
        ]

        let preparedPlan = try await EditingPlanCompiler.compile(
            actions,
            for: snapshot.project,
            baseRevision: snapshot.revision
        )

        #expect(preparedPlan.batchCommand.commands.count == 5)
        #expect(preparedPlan.expectedDuration == 5.0)

        // Dispatch to session
        let newRev = try await session.dispatch(
            preparedPlan.batchCommand,
            expectedRevision: snapshot.revision
        )
        #expect(newRev.value == 1)

        let updated = await session.snapshot()
        #expect(updated.timeline.tracks.count == 1)
        #expect(updated.timeline.tracks[0].clips.count == 1)
        #expect(updated.mediaLibrary.assets[assetId] != nil)
        let clip = updated.timeline.tracks[0].clips[0]
        #expect(clip.id == clipId)
        #expect(clip.transform.scale == CGSize(width: 1.2, height: 1.2))
        #expect(clip.keyframes.count == 2)

        // Single undo restores the empty project
        try await session.undo()
        let undone = await session.snapshot()
        #expect(undone.timeline.tracks.isEmpty)
        #expect(undone.mediaLibrary.assets.isEmpty)
    }

    @Test("Mid-sequence invalid action rejects entire plan without mutating draft or session")
    func invalidMidSequenceActionFailsClosed() async throws {
        let initialProject = makeEmptyProject()
        let session = EditorSession(project: initialProject)
        let snapshot = await session.snapshotWithRevision()

        let trackId = UUID()
        let nonExistentClipId = UUID()

        let actions: [EditingActionDSL.Action] = [
            .createTrack(trackId: trackId, kind: .video, name: "Main Video"),
            // This action will fail because the clip was never added
            .setClipTransform(clipId: nonExistentClipId, transform: ClipTransform(scale: CGSize(width: 1.5, height: 1.5))),
        ]

        await #expect(throws: EditingActionDSL.PlanningError.self) {
            try await EditingPlanCompiler.compile(
                actions,
                for: snapshot.project,
                baseRevision: snapshot.revision
            )
        }

        // Session was not touched
        let current = await session.snapshot()
        #expect(current.timeline.tracks.isEmpty)
    }

    @Test("Filter, color correction, trim, and marker actions compile into one atomic undoable batch")
    func compileFilterColorCorrectionAndMarkerActionsAtomically() async throws {
        let initialProject = makeEmptyProject()
        let session = EditorSession(project: initialProject)
        let snapshot = await session.snapshotWithRevision()

        let trackId = UUID()
        let assetId = UUID()
        let clipId = UUID()
        let asset = MediaAsset(
            id: assetId,
            originalURL: URL(fileURLWithPath: "/tmp/test_video.mp4"),
            kind: .video,
            duration: 10.0
        )

        let actions: [EditingActionDSL.Action] = [
            .createTrack(trackId: trackId, kind: .video, name: "Video"),
            .registerAsset(asset: asset),
            .addClip(
                clipId: clipId,
                trackId: trackId,
                assetId: assetId,
                timelineRange: TimeRange(start: 0, duration: 5),
                sourceRange: TimeRange(start: 0, duration: 5),
                kind: .video
            ),
            .trimClip(
                clipId: clipId,
                sourceRange: TimeRange(start: 0, duration: 8),
                timelineRange: TimeRange(start: 0, duration: 8)
            ),
            .setClipEffects(clipId: clipId, effects: [Effect(type: .grayscale)]),
            .setClipColorCorrection(
                clipId: clipId,
                colorCorrection: ColorCorrection(brightness: 0.2, contrast: 1.1, saturation: 0.9)
            ),
            .addMarker(name: "Marker 1", time: 4.0),
        ]

        let prepared = try await EditingPlanCompiler.compile(
            actions,
            for: snapshot.project,
            baseRevision: snapshot.revision
        )

        try await session.dispatch(prepared.batchCommand, expectedRevision: snapshot.revision)
        let applied = await session.snapshot()
        let clip = try #require(applied.timeline.tracks.first?.clips.first)
        #expect(clip.timelineRange.duration == 8.0)
        #expect(clip.effects.map(\.type) == [.grayscale])
        #expect(abs((clip.colorCorrection?.brightness ?? 0) - 0.2) < 1e-6)
        #expect(applied.markers.count == 1)
        #expect(applied.markers.first?.name == "Marker 1")

        try await session.undo()
        let undone = await session.snapshot()
        #expect(undone.timeline.tracks.isEmpty)
        #expect(undone.markers.isEmpty)
    }

    @Test("CA-35: destructive action classification, stale-revision rejection, and single-undo recovery")
    func destructivePlanMetadataAndConfirmationContract() async throws {
        let trackId = UUID()
        let assetId = UUID()
        let clipId = UUID()
        let asset = MediaAsset(
            id: assetId,
            originalURL: URL(fileURLWithPath: "/tmp/sample.mp4"),
            kind: .video,
            duration: 10.0
        )
        let clip = Clip(
            id: clipId,
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 10.0),
            timelineRange: TimeRange(start: 0, duration: 10.0)
        )
        let initialProject = Project(
            name: "DestructiveGate",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(tracks: [Track(id: trackId, kind: .video, name: "V1", zIndex: 0, clips: [clip])])
        )

        #expect(EditingActionDSL.Action.trimClip(
            clipId: clipId,
            sourceRange: TimeRange(start: 0, duration: 6),
            timelineRange: TimeRange(start: 0, duration: 6)
        ).isDestructive)
        #expect(EditingActionDSL.Action.deleteTimelineRange(start: 2, end: 4).isDestructive)
        #expect(EditingActionDSL.Action.deleteClip(clipId: clipId).isDestructive)
        #expect(EditingActionDSL.Action.removeSilence(clipId: clipId).isDestructive)
        #expect(!EditingActionDSL.Action.setVolume(clipId: clipId, volume: 0.5).isDestructive)
        #expect(!EditingActionDSL.Action.addMarker(name: "M1", time: 1.0).isDestructive)

        let session = EditorSession(project: initialProject)
        let snapshot = await session.snapshotWithRevision()

        let prepared = try await EditingPlanCompiler.compile(
            [
                .trimClip(
                    clipId: clipId,
                    sourceRange: TimeRange(start: 0, duration: 6.0),
                    timelineRange: TimeRange(start: 0, duration: 6.0)
                )
            ],
            for: snapshot.project,
            baseRevision: snapshot.revision,
            label: "Trim clip",
            summaryLines: ["Trim clip #1 to 6.0s"]
        )

        // Compiling a destructive plan must NOT mutate the session until confirmed.
        let beforeConfirm = await session.snapshotWithRevision()
        #expect(beforeConfirm.revision == snapshot.revision)
        #expect(beforeConfirm.project.timeline.duration == 10.0)
        #expect(prepared.containsDestructiveActions)
        #expect(prepared.actionCount == 1)
        #expect(prepared.affectedClipCount == 1)
        #expect(abs(prepared.durationDeltaSeconds - (-4.0)) < 1e-6)
        #expect(prepared.summaryLines == ["Trim clip #1 to 6.0s"])

        // If an intervening edit happens before confirmation, stale revision must fail closed.
        try await session.dispatch(AddMarkerCommand(marker: Marker(time: 1.0, name: "Intervening")))
        await #expect(throws: EditorCommandError.self) {
            try await session.dispatch(
                prepared.batchCommand,
                planId: prepared.planId,
                expectedRevision: snapshot.revision
            )
        }

        // Re-compiling against the latest revision and confirming applies atomically and undoes in 1 step.
        let latest = await session.snapshotWithRevision()
        let freshPrepared = try await EditingPlanCompiler.compile(
            [
                .trimClip(
                    clipId: clipId,
                    sourceRange: TimeRange(start: 0, duration: 6.0),
                    timelineRange: TimeRange(start: 0, duration: 6.0)
                )
            ],
            for: latest.project,
            baseRevision: latest.revision
        )
        try await session.dispatch(
            freshPrepared.batchCommand,
            planId: freshPrepared.planId,
            expectedRevision: latest.revision
        )
        #expect(abs((await session.snapshot()).timeline.duration - 6.0) < 1e-6)

        try await session.undo()
        #expect(abs((await session.snapshot()).timeline.duration - 10.0) < 1e-6)
    }
}
