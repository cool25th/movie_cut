import Foundation
import Testing
@testable import MovieCutCore

/// CODEX-19: callers on both platforms assign `zIndex: tracks.count`, which
/// collides after a deletion (0/1/2, remove 0 → the two survivors keep 1/2,
/// and the next add is 2 again). Rendering orders layers by zIndex alone, so
/// a duplicate makes the overlap order nondeterministic. CreateTrackCommand
/// is the choke point every surface funnels through — these tests pin the
/// normalization contract.
@Suite("CreateTrackCommand z-index normalization (CODEX-19)")
struct CreateTrackZIndexNormalizationTests {
    private func makeProject(zIndexes: [Int]) -> Project {
        var project = Project(name: "z-normalize")
        project.timeline.tracks = zIndexes.enumerated().map { index, z in
            Track(kind: .video, name: "T\(index)", zIndex: z)
        }
        return project
    }

    @Test("a colliding z-index (the delete-then-add case) is bumped to max+1")
    func collisionBumpedToMaxPlusOne() throws {
        // Default project 0/1/2 → delete z0 → survivors 1/2 → caller's
        // `tracks.count` (=2) now COLLIDES with the survivor.
        var project = makeProject(zIndexes: [1, 2])
        let track = Track(kind: .video, name: "new", zIndex: 2)

        try CreateTrackCommand(track: track).apply(to: &project)

        #expect(project.timeline.tracks.count == 3)
        #expect(Set(project.timeline.tracks.map(\.zIndex)).count == 3,
                "z-indexes must stay unique; got \(project.timeline.tracks.map(\.zIndex))")
        #expect(project.timeline.tracks.last?.zIndex == 3,
                "the colliding add must land at max+1")
    }

    @Test("a non-colliding explicit z-index is preserved")
    func uniqueZIndexPreserved() throws {
        var project = makeProject(zIndexes: [1, 2])
        let track = Track(kind: .text, name: "lyrics", zIndex: 7)

        try CreateTrackCommand(track: track).apply(to: &project)

        #expect(project.timeline.tracks.last?.zIndex == 7,
                "deliberate layer placement must survive normalization")
    }

    @Test("the exact defect sequence: 0/1/2 → remove 0 → add keeps uniqueness")
    func defectSequence() throws {
        var project = Project(name: "z-seq")
        project.timeline.tracks = [
            Track(kind: .video, name: "V", zIndex: 0),
            Track(kind: .video, name: "V2", zIndex: 1),
            Track(kind: .audio, name: "A", zIndex: 2)
        ]
        // Remove z0 (both platforms' RemoveTrackCommand path shape).
        if let index = project.timeline.tracks.firstIndex(where: { $0.zIndex == 0 }) {
            project.timeline.tracks.remove(at: index)
        }
        // Caller computes zIndex = tracks.count = 2 — the old collision.
        let added = Track(kind: .text, name: "T", zIndex: project.timeline.tracks.count)
        try CreateTrackCommand(track: added).apply(to: &project)

        let zIndexes = project.timeline.tracks.map(\.zIndex)
        #expect(Set(zIndexes).count == zIndexes.count,
                "the exact defect sequence must end unique; got \(zIndexes)")
    }

    @Test("round-trip through undo restores the pre-add z-indexes exactly")
    func undoRoundTrip() async throws {
        let session = EditorSession(project: makeProject(zIndexes: [1, 2]))
        let track = Track(kind: .video, name: "new", zIndex: 2)

        try await session.dispatch(CreateTrackCommand(track: track))
        let after = await session.snapshot()
        #expect(after.timeline.tracks.last?.zIndex == 3)

        try await session.undo()
        let restored = await session.snapshot()
        #expect(restored.timeline.tracks.map(\.zIndex) == [1, 2])
    }
}
