import Foundation
import Testing
@testable import MovieCutCore

/// Requirement 3 — recent-projects store behaviour.
///
/// These exercise the real bookmark APIs (`URL.bookmarkData` /
/// `URL(resolvingBookmarkData:)`) and the real filesystem against files in the
/// OS temp dir, then assert on the store's observable behaviour (persistence,
/// upsert, sort, missing-file partitioning). No source-string assertions: each
/// test proves a behaviour by driving the store and reading back its output.
@Suite("RecentProjectsStore")
struct RecentProjectsStoreTests {

    // MARK: - Helpers

    /// Per-test store file under a unique temp directory, cleaned up on exit.
    /// Returns the store and its on-disk URL so a "relaunched" store can be
    /// pointed at the same path.
    private func makeStore() -> (store: RecentProjectsStore, storeURL: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moviecut-recent-\(UUID().uuidString)", isDirectory: true)
        let url = dir.appendingPathComponent("RecentProjects.json")
        return (RecentProjectsStore(storeURL: url), url, dir)
    }

    /// Creates a real temp file and returns a real security-scoped bookmark for
    /// it plus the file URL for lifecycle control in the test.
    ///
    /// The bookmark uses `[.withSecurityScope]` alone. The production App layer's
    /// `SecurityScopedAccess.makeBookmark` adds `.minimalBookmark` too; that pair
    /// is only valid *under* the sandbox, and these Core tests run via SwiftPM
    /// (no sandbox) where the two flags are mutually exclusive. `.withSecurityScope`
    /// alone produces valid security-scoped bookmark data that the store resolves
    /// identically — the same resolution path the real app uses at runtime — so
    /// the existence/upsert/sort behaviours under test are exercised faithfully.
    private func bookmarkedFile(name: String) throws -> (bookmark: Data, url: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("moviecut-recent-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data([0x4D, 0x43, 0x50, 0x4A]).write(to: url)  // "MCPJ" placeholder bytes
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return (bookmark, url)
    }

    private func entry(
        id: UUID,
        bookmark: Data,
        name: String,
        modified: Date,
        duration: Double,
        thumbnail: String? = nil
    ) -> RecentProject {
        RecentProject(
            id: id,
            urlBookmark: bookmark,
            name: name,
            modificationDate: modified,
            duration: duration,
            thumbnailPath: thumbnail
        )
    }

    // MARK: - Persistence round-trip

    @Test("upsert persists across a fresh store instance (restart simulation)")
    func upsertPersistsAcrossInstances() async throws {
        let (store, storeURL, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bookmark, url) = try bookmarkedFile(name: "a.moviecut")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        let inserted = try await store.upsert(
            entry(id: id, bookmark: bookmark, name: "A", modified: Date(timeIntervalSince1970: 1_000), duration: 5)
        )
        #expect(inserted.count == 1)
        #expect(inserted.first?.name == "A")

        // A brand-new store pointed at the same file models a relaunch: the
        // list must survive the round-trip through JSON on disk.
        let relaunched = RecentProjectsStore(storeURL: storeURL)
        let reloaded = await relaunched.load()
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.id == id)
        #expect(reloaded.first?.name == "A")
        #expect(reloaded.first?.duration == 5)
        // Bookmark data survives verbatim so the App layer can still resolve it.
        #expect(reloaded.first?.urlBookmark == bookmark)
    }

    @Test("a missing or unreadable store file yields an empty list")
    func missingFileYieldsEmpty() async throws {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        // No write yet — load must not throw and must be empty.
        #expect(await store.load() == [])
    }

    // MARK: - Upsert semantics

    @Test("upsert with an existing id updates in place instead of duplicating")
    func upsertUpdatesInPlace() async throws {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bookmark, url) = try bookmarkedFile(name: "b.moviecut")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()

        _ = try await store.upsert(
            entry(id: id, bookmark: bookmark, name: "Before", modified: Date(timeIntervalSince1970: 1_000), duration: 1)
        )
        let afterSecond = try await store.upsert(
            entry(id: id, bookmark: bookmark, name: "After", modified: Date(timeIntervalSince1970: 2_000), duration: 9)
        )

