import Foundation
import Testing

@testable import MovieCutCore

/// CA-20 stage 1 (W4): FCP-style clip role tags — model, persistence
/// round-trip (schema v9 migration), and the two commands the timeline
/// index UI will drive.
@Suite("Clip roles (CA-20 stage 1)")
struct ClipRolesTests {
    private func makeProject(clipCount: Int = 3) -> Project {
        let clipIds = (0..<clipCount).map { _ in UUID() }
        let clips = clipIds.map { _ in
            Clip(assetId: nil, kind: .video,
                 sourceRange: TimeRange(start: 0, duration: 1),
                 timelineRange: TimeRange(start: 0, duration: 1))
        }
        var project = Project(name: "roles")
        project.timeline = Timeline(
            canvasSize: CGSize(width: 320, height: 240),
            tracks: [Track(kind: .video, name: "V", zIndex: 0, clips: clips)]
        )
        return project
    }

    @Test("presets carry unique names and ids")
    func presetsUnique() {
        let names = Set(TimelineRole.presets.map(\.name))
        let ids = Set(TimelineRole.presets.map(\.id))
        #expect(names.count == TimelineRole.presets.count)
        #expect(ids.count == TimelineRole.presets.count)
    }

    @Test("roles and clip tags round-trip through JSON")
    func roundTrip() throws {
        var project = makeProject()
        let dialogue = TimelineRole.presets[0]
        try AddTimelineRoleCommand(role: dialogue).apply(to: &project)
        try SetClipRoleCommand(
            clipIds: project.timeline.tracks[0].clips.map(\.id),
            roleId: dialogue.id
        ).apply(to: &project)

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        #expect(decoded.roles == [dialogue])
        #expect(decoded.timeline.tracks[0].clips.allSatisfy { $0.roleId == dialogue.id })
        #expect(decoded.schemaVersion == currentSchemaVersion)
    }

    @Test("a role-free project stays byte-identical (no roles/roleId keys)")
    func roleFreeByteIdentical() throws {
        let project = makeProject()
        let data = try JSONEncoder().encode(project)
        let text = String(decoding: data, as: UTF8.self)
        // ": "-suffixed so the project NAME (e.g. "roles") can't match.
        #expect(!text.contains("\"roles\":"))
        #expect(!text.contains("\"roleId\""))
    }

    @Test("a v8 document (no role fields) migrates through the chain to v9")
    func legacyMigration() throws {
        // Build a structurally-valid document by encoding a normal project
        // with the version pinned back to 8 — a real pre-roles file differs
        // only by schemaVersion and the absence of role keys (hand-written
        // JSON rots as the model gains required fields).
        var project = makeProject()
        project.schemaVersion = 8
        let data = try JSONEncoder().encode(project)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"roleId\""))

        var decoded = try JSONDecoder().decode(Project.self, from: data)
        #expect(decoded.roles.isEmpty)
        #expect(decoded.schemaVersion == 8)

        try ProjectMigrationRunner.migrate(&decoded)
        #expect(decoded.schemaVersion == currentSchemaVersion)
        #expect(decoded.roles.isEmpty)

        // Round-trips at v9 with no role payload added.
        let roundTripped = try JSONEncoder().encode(decoded)
        #expect(!String(decoding: roundTripped, as: UTF8.self).contains("\"roles\":"))
    }

    @Test("AddTimelineRoleCommand rejects duplicate names and ids")
    func addRoleGuards() throws {
        var project = makeProject()
        let music = TimelineRole.presets[1]
        try AddTimelineRoleCommand(role: music).apply(to: &project)

        #expect(throws: EditorCommandError.self) {
            try AddTimelineRoleCommand(role: TimelineRole(name: music.name, colorHex: "#000000"))
                .apply(to: &project)
        }
        #expect(throws: EditorCommandError.self) {
            try AddTimelineRoleCommand(role: TimelineRole(id: music.id, name: "Other Name", colorHex: "#000000"))
                .apply(to: &project)
        }
        #expect(project.roles.count == 1)
    }

    @Test("SetClipRoleCommand tags a batch and undoes via session snapshot")
    func assignAndUndo() async throws {
        let dialogue = TimelineRole.presets[0]
        let session = EditorSession(project: makeProject(clipCount: 3))
        try await session.dispatch(AddTimelineRoleCommand(role: dialogue))

        let clipIds = await session.snapshot().timeline.tracks[0].clips.map(\.id)
        try await session.dispatch(SetClipRoleCommand(clipIds: Array(clipIds.prefix(2)), roleId: dialogue.id))

        var after = await session.snapshot()
        #expect(after.timeline.tracks[0].clips[0].roleId == dialogue.id)
        #expect(after.timeline.tracks[0].clips[1].roleId == dialogue.id)
        #expect(after.timeline.tracks[0].clips[2].roleId == nil,
                "an unselected clip must keep its (nil) tag")

        try await session.undo()
        after = await session.snapshot()
        #expect(after.timeline.tracks[0].clips.allSatisfy { $0.roleId == nil })

        // Clear path: tag everything, then clear two.
        try await session.redo()
        try await session.dispatch(SetClipRoleCommand(clipIds: clipIds, roleId: dialogue.id))
        try await session.dispatch(SetClipRoleCommand(clipIds: Array(clipIds.prefix(2)), roleId: nil))
        after = await session.snapshot()
        #expect(after.timeline.tracks[0].clips[0].roleId == nil)
        #expect(after.timeline.tracks[0].clips[2].roleId == dialogue.id)
    }

    @Test("SetClipRoleCommand is atomic — unknown clip or role rejects before mutating")
    func atomicGuards() throws {
        var project = makeProject(clipCount: 2)
        let dialogue = TimelineRole.presets[0]
        try AddTimelineRoleCommand(role: dialogue).apply(to: &project)
        let realId = project.timeline.tracks[0].clips[0].id

        // Unknown role id: nothing changes.
        let before = project
        #expect(throws: EditorCommandError.self) {
            try SetClipRoleCommand(clipIds: [realId], roleId: UUID()).apply(to: &project)
        }
        #expect(project == before)

        // One unknown clip in the batch: NOTHING is applied (the known clip
        // keeps its nil tag).
        #expect(throws: EditorCommandError.self) {
            try SetClipRoleCommand(clipIds: [realId, UUID()], roleId: dialogue.id).apply(to: &project)
        }
        #expect(project == before)

        // Duplicate ids in the request are deduped, not "unknown".
        try SetClipRoleCommand(clipIds: [realId, realId], roleId: dialogue.id).apply(to: &project)
        #expect(project.timeline.tracks[0].clips[0].roleId == dialogue.id)
    }
}
