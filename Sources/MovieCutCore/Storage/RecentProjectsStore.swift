import Foundation

/// A single entry in the recent-projects list (requirement 3).
///
/// The entry stores a security-scoped bookmark (`Data`) for the project file
/// URL rather than the URL itself, so the App Sandbox can re-reach the file
/// after a restart (requirement 3.5). Bookmark capture and scope lifecycle are
/// owned by `SecurityScopedAccess` in the App layer; this type is the persisted
/// value only — it never starts or stops a scope, so it does not duplicate that
/// lifecycle ownership. The App layer builds the bookmark via
/// `SecurityScopedAccess.makeBookmark(for:)` and hands the resulting `Data`
/// into the store via ``RecentProject/init(id:urlBookmark:name:modificationDate:duration:thumbnailPath:)``.
public struct RecentProject: Codable, Sendable, Equatable, Identifiable {
    /// Stable identifier derived from the project URL so upsert keys off the
    /// same file across saves. A re-save of the same project file updates the
    /// existing entry instead of appending a duplicate.
    public var id: UUID
    /// Security-scoped bookmark data for the project file URL. Opaque to this
    /// type; the App layer resolves and scopes it.
    public var urlBookmark: Data
    /// Last-known display name of the project.
    public var name: String
    /// Last modification time of the entry (refreshed on upsert).
    public var modificationDate: Date
    /// Project composition duration in seconds, for display in the home list.
    public var duration: Double
    /// Path to the recorded thumbnail. Optional because a fresh project may not
    /// have one yet. Stored as a path string (not URL) so it survives Codable
    /// round-trip regardless of file:// encoding quirks.
    public var thumbnailPath: String?

    public init(
        id: UUID,
        urlBookmark: Data,
        name: String,
        modificationDate: Date,
        duration: Double,
        thumbnailPath: String? = nil
    ) {
        self.id = id
        self.urlBookmark = urlBookmark
        self.name = name
        self.modificationDate = modificationDate
        self.duration = duration
        self.thumbnailPath = thumbnailPath
    }
}

/// File-backed persistence for the recent-projects list (requirement 3.3).
///
/// JSON under Application Support, written atomically. The store performs:
/// - **upsert** — inserting a new entry or updating the existing one keyed by
///   `id`, keeping the most-recent `modificationDate` on top;
/// - **sort** — entries ordered by `modificationDate` descending;
/// - **missing-file detection** — entries whose underlying project file can no
///   longer be reached (the bookmark no longer resolves to an existing file)
///   are flagged so the UI can mark them and offer removal (requirement 3.4).
///
/// The store does NOT touch `startAccessingSecurityScopedResource`. Outside the
/// sandbox (tests, non-sandboxed builds) `resolvingBookmarkData` reaches the
/// file by path directly, which is sufficient for the existence check. Inside
/// the sandbox the App layer opens a scope via `SecurityScopedAccess` before
/// opening the project; the existence check here is the same one that drives
/// the "missing" badge, not the access grant.
public actor RecentProjectsStore {
    private let storeURL: URL

    /// Default store location: Application Support/MovieCut/RecentProjects.json.
    public init() {
        self.storeURL = Self.defaultStoreURL()
    }

    /// Store with an explicit file URL (tests).
    public init(storeURL: URL) {
        self.storeURL = storeURL
    }

    /// Returns the list as currently persisted, sorted by `modificationDate`
    /// descending. A missing or unreadable file yields an empty list.
    public func load() -> [RecentProject] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RecentProject].self, from: data)) ?? []
    }

    /// Atomically writes `entries` to disk, then returns the sorted form. The
    /// caller normally passes the result of ``upsert(_:)`` or a filtered list.
    public func save(_ entries: [RecentProject]) throws {
        let sorted = Self.sorted(entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(sorted).write(to: storeURL, options: [.atomic])
    }

    /// Inserts `entry`, or updates the existing entry with the same `id` in
    /// place, persisting the result. Returns the new sorted list (most-recent
    /// first). This is the only mutation path the home screen uses on save
    /// (requirement 3.3).
    @discardableResult
    public func upsert(_ entry: RecentProject) throws -> [RecentProject] {
        var entries = load()
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        try save(entries)
        return Self.sorted(entries)
    }

    /// Removes the entry with the given id (e.g. user dismissed a missing
    /// project). No-op if absent. Returns the new sorted list.
    @discardableResult
    public func remove(_ id: UUID) throws -> [RecentProject] {
        var entries = load()
        entries.removeAll { $0.id == id }
        try save(entries)
        return Self.sorted(entries)
    }

    /// Partitions persisted entries by whether the project file they point at
    /// is still reachable (requirement 3.4). `missing` entries have a bookmark
    /// that either fails to resolve or resolves to a path that no longer
    /// exists; the UI marks these distinctly and offers removal via ``remove(_:)``.
    public func partitionedByReachability() -> (present: [RecentProject], missing: [RecentProject]) {
        var present: [RecentProject] = []
        var missing: [RecentProject] = []
        for entry in load() {
            if Self.projectFileExists(for: entry) {
                present.append(entry)
            } else {
                missing.append(entry)
            }
        }
        return (Self.sorted(present), Self.sorted(missing))
    }

    // MARK: - Internal helpers (testable via the actor's public surface)

    /// Orders entries by `modificationDate` descending (newest first), with id
    /// as a stable tiebreaker so equal timestamps never reorder between saves.
    public static func sorted(_ entries: [RecentProject]) -> [RecentProject] {
        entries.sorted { lhs, rhs in
            if lhs.modificationDate != rhs.modificationDate {
                return lhs.modificationDate > rhs.modificationDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Whether the project file an entry points at still exists on disk.
    ///
    /// Resolves the bookmark without a security scope (a no-op outside the
    /// sandbox, which is where tests run). A failure to resolve, or a resolved
    /// path whose file is gone, both count as missing.
    public static func projectFileExists(for entry: RecentProject) -> Bool {
        guard let url = resolveBookmarkData(entry.urlBookmark) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Resolves opaque bookmark data to a URL. Kept here (not in the App
    /// layer's `SecurityScopedAccess`) because the missing-file check is a pure
    /// existence test that does not start a scope; it must run in Core so the
    /// store is testable without App/UIKit. `SecurityScopedAccess` remains the
    /// sole owner of the access-pair lifecycle.
    private static func resolveBookmarkData(_ data: Data) -> URL? {
        guard !data.isEmpty else { return nil }

        // User-selected files carry security-scoped bookmarks, while files in
        // the app container may carry ordinary minimal bookmarks because no
        // persistent scope is required there. Support both persisted forms.
        // `withSecurityScope` is macOS-only; iOS resolves plain bookmarks.
        var options: [URL.BookmarkResolutionOptions] = []
        #if os(macOS)
        options.append(.withSecurityScope)
        #endif
        options.append([])
        for option in options {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: option,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        return nil
    }

    // MARK: - Default location

    /// Application Support/MovieCut/RecentProjects.json, creating the directory.
    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("MovieCut", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("RecentProjects.json")
    }

    /// Application Support/MovieCut/HomeThumbnails/, where save-time home
    /// thumbnails (one per recent entry) are written by the App layer. The
    /// directory is created lazily by the App layer on write; this returns the
    /// path only. Kept on the store so the location is co-located with
    /// ``defaultStoreURL()`` and survives a sandboxed relaunch identically.
    public static func defaultThumbnailsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("MovieCut", isDirectory: true)
            .appendingPathComponent("HomeThumbnails", isDirectory: true)
    }
}