        // Exactly one entry for this id, carrying the latest values.
        #expect(afterSecond.count == 1)
        #expect(afterSecond.first?.name == "After")
        #expect(afterSecond.first?.duration == 9)
        #expect(afterSecond.first?.modificationDate == Date(timeIntervalSince1970: 2_000))
    }

    @Test("upsert of distinct ids keeps all entries")
    func upsertKeepsDistinct() async throws {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bm1, u1) = try bookmarkedFile(name: "c1.moviecut")
        let (bm2, u2) = try bookmarkedFile(name: "c2.moviecut")
        defer { try? FileManager.default.removeItem(at: u1) }
        defer { try? FileManager.default.removeItem(at: u2) }

        _ = try await store.upsert(entry(id: UUID(), bookmark: bm1, name: "C1", modified: Date(timeIntervalSince1970: 1_000), duration: 2))
        _ = try await store.upsert(entry(id: UUID(), bookmark: bm2, name: "C2", modified: Date(timeIntervalSince1970: 2_000), duration: 3))

        #expect(await store.load().count == 2)
    }

    @Test("remove deletes only the matching id")
    func removeTargetsOneId() async throws {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bm1, u1) = try bookmarkedFile(name: "d1.moviecut")
        let (bm2, u2) = try bookmarkedFile(name: "d2.moviecut")
        defer { try? FileManager.default.removeItem(at: u1) }
        defer { try? FileManager.default.removeItem(at: u2) }
        let id1 = UUID()
        let id2 = UUID()

        _ = try await store.upsert(entry(id: id1, bookmark: bm1, name: "D1", modified: Date(timeIntervalSince1970: 1_000), duration: 1))
        _ = try await store.upsert(entry(id: id2, bookmark: bm2, name: "D2", modified: Date(timeIntervalSince1970: 2_000), duration: 1))

        let afterRemove = try await store.remove(id1)
        #expect(afterRemove.count == 1)
        #expect(afterRemove.first?.id == id2)
    }

    // MARK: - Sort

    @Test("entries sort newest-first by modificationDate")
    func sortsNewestFirst() async throws {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bm1, u1) = try bookmarkedFile(name: "s1.moviecut")
        let (bm2, u2) = try bookmarkedFile(name: "s2.moviecut")
        let (bm3, u3) = try bookmarkedFile(name: "s3.moviecut")
        defer { try? FileManager.default.removeItem(at: u1) }
        defer { try? FileManager.default.removeItem(at: u2) }
        defer { try? FileManager.default.removeItem(at: u3) }

        // Insert in a deliberately scrambled time order.
        _ = try await store.upsert(entry(id: UUID(), bookmark: bm1, name: "oldest", modified: Date(timeIntervalSince1970: 1_000), duration: 1))
        _ = try await store.upsert(entry(id: UUID(), bookmark: bm3, name: "newest", modified: Date(timeIntervalSince1970: 3_000), duration: 1))
        _ = try await store.upsert(entry(id: UUID(), bookmark: bm2, name: "middle", modified: Date(timeIntervalSince1970: 2_000), duration: 1))

        let ordered = await store.load().map(\.name)
        #expect(ordered == ["newest", "middle", "oldest"])
    }

    @Test("equal modificationDates keep a deterministic order across saves")
    func sortIsStableAcrossSaves() {
        // Two entries that share a timestamp must not swap relative to each
        // other between independent sorts (id is the stable tiebreaker).
        let idA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let idB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let unsorted = [
            RecentProject(id: idB, urlBookmark: Data([1]), name: "B", modificationDate: Date(timeIntervalSince1970: 5_000), duration: 1),
            RecentProject(id: idA, urlBookmark: Data([2]), name: "A", modificationDate: Date(timeIntervalSince1970: 5_000), duration: 1),
        ]
        let first = RecentProjectsStore.sorted(unsorted).map(\.name)
        let second = RecentProjectsStore.sorted(unsorted.reversed()).map(\.name)
        #expect(first == second)
        #expect(first == ["A", "B"])
    }

    // MARK: - Missing-file detection

    @Test("partition reports a present file as present")
    func partitionFindsPresentFile() async throws {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bookmark, url) = try bookmarkedFile(name: "p.moviecut")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await store.upsert(entry(id: UUID(), bookmark: bookmark, name: "Present", modified: Date(timeIntervalSince1970: 1_000), duration: 1))

        let (present, missing) = await store.partitionedByReachability()
        #expect(present.count == 1)
        #expect(present.first?.name == "Present")
        #expect(missing.isEmpty)
    }

    @Test("partition flags an entry whose file was deleted as missing")
    func partitionFlagsDeletedFile() async throws {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bookmark, url) = try bookmarkedFile(name: "gone.moviecut")
        // Delete the underlying file AFTER capturing the bookmark so the entry
        // now points at nothing — the real "user moved/deleted it" condition.
        try FileManager.default.removeItem(at: url)
        _ = try await store.upsert(entry(id: UUID(), bookmark: bookmark, name: "Gone", modified: Date(timeIntervalSince1970: 1_000), duration: 1))

        let (present, missing) = await store.partitionedByReachability()
        #expect(present.isEmpty)
        #expect(missing.count == 1)
        #expect(missing.first?.name == "Gone")
    }

    @Test("partition separates mixed present and missing entries")
    func partitionSplitsMixed() async throws {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bmLive, urlLive) = try bookmarkedFile(name: "live.moviecut")
        let (bmDead, urlDead) = try bookmarkedFile(name: "dead.moviecut")
        defer { try? FileManager.default.removeItem(at: urlLive) }
        try FileManager.default.removeItem(at: urlDead)

        _ = try await store.upsert(entry(id: UUID(), bookmark: bmDead, name: "dead", modified: Date(timeIntervalSince1970: 2_000), duration: 1))
        _ = try await store.upsert(entry(id: UUID(), bookmark: bmLive, name: "live", modified: Date(timeIntervalSince1970: 1_000), duration: 1))

        let (present, missing) = await store.partitionedByReachability()
        #expect(present.map(\.name) == ["live"])
        #expect(missing.map(\.name) == ["dead"])
    }

    @Test("a flagged-missing entry can be removed, leaving only reachable ones")
    func missingEntryCanBeRemoved() async throws {
        let (store, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bmLive, urlLive) = try bookmarkedFile(name: "keep.moviecut")
        let (bmDead, urlDead) = try bookmarkedFile(name: "drop.moviecut")
        defer { try? FileManager.default.removeItem(at: urlLive) }
        try FileManager.default.removeItem(at: urlDead)

        let liveId = UUID()
        let deadId = UUID()
        _ = try await store.upsert(entry(id: liveId, bookmark: bmLive, name: "keep", modified: Date(timeIntervalSince1970: 1_000), duration: 1))
        _ = try await store.upsert(entry(id: deadId, bookmark: bmDead, name: "drop", modified: Date(timeIntervalSince1970: 2_000), duration: 1))

        let (_, missing) = await store.partitionedByReachability()
        #expect(missing.map(\.id) == [deadId])

        let remaining = try await store.remove(deadId)
        #expect(remaining.map(\.id) == [liveId])

        // After removal, the partition is clean.
        let (present, stillMissing) = await store.partitionedByReachability()
        #expect(present.count == 1)
        #expect(stillMissing.isEmpty)
    }
}
