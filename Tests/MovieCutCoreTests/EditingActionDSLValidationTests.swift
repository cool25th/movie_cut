import Foundation
import Testing
@testable import MovieCutCore

@Suite("Editing Action DSL Validation Tests (Fail-Closed)")
struct EditingActionDSLValidationTests {

    private func makeProject() -> (Project, UUID) {
        let trackId = UUID()
        let project = Project(
            name: "ValidationTest",
            timeline: Timeline(tracks: [
                Track(id: trackId, kind: .video, name: "V")
            ])
        )
        return (project, trackId)
    }

    @Test("addClip throws assetNotFound when assetId does not exist in media library")
    func addClipThrowsAssetNotFound() {
        let (project, trackId) = makeProject()
        let missingAssetId = UUID()

        #expect(throws: EditingActionDSL.PlanningError.assetNotFound(missingAssetId)) {
            try EditingActionDSL.plan(
                .addClip(
                    clipId: UUID(),
                    trackId: trackId,
                    assetId: missingAssetId,
                    timelineRange: TimeRange(start: 0, duration: 5),
                    sourceRange: TimeRange(start: 0, duration: 5),
                    kind: .image
                ),
                for: project
            )
        }
    }

    @Test("addClip throws incompatibleAssetKind when image asset is placed as audio clip")
    func addClipThrowsIncompatibleAssetKind() {
        let photoAsset = MediaAsset(
            id: UUID(),
            originalURL: URL(fileURLWithPath: "/tmp/photo.jpg"),
            kind: .image
        )
        let trackId = UUID()
        let project = Project(
            name: "Test",
            mediaLibrary: MediaLibrary(assets: [photoAsset.id: photoAsset]),
            timeline: Timeline(tracks: [Track(id: trackId, kind: .audio, name: "A")])
        )

        #expect(throws: EditingActionDSL.PlanningError.incompatibleAssetKind(clip: .audio, asset: .image)) {
            try EditingActionDSL.plan(
                .addClip(
                    clipId: UUID(),
                    trackId: trackId,
                    assetId: photoAsset.id,
                    timelineRange: TimeRange(start: 0, duration: 5),
                    sourceRange: TimeRange(start: 0, duration: 5),
                    kind: .audio
                ),
                for: project
            )
        }
    }

    @Test("addClip throws sourceRangeExceedsAssetDuration when audio range exceeds duration")
    func addClipThrowsSourceRangeExceeded() {
        let audioAsset = MediaAsset(
            id: UUID(),
            originalURL: URL(fileURLWithPath: "/tmp/bgm.wav"),
            kind: .audio,
            duration: 4.0
        )
        let trackId = UUID()
        let project = Project(
            name: "Test",
            mediaLibrary: MediaLibrary(assets: [audioAsset.id: audioAsset]),
            timeline: Timeline(tracks: [Track(id: trackId, kind: .audio, name: "A")])
        )

        #expect(throws: EditingActionDSL.PlanningError.sourceRangeExceedsAssetDuration(requested: 5.0, duration: 4.0)) {
            try EditingActionDSL.plan(
                .addClip(
                    clipId: UUID(),
                    trackId: trackId,
                    assetId: audioAsset.id,
                    timelineRange: TimeRange(start: 0, duration: 5.0),
                    sourceRange: TimeRange(start: 0, duration: 5.0),
                    kind: .audio
                ),
                for: project
            )
        }
    }

    @Test("addClip throws invalidTimeValue when timeline or source duration is non-positive or NaN")
    func addClipThrowsInvalidTimeValue() {
        let (project, trackId) = makeProject()
        let asset = MediaAsset(id: UUID(), originalURL: URL(fileURLWithPath: "/tmp/p.jpg"), kind: .image)
        let projectWithAsset = Project(
            name: "Test",
            mediaLibrary: MediaLibrary(assets: [asset.id: asset]),
            timeline: project.timeline
        )

        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .addClip(
                    clipId: UUID(),
                    trackId: trackId,
                    assetId: asset.id,
                    timelineRange: TimeRange(start: 0, duration: -1),
                    sourceRange: TimeRange(start: 0, duration: 5),
                    kind: .image
                ),
                for: projectWithAsset
            )
        }

        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .addClip(
                    clipId: UUID(),
                    trackId: trackId,
                    assetId: asset.id,
                    timelineRange: TimeRange(start: 0, duration: Double.nan),
                    sourceRange: TimeRange(start: 0, duration: 5),
                    kind: .image
                ),
                for: projectWithAsset
            )
        }
    }

    @Test("registerAsset throws assetAlreadyExists when colliding ID has different URL or kind")
    func registerAssetCollisionThrows() {
        let asset1 = MediaAsset(id: UUID(), originalURL: URL(fileURLWithPath: "/tmp/a.jpg"), kind: .image)
        let asset2Conflict = MediaAsset(id: asset1.id, originalURL: URL(fileURLWithPath: "/tmp/b.jpg"), kind: .image)
        let project = Project(name: "Test", mediaLibrary: MediaLibrary(assets: [asset1.id: asset1]))

        #expect(throws: EditingActionDSL.PlanningError.assetAlreadyExists(asset1.id)) {
            try EditingActionDSL.plan(.registerAsset(asset: asset2Conflict), for: project)
        }
    }

    @Test("registerAsset rejects ANY existing id — identical re-registration must not overwrite")
    func registerAssetIdenticalReregistrationThrows() {
        let asset = MediaAsset(id: UUID(), originalURL: URL(fileURLWithPath: "/tmp/a.jpg"), kind: .image)
        let project = Project(name: "Test", mediaLibrary: MediaLibrary(assets: [asset.id: asset]))

        // Same id, same URL, same kind — the old carve-out silently
        // overwrote stored metadata/bookmarks (review 2026-10-05). Reuse is
        // referencing the asset (addClip) without registering; refresh is
        // the explicit UpdateMediaAssetCommand.
        #expect(throws: EditingActionDSL.PlanningError.assetAlreadyExists(asset.id)) {
            try EditingActionDSL.plan(.registerAsset(asset: asset), for: project)
        }
    }

    @Test("registerAsset rejects non-finite or non-positive known durations")
    func registerAssetInvalidDurationThrows() {
        let (project, _) = makeProject()
        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .registerAsset(asset: MediaAsset(id: UUID(), originalURL: URL(fileURLWithPath: "/tmp/x.wav"), kind: .audio, duration: .nan)),
                for: project
            )
        }
        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .registerAsset(asset: MediaAsset(id: UUID(), originalURL: URL(fileURLWithPath: "/tmp/y.wav"), kind: .audio, duration: .infinity)),
                for: project
            )
        }
        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .registerAsset(asset: MediaAsset(id: UUID(), originalURL: URL(fileURLWithPath: "/tmp/z.wav"), kind: .audio, duration: 0)),
                for: project
            )
        }
    }

    @Test("explicit asset metadata refresh goes through UpdateMediaAssetCommand, not registerAsset")
    func explicitAssetUpdatePath() throws {
        var asset = MediaAsset(id: UUID(), originalURL: URL(fileURLWithPath: "/tmp/u.jpg"), kind: .image)
        var project = Project(name: "Test", mediaLibrary: MediaLibrary(assets: [asset.id: asset]))

        asset.metadata = MediaMetadata(width: 64, height: 64)
        try UpdateMediaAssetCommand(asset: asset).apply(to: &project)
        #expect(project.mediaLibrary.assets[asset.id]?.metadata == MediaMetadata(width: 64, height: 64))
    }

    @Test("setClipTransform rejects non-finite values and non-positive scale")
    func setClipTransformRejectsNonFinite() throws {
        let (project, trackId, clipId) = makeProjectWithClip()

        let good = ClipTransform(
            position: CGPoint(x: 0, y: 0), offset: CGPoint(x: 0, y: 0),
            scale: CGSize(width: 1, height: 1), rotation: 0,
            anchorPoint: CGPoint(x: 0.5, y: 0.5)
        )
        _ = try EditingActionDSL.plan(.setClipTransform(clipId: clipId, transform: good), for: project)

        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .setClipTransform(clipId: clipId, transform: ClipTransform(position: CGPoint(x: Double.nan, y: 0))),
                for: project
            )
        }
        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .setClipTransform(clipId: clipId, transform: ClipTransform(rotation: .infinity)),
                for: project
            )
        }
        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .setClipTransform(clipId: clipId, transform: ClipTransform(scale: CGSize(width: 0, height: 1))),
                for: project
            )
        }
        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .setClipTransform(clipId: UUID(), transform: good),
                for: project
            )
        }
    }

    @Test("setClipKeyframes rejects non-finite values and negative times")
    func setClipKeyframesRejectsNonFinite() throws {
        let (project, _, clipId) = makeProjectWithClip()

        _ = try EditingActionDSL.plan(
            .setClipKeyframes(clipId: clipId, keyframes: [
                Keyframe(property: .scaleX, time: 0, value: 1.0),
                Keyframe(property: .scaleX, time: 5, value: 1.15),
            ]),
            for: project
        )

        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .setClipKeyframes(clipId: clipId, keyframes: [
                    Keyframe(property: .scaleX, time: 0, value: .nan),
                ]),
                for: project
            )
        }
        // Negative time is normalized at the MODEL boundary (Keyframe.init
        // clamps with max(0, time)) — the DSL validator never sees it.
        #expect(Keyframe(property: .scaleX, time: -0.1, value: 1.0).time == 0)
        #expect(throws: EditingActionDSL.PlanningError.self) {
            try EditingActionDSL.plan(
                .setClipKeyframes(clipId: clipId, keyframes: [
                    Keyframe(property: .scaleX, time: .infinity, value: 1.0),
                ]),
                for: project
            )
        }
    }

    /// Project with one image clip in place (target for property actions).
    private func makeProjectWithClip() -> (Project, UUID, UUID) {
        let asset = MediaAsset(id: UUID(), originalURL: URL(fileURLWithPath: "/tmp/kf.jpg"), kind: .image)
        let trackId = UUID()
        let clipId = UUID()
        let project = Project(
            name: "KeyframeValidation",
            mediaLibrary: MediaLibrary(assets: [asset.id: asset]),
            timeline: Timeline(tracks: [
                Track(id: trackId, kind: .video, name: "V", clips: [
                    Clip(
                        id: clipId,
                        kind: .image,
                        sourceRange: TimeRange(start: 0, duration: 5),
                        timelineRange: TimeRange(start: 0, duration: 5)
                    )
                ])
            ])
        )
        return (project, trackId, clipId)
    }

    @Test("Sequential draft compilation rejects bad sequence fail-closed without mutating original")
    func sequentialDraftFailClosed() async throws {
        let initialProject = Project(name: "InitialProject")
        let session = EditorSession(project: initialProject)
        let snapshot = await session.snapshotWithRevision()

        let validAsset = MediaAsset(id: UUID(), originalURL: URL(fileURLWithPath: "/tmp/valid.jpg"), kind: .image)
        let trackId = UUID()

        let actions: [EditingActionDSL.Action] = [
            .createTrack(trackId: trackId, kind: .video, name: "Video Track"),
            .registerAsset(asset: validAsset),
            // Bad action: trying to add clip from unregistered asset ID
            .addClip(
                clipId: UUID(),
                trackId: trackId,
                assetId: UUID(),
                timelineRange: TimeRange(start: 0, duration: 5),
                sourceRange: TimeRange(start: 0, duration: 5),
                kind: .image
            )
        ]

        await #expect(throws: EditingActionDSL.PlanningError.self) {
            try await EditingPlanCompiler.compile(actions, for: snapshot.project, baseRevision: snapshot.revision)
        }

        let sessionState = await session.snapshot()
        #expect(sessionState.timeline.tracks.isEmpty)
        #expect(sessionState.mediaLibrary.assets.isEmpty)
    }
}
