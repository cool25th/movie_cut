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
}
