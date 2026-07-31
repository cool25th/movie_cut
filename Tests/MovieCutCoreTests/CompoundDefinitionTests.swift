import Foundation
import Testing
@testable import MovieCutCore

/// Task 5.7 — CompoundDefinition model + serialization (Requirement 7.6).
///
/// These pin the model and on-disk contracts for Inc 1 compound clips:
///   - `Project.compounds` and `Clip.compoundId` decode leniently so a
///     compound-free legacy fixture still loads (and round-trips byte-clean);
///   - a round-trip with compounds is lossless;
///   - a child clip carrying a `compoundId` (nesting) is rejected explicitly
///     by load-time validation;
///   - a container clip whose `compoundId` has no definition (broken ref) is
///     rejected explicitly by load-time validation;
///   - `currentSchemaVersion` is unchanged (task 6 owns the bump).
@Suite("CompoundDefinition (Task 5.7)")
struct CompoundDefinitionTests {

    // MARK: - Fixture path (committed under Tests/Fixtures)

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }

    // MARK: - Schema (task 6.1 consolidated the bump)

    @Test("compound fields ship at the current schema version (task 6.1 bump)")
    func schemaVersionCarriesCompoundFields() {
        // Task 6.1 bumped `currentSchemaVersion` once for the batched additive
        // fields (blendMode / previewQuality / compounds). The compound feature
        // is part of that batch, so current must be 4 and the chain reaches it.
        #expect(currentSchemaVersion == 4)
        #expect(ProjectSchema.migrations.last?.version == currentSchemaVersion)
    }

    // MARK: - Defaults / lenient decode

    @Test("a fresh project has no compounds and clips default to a nil compoundId")
    func freshProjectDefaultsAreEmpty() {
        let project = Project(name: "Untitled")
        #expect(project.compounds.isEmpty)
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        #expect(clip.compoundId == nil)
    }

    @Test("a compound-free legacy project fixture loads through ProjectStore")
    func compoundFreeLegacyFixtureLoads() async throws {
        // Real decode + migration + compound validation, not a string check.
        let store = ProjectStore(autosaveDirectory: nil)
        let project = try await store.load(from: fixture("project_compound_free_v3.moviecut"))

        #expect(project.schemaVersion == currentSchemaVersion)
        #expect(project.compounds.isEmpty)
        // A compound-free project must pass structural validation.
        try project.validateCompounds()
    }

    @Test("a compound-free project omits the compounds key and round-trips byte-clean")
    func compoundFreeRoundTripsWithoutKey() throws {
        var project = Project(name: "No compounds")
        // Encode with the same formatting as ProjectStore.save so the on-disk
        // shape is the one that matters.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("\"compounds\""))

        let decoded = try JSONDecoder().decode(Project.self, from: data)
        #expect(decoded.compounds.isEmpty)
        #expect(decoded == project)
    }

    // MARK: - Lossless round-trip with compounds

    @Test("a project with a compound round-trips losslessly")
    func projectWithCompoundRoundTripsLosslessly() throws {
        let child = Clip(
            id: UUID(uuidString: "55555555-0000-4000-8000-000000000001")!,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        let compound = CompoundDefinition(
            id: UUID(uuidString: "55555555-0000-4000-8000-000000000099")!,
            name: "Intro",
            childClips: [child]
        )
        let container = Clip(
            id: UUID(uuidString: "55555555-0000-4000-8000-000000000002")!,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 10, duration: 2),
            compoundId: compound.id
        )
        var track = Track(kind: .video, name: "V1", zIndex: 0, clips: [container])
        track.isLocked = false
        let original = Project(
            name: "With compound",
            timeline: Timeline(tracks: [track]),
            compounds: [compound]
        )

        // Round-trip through encode → decode.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(Project.self, from: data)

        #expect(decoded.compounds == [compound])
        let decodedContainer = decoded.timeline.tracks[0].clips[0]
        #expect(decodedContainer.compoundId == compound.id)
        // Structural validation must pass on a well-formed project.
        try decoded.validateCompounds()
        // The decoded project equals the original (lossless).
        #expect(decoded == original)
    }

    @Test("a plain clip omits the compoundId key from its JSON")
    func plainClipOmitsCompoundIdKey() throws {
        // Requirement 7.6: encode only when set, so a plain clip stays
        // byte-identical to its pre-feature JSON.
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        #expect(clip.compoundId == nil)

        let data = try JSONEncoder().encode(clip)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("compoundId"))
    }

    // MARK: - No-nesting validation at load

    @Test("a project whose compound child itself carries a compoundId errors at load")
    func nestedCompoundRejectedAtLoad() async throws {
        // A child clip carrying a compoundId must be rejected (Inc 1 forbids
        // nesting). Build a project JSON that encodes that broken state, write
        // it to a temp file, and load it through the real ProjectStore path.
        let nestedChild = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2),
            compoundId: UUID(uuidString: "66666666-0000-4000-8000-0000000000aa")!
        )
        let compound = CompoundDefinition(
            name: "Nested-broken",
            childClips: [nestedChild]
        )
        let project = Project(
            name: "Nested-broken",
            compounds: [compound]
        )

        let url = try await writeFixture("compound_nested.moviecut", project: project)
        let store = ProjectStore(autosaveDirectory: nil)

        await #expect(throws: CompoundValidationError.self) {
            _ = try await store.load(from: url)
        }
    }

    @Test("validateCompounds raises the nesting error directly for an in-memory project")
    func validateCompoundsRejectsNestingInMemory() throws {
        let nestedChild = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2),
            compoundId: UUID(uuidString: "66666666-0000-4000-8000-0000000000bb")!
        )
        let compound = CompoundDefinition(
            id: UUID(uuidString: "66666666-0000-4000-8000-0000000000cc")!,
            name: "Bad",
            childClips: [nestedChild]
        )
        let project = Project(name: "Bad", compounds: [compound])

        #expect(throws: CompoundValidationError.self) {
            try project.validateCompounds()
        }
    }

    // MARK: - Broken reference validation at load

    @Test("a project whose container references a missing compound errors at load")
    func danglingCompoundReferenceRejectedAtLoad() async throws {
        let missingCompoundId = UUID(uuidString: "77777777-0000-4000-8000-0000000000aa")!
        let container = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2),
            compoundId: missingCompoundId // no matching definition
        )
        var track = Track(kind: .video, name: "V1", zIndex: 0, clips: [container])
        track.isLocked = false
        let project = Project(
            name: "Dangling",
            timeline: Timeline(tracks: [track]),
            compounds: [] // no definitions at all
        )

        let url = try await writeFixture("compound_dangling.moviecut", project: project)
        let store = ProjectStore(autosaveDirectory: nil)

        await #expect(throws: CompoundValidationError.self) {
            _ = try await store.load(from: url)
        }
    }

    @Test("validateCompounds raises the dangling error directly for an in-memory project")
    func validateCompoundsRejectsDanglingInMemory() throws {
        let missingCompoundId = UUID(uuidString: "77777777-0000-4000-8000-0000000000bb")!
        let container = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2),
            compoundId: missingCompoundId
        )
        var track = Track(kind: .video, name: "V1", zIndex: 0, clips: [container])
        track.isLocked = false
        let project = Project(
            name: "Dangling",
            timeline: Timeline(tracks: [track]),
            compounds: []
        )

        #expect(throws: CompoundValidationError.self) {
            try project.validateCompounds()
        }
    }

    // MARK: - Error descriptions are user-facing

    @Test("dangling and nesting errors carry a localized description")
    func errorsAreLocalized() {
        let dangling = CompoundValidationError.danglingCompoundReference(
            clipId: UUID(uuidString: "77777777-0000-4000-8000-000000000001")!,
            compoundId: UUID(uuidString: "77777777-0000-4000-8000-000000000002")!
        )
        let nesting = CompoundValidationError.nestedCompoundForbidden(
            parentCompoundId: UUID(uuidString: "66666666-0000-4000-8000-000000000003")!,
            childClipId: UUID(uuidString: "66666666-0000-4000-8000-000000000004")!
        )
        #expect(dangling.errorDescription?.contains("compound") == true)
        #expect(nesting.errorDescription?.contains("Nested") == true)
    }

    // MARK: - Helpers

    /// Writes a project to a temp file using the same encoder as ProjectStore,
    /// returning the URL. Used to feed broken-shape fixtures through the real
    /// `ProjectStore.load` path (decode + migrate + validate).
    private func writeFixture(_ name: String, project: Project) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompoundDefinitionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: url, options: [.atomic])
        return url
    }
}
