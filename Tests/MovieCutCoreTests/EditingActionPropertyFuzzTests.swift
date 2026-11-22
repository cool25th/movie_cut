import Foundation
import Testing
@testable import MovieCutCore

/// CA-37: Property-based fuzzing for `EditorSession`, `EditorCommand`, and `EditingActionDSL`.
/// Verifies that arbitrary valid sequences of N mutations followed by N `undo()` calls
/// restore the exact initial `Project` (including byte-identical JSON serialization),
/// and N `redo()` calls restore the exact post-execution `Project`.
@Suite("Editing Action Property Fuzzing (CA-37)")
struct EditingActionPropertyFuzzTests {

    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }

        mutating func nextInt(_ upperBound: Int) -> Int {
            precondition(upperBound > 0)
            return Int(next() % UInt64(upperBound))
        }

        mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
            let unit = Double(next() & 0x1F_FFFF_FFFF_FFFF) / Double(0x20_0000_0000_0000)
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
    }

    private func makeSeededProject() -> Project {
        let videoAssetId = UUID()
        let videoAsset = MediaAsset(
            id: videoAssetId,
            originalURL: URL(fileURLWithPath: "/tmp/fuzz_video.mp4"),
            kind: .video,
            duration: 60.0
        )
        let clips = (0..<4).map { idx in
            Clip(
                assetId: videoAssetId,
                kind: .video,
                sourceRange: TimeRange(start: Double(idx) * 5.0, duration: 5.0),
                timelineRange: TimeRange(start: Double(idx) * 5.0, duration: 5.0)
            )
        }
        var project = Project(name: "FuzzTarget")
        project.mediaLibrary.assets[videoAssetId] = videoAsset
        project.timeline.tracks = [
            Track(kind: .video, name: "Video 1", zIndex: 0, clips: clips),
            Track(kind: .audio, name: "Audio 1", zIndex: 1, clips: []),
        ]
        return project
    }

    @Test("Random command and DSL sequences satisfy apply^N -> undo^N == initial and redo^N == final across 25 seeds")
    func randomEditingSequencesPreserveExactUndoRedoInvariants() async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for seed in UInt64(1)...UInt64(25) {
            var rng = SplitMix64(seed: seed * 1_000_003)
            let initialProject = makeSeededProject()
            let initialData = try encoder.encode(initialProject)
            let session = EditorSession(project: initialProject)

            let stepCount = 6 + rng.nextInt(7) // 6...12 steps per trial
            var intermediateSnapshots: [Project] = [initialProject]

            for step in 0..<stepCount {
                let current = await session.snapshotWithRevision()
                let videoClips = current.project.timeline.tracks.first(where: { $0.kind == .video })?.clips ?? []
                guard let targetClip = videoClips.isEmpty ? nil : videoClips[rng.nextInt(videoClips.count)] else {
                    break
                }

                let choice = rng.nextInt(6)
                switch choice {
                case 0:
                    // Volume + Fade via DSL batch
                    let fade = rng.nextDouble(in: 0.0...min(1.0, targetClip.timelineRange.duration / 3.0))
                    let actions: [EditingActionDSL.Action] = [
                        .setClipFade(clipId: targetClip.id, fadeIn: fade, fadeOut: fade),
                    ]
                    let prepared = try await EditingPlanCompiler.compile(
                        actions,
                        for: current.project,
                        baseRevision: current.revision,
                        label: "FuzzStep-\(step)"
                    )
                    try await session.dispatch(
                        prepared.batchCommand,
                        planId: prepared.planId,
                        expectedRevision: current.revision
                    )

                case 1:
                    // Color Correction via DSL batch
                    let cc = ColorCorrection(
                        brightness: rng.nextDouble(in: -0.3...0.3),
                        contrast: rng.nextDouble(in: 0.8...1.3),
                        saturation: rng.nextDouble(in: 0.7...1.4),
                        warmth: rng.nextDouble(in: -0.2...0.2),
                        tint: rng.nextDouble(in: -0.2...0.2)
                    )
                    let actions: [EditingActionDSL.Action] = [
                        .setClipColorCorrection(clipId: targetClip.id, colorCorrection: cc),
                    ]
                    let prepared = try await EditingPlanCompiler.compile(
                        actions,
                        for: current.project,
                        baseRevision: current.revision,
                        label: "FuzzCC-\(step)"
                    )
                    try await session.dispatch(
                        prepared.batchCommand,
                        planId: prepared.planId,
                        expectedRevision: current.revision
                    )

                case 2:
                    // Effect stack via DSL batch
                    let effects: [Effect] = rng.nextInt(2) == 0 ? [.sepia] : [.grayscale]
                    let actions: [EditingActionDSL.Action] = [
                        .setClipEffects(clipId: targetClip.id, effects: effects),
                    ]
                    let prepared = try await EditingPlanCompiler.compile(
                        actions,
                        for: current.project,
                        baseRevision: current.revision,
                        label: "FuzzEffects-\(step)"
                    )
                    try await session.dispatch(
                        prepared.batchCommand,
                        planId: prepared.planId,
                        expectedRevision: current.revision
                    )

                case 3:
                    // Add Marker via DSL batch
                    let markerTime = rng.nextDouble(in: 0.0...20.0)
                    let actions: [EditingActionDSL.Action] = [
                        .addMarker(name: "M-\(seed)-\(step)", time: markerTime),
                    ]
                    let prepared = try await EditingPlanCompiler.compile(
                        actions,
                        for: current.project,
                        baseRevision: current.revision,
                        label: "FuzzMarker-\(step)"
                    )
                    try await session.dispatch(
                        prepared.batchCommand,
                        planId: prepared.planId,
                        expectedRevision: current.revision
                    )

                case 4:
                    // Role upsert / tag / rename / remove cycle
                    let preset = TimelineRole.presets[rng.nextInt(TimelineRole.presets.count)]
                    if !current.project.roles.contains(where: { $0.id == preset.id || $0.name == preset.name }) {
                        try await session.dispatch(AddTimelineRoleCommand(role: preset))
                    } else if rng.nextInt(2) == 0, let existingRole = current.project.roles.first {
                        try await session.dispatch(SetClipRoleCommand(clipIds: [targetClip.id], roleId: existingRole.id))
                    } else if let existingRole = current.project.roles.first {
                        try await session.dispatch(RemoveTimelineRoleCommand(roleId: existingRole.id))
                    }

                default:
                    // Transform update via DSL batch
                    let scale = rng.nextDouble(in: 0.9...1.25)
                    let transform = ClipTransform(
                        position: CGPoint(x: rng.nextDouble(in: -10...10), y: rng.nextDouble(in: -10...10)),
                        scale: CGSize(width: scale, height: scale),
                        rotation: 0
                    )
                    let actions: [EditingActionDSL.Action] = [
                        .setClipTransform(clipId: targetClip.id, transform: transform),
                    ]
                    let prepared = try await EditingPlanCompiler.compile(
                        actions,
                        for: current.project,
                        baseRevision: current.revision,
                        label: "FuzzTransform-\(step)"
                    )
                    try await session.dispatch(
                        prepared.batchCommand,
                        planId: prepared.planId,
                        expectedRevision: current.revision
                    )
                }

                let afterStep = await session.snapshotWithRevision()
                #expect(afterStep.revision.value == current.revision.value + 1)
                intermediateSnapshots.append(afterStep.project)
            }

            let executedSteps = intermediateSnapshots.count - 1
            let finalSnapshot = await session.snapshot()
            let finalData = try encoder.encode(finalSnapshot)

            // Undo all N steps one by one and verify each intermediate snapshot matches
            for idx in stride(from: executedSteps - 1, through: 0, by: -1) {
                try await session.undo()
                let undone = await session.snapshot()
                #expect(undone == intermediateSnapshots[idx])
            }

            let fullyUndone = await session.snapshot()
            let fullyUndoneData = try encoder.encode(fullyUndone)
            #expect(fullyUndone == initialProject)
            #expect(fullyUndoneData == initialData)

            // Redo all N steps and verify we land back at the exact final state
            for idx in 1...executedSteps {
                try await session.redo()
                let redone = await session.snapshot()
                #expect(redone == intermediateSnapshots[idx])
            }

            let fullyRedone = await session.snapshot()
            let fullyRedoneData = try encoder.encode(fullyRedone)
            #expect(fullyRedone == finalSnapshot)
            #expect(fullyRedoneData == finalData)
        }
    }
}
