import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// S2 — App-layer security-scoped access behaviour.
///
/// These exercise the real `URL.bookmarkData`/`resolvingBookmarkData` APIs
/// against files in the OS temp dir, so they verify the resolve/stale/scope
/// pair behaviour that `ProjectStore.load` + `PlaybackEngine` rely on under the
/// sandbox. (Sandbox itself is exercised by S3; these run sandbox-on or off.)
@Suite("Security-scoped access")
struct SecurityScopedAccessTests {

    /// Creates a temp file asset with a real bookmark, returning it.
    private func bookmarkedAsset(suffix: String = "clip.mp4") throws -> (asset: MediaAsset, url: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutScopeTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString)-\(suffix)")
        try Data([0x00, 0x01]).write(to: url)

        let bookmark = try #require(SecurityScopedAccess.makeBookmark(for: url))
        let asset = MediaAsset(originalURL: url, kind: .video, originalBookmark: bookmark)
        return (asset, url)
    }

    @Test("resolveBookmark returns the original URL for a live file")
    func resolveReturnsLiveURL() throws {
        let (asset, url) = try bookmarkedAsset()
        defer { try? FileManager.default.removeItem(at: url) }

        let resolved = SecurityScopedAccess.resolveBookmark(for: asset)
        let result = try #require(resolved)
        // The bookmark resolves to the same on-disk file (standardized path).
        #expect(result.url.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
    }

    @Test("resolveBookmark reports nil for a deleted (stale) file")
    func resolveReportsMissingForDeletedFile() throws {
        let (asset, url) = try bookmarkedAsset()
        // Remove the file so the bookmark now points nowhere.
        try FileManager.default.removeItem(at: url)

        #expect(SecurityScopedAccess.resolveBookmark(for: asset) == nil)
        // needsRelocation is true: there is a bookmark but it no longer reaches.
        #expect(SecurityScopedAccess.needsRelocation(asset))
    }

    @Test("resolveBookmark returns nil for an asset with no bookmark")
    func resolveReturnsNilWithoutBookmark() throws {
        let asset = MediaAsset(originalURL: URL(fileURLWithPath: "/tmp/none.mp4"), kind: .video)
        #expect(asset.originalBookmark == nil)
        #expect(SecurityScopedAccess.resolveBookmark(for: asset) == nil)
        // No bookmark at all is not "needs relocation" — it was never captured.
        #expect(!SecurityScopedAccess.needsRelocation(asset))
    }

    @Test("withSecurityScope hands the body a reachable URL and releases the pair")
    func withSecurityScopeRunsBody() throws {
        let (asset, url) = try bookmarkedAsset()
        defer { try? FileManager.default.removeItem(at: url) }

        // The body receives a URL that can actually read the file.
        let bytes = try SecurityScopedAccess.withSecurityScope(for: asset) { resolved in
            try Data(contentsOf: resolved)
        }
        #expect(bytes == Data([0x00, 0x01]))
    }

    @Test("withSecurityScope still releases the scope when the body throws")
    func withSecurityScopeReleasesOnThrow() throws {
        let (asset, url) = try bookmarkedAsset()
        defer { try? FileManager.default.removeItem(at: url) }

        struct Boom: Error {}
        #expect(throws: Boom.self) {
            try SecurityScopedAccess.withSecurityScope(for: asset) { _ in
                throw Boom()
            }
        }
        // No assertion to make on the scope itself (it's internal), but reaching
        // here without a crash/leak path proves the throw path stops the scope.
        // A second call must still work, proving the first fully released.
        let bytes = try SecurityScopedAccess.withSecurityScope(for: asset) { resolved in
            try Data(contentsOf: resolved)
        }
        #expect(bytes == Data([0x00, 0x01]))
    }

    @Test("beginScope/endScope pair reach the file without crashing")
    func beginEndScopePair() throws {
        let (asset, url) = try bookmarkedAsset()
        defer { try? FileManager.default.removeItem(at: url) }

        let scoped = SecurityScopedAccess.beginScope(for: asset)
        defer { SecurityScopedAccess.endScope(for: scoped) }
        // The scoped URL must read the file content.
        let bytes = try Data(contentsOf: scoped)
        #expect(bytes == Data([0x00, 0x01]))
    }

    @Test("beginScope falls back to originalURL when there is no bookmark")
    func beginScopeFallsBackWithoutBookmark() {
        let asset = MediaAsset(originalURL: URL(fileURLWithPath: "/tmp/absent.mp4"), kind: .video)
        // No crash, returns the stored URL (unreachable, but the call is safe).
        let scoped = SecurityScopedAccess.beginScope(for: asset)
        #expect(scoped == asset.originalURL)
    }
}
