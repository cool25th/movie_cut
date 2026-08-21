import Foundation
import Testing
@testable import MovieCutCore

/// G-25 Inc 9 — `Track.isSolo` (audio solo) model/commands/schema: the
/// pre-v5 decode fallback, command application, and the v4→v5 migration
/// step. Engine honoring (preview/export) is exercised by the E2E paths;
/// graph-bus solo semantics live in AudioGraphRenderingTests.
@Suite("Track solo (G-25 Inc 9)")
struct TrackSoloTests {
    @Test("solo toggles through SetTrackPropertyCommand")
    func commandTogglesSolo() throws {
        var project = Project(name: "solo")
        let track = Track(kind: .audio, name: "BGM")
        project.timeline.tracks.append(track)
        #expect(project.timeline.tracks[0].isSolo == false)

        try SetTrackPropertyCommand(trackId: track.id, property: .isSolo(true)).apply(to: &project)
        #expect(project.timeline.tracks[0].isSolo == true)

        try SetTrackPropertyCommand(trackId: track.id, property: .isSolo(false)).apply(to: &project)
        #expect(project.timeline.tracks[0].isSolo == false)
    }

    @Test("pre-v5 track JSON (no isSolo key) decodes with solo off")
    func preV5DecodeFallsBack() throws {
        let legacy = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "kind": "audio",
          "name": "BGM",
          "isMuted": false,
          "isLocked": false,
          "isHidden": false,
          "zIndex": 0,
          "clips": []
        }
        """.data(using: .utf8)!
        let track = try JSONDecoder().decode(Track.self, from: legacy)
        #expect(track.isSolo == false)

        // Round-trip: the new field is always written once present.
        let encoded = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(Track.self, from: encoded)
        #expect(decoded.isSolo == false)
        #expect(String(data: encoded, encoding: .utf8)?.contains(#""isSolo""#) == true)
    }

    @Test("the migration chain reaches schema 5 with solo defaulting off")
    func migrationReachesV5() throws {
        var project = Project(name: "legacy", schemaVersion: 4)
        project.timeline.tracks.append(Track(kind: .audio, name: "BGM"))
        try ProjectMigrationRunner.migrate(&project)
        #expect(project.schemaVersion == currentSchemaVersion)
        #expect(currentSchemaVersion >= 5)
        #expect(project.timeline.tracks[0].isSolo == false)
    }
}
