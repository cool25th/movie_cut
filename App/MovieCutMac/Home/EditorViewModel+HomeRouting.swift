import CryptoKit
import Foundation
import MovieCutCore

/// Home-screen entry points for ``EditorViewModel`` (task 4.4).
///
/// These exist as an extension so `EditorViewModel.swift` itself is not modified
/// (spec constraint: new VM entry points go in NEW extension files). They expose
/// only what the home/stage routing needs:
/// - the current project's duration (for the home card and the recent entry);
/// - a way to **record the current project into the recent list at save time**
///   (requirement 3.3), capturing a thumbnail via the existing
///   ``ThumbnailGenerator`` (requirement 3.1 / design §4.2 "썸네일. 기존
///   ThumbnailGenerator로 저장 시점에 1장 기록").
///
/// The recording path does not duplicate the bookmark lifecycle:
/// `SecurityScopedAccess.makeBookmark(for:)` is the single owner, and
/// `RecentProjectsStore` is the single owner of persistence. This extension is
/// the glue that reads current project state and hands the resulting
/// ``RecentProject`` to the store.
extension EditorViewModel {
    /// The current project's composition duration, for the home card and for
    /// the recent-list entry recorded at save time.
    var homeCardDuration: Double {
        currentProject.timeline.duration
    }

    /// Records the current project into the recent list (requirement 3.3).
    ///
    /// `SecurityScopedAccess.makeBookmark(for:)`, renders a single thumbnail
    /// at save time via the existing `ThumbnailGenerator` (design §4.2), and
    /// upserts the entry. User-selected files retain security scope; files in
    /// the app container use the bookmark helper's regular-bookmark fallback.
    ///
    /// - Parameters:
    ///   - store: The recent-projects store to upsert into.
    ///   - projectURL: The URL the project was saved to. A stable id is derived
    ///     from this URL so re-saves update the existing entry in place rather
    ///     than appending a duplicate.
    func recordCurrentProjectToRecent(
        _ store: RecentProjectsStore,
        savedTo projectURL: URL
    ) async {
        // Bookmark capture is the single owner's job; the store only persists
        // the opaque Data.
        let bookmark = SecurityScopedAccess.makeBookmark(for: projectURL)
        let thumbnailPath = Self.captureHomeThumbnail(for: currentProject)
        let id = Self.recentProjectID(for: projectURL)

        let entry = RecentProject(
            id: id,
            urlBookmark: bookmark ?? Data(),
            name: currentProject.name,
            modificationDate: Date(),
            duration: homeCardDuration,
            thumbnailPath: thumbnailPath
        )

        try? await store.upsert(entry)
    }

    /// Renders one thumbnail for the home card from the project's first usable
    /// media asset, writing it under Application Support and returning the path.
    /// Returns nil for a project with no suitable media (a fresh project). Uses
    /// the existing `ThumbnailGenerator` (design §4.2) without the render cache
    /// — a save-time thumbnail is a single generation, not a hot path.
    private static func captureHomeThumbnail(for project: Project) -> String? {
        guard let asset = project.mediaLibrary.assets.values.first(where: {
            ($0.kind == .video || $0.kind == .image)
                && FileManager.default.fileExists(atPath: $0.originalURL.path)
        }) else {
            return nil
        }

        guard let data = ThumbnailGenerator.generate(
            for: asset,
            at: project.timeline.duration / 2,
            size: ThumbnailGenerator.defaultSize
        ) else {
            return nil
        }

        let dir = RecentProjectsStore.defaultThumbnailsDirectory()
        let url = dir.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            return url.path
        } catch {
            return nil
        }
    }

    /// Derives a stable id from a project file URL so the same file always maps
    /// to the same recent entry across saves. Uses the standardized absolute
    /// path so symlink/saved-again variants collapse to one entry.
    private static func recentProjectID(for url: URL) -> UUID {
        let key = url.resolvingSymlinksInPath().path
        // Name-based UUID (SHA-256 → first 128 bits, with RFC 4122 v5
        // version/variant bits set). We rely only on stability across runs, not
        // on the version, but a well-formed UUID avoids future surprises.
        let digest = SHA256.hash(data: Data(key.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
