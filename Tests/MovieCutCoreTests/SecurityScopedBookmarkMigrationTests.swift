import Foundation
import Testing
@testable import MovieCutCore

/// S2 — security-scoped bookmark persistence.
///
/// Core-layer tests verify the *executed artifact*: a bookmark field survives a
/// JSON round trip, the v1→v2 migration runs through the S1 chain, and a
/// project package strips machine-local bookmarks so they never travel between
/// devices. App-layer resolve/stale/scope behaviour is covered by the Mac test
/// target. See S2 of `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`.
@Suite("Security-scoped bookmark persistence (core)")
struct SecurityScopedBookmarkMigrationTests {

    @Test("MediaAsset bookmark survives a JSON round trip")
    func bookmarkRoundTripsThroughJSON() throws {
        let bookmark = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let asset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/clip.mp4"),
            kind: .video,
            originalBookmark: bookmark
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MediaAsset.self, from: encoder.encode(asset))

        #expect(decoded.originalBookmark == bookmark)
        #expect(decoded.originalURL == asset.originalURL)
    }

    @Test("A v1 asset (no bookmark key) decodes with a nil bookmark, not an error")
    func missingBookmarkKeyDecodesAsNil() throws {
        // v1 projects have no originalBookmark key at all. Decoding must not
        // throw, and the field must be nil so the app can re-create one.
        let v1JSON = """
        {
          "id": "10000000-0000-4000-8000-000000000001",
          "originalURL": "/tmp/legacy.mp4",
          "kind": "video",
          "metadata": {}
        }
        """.data(using: .utf8)!

        let asset = try JSONDecoder().decode(MediaAsset.self, from: v1JSON)
        #expect(asset.originalBookmark == nil)
        #expect(asset.kind == .video)
    }

    @Test("A schema v1 project migrates to v2 through the registered chain")
    func v1ProjectMigratesToV2() throws {
        var project = Project(name: "legacy", schemaVersion: 1)
        #expect(project.schemaVersion == 1)

        // The production runner uses the registered chain (which now includes
        // AddSecurityScopedBookmarkMigration). This is the real load() path.
        try ProjectMigrationRunner.migrate(&project)

        #expect(project.schemaVersion == currentSchemaVersion)
        // The bookmark migration is the v1→v2 step; the chain must reach at
        // least v2 (later migrators may run it further toward current).
        #expect(currentSchemaVersion >= 2)
    }

    @Test("The bookmark migration is the v1→v2 step and is registered")
    func bookmarkMigrationRegistered() throws {
        let migrators = ProjectSchema.migrations
        #expect(migrators.count >= 1)
        let first = try #require(migrators.first)
        #expect(first.version == 2)
        #expect(first is AddSecurityScopedBookmarkMigration)
    }

    @Test("The committed v1 fixture loads and migrates to v2 with nil bookmarks")
    func v1FixtureMigratesToV2() async throws {
        // DoD: a real v1 project file must still load after the bookmark field
        // and migration were added. The fixture has empty assets, so every
        // (zero) bookmarks are nil — a valid post-v2 state.
        let store = ProjectStore(autosaveDirectory: nil)
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/project_v1.moviecut")
        let project = try await store.load(from: url)

        #expect(project.schemaVersion == currentSchemaVersion)
        #expect(project.mediaLibrary.assets.isEmpty)
    }

    @Test("A project package export strips machine-local bookmarks")
    func packageExportStripsBookmarks() throws {
        // Security-scoped bookmarks are device/account-local: shipping one in a
        // .mctemplate would only mislead the loader on another machine. The
        // package writer must drop them, the same way it drops proxies.
        let bookmark = Data([0x01, 0x02, 0x03])
        var asset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            kind: .video
        )
        asset.originalBookmark = bookmark

        var library = MediaLibrary()
        library.assets[asset.id] = asset
        let project = Project(name: "pkg", schemaVersion: currentSchemaVersion, mediaLibrary: library)

        let packageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutBookmarkPkgTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        let packageURL = packageDir.appendingPathComponent("pkg.mctemplate")

        // ProjectPackage.export copies media by path; the source need not exist,
        // it just won't be copied. We only assert the bookmark is stripped.
        _ = try ProjectPackage.export(project, to: packageURL)
        let loaded = try ProjectPackage.load(from: packageURL)

        let repackaged = try #require(loaded.mediaLibrary.assets.values.first)
        #expect(repackaged.originalBookmark == nil)
        #expect(repackaged.proxy == nil)
    }
}
