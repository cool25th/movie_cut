import Foundation
import MovieCutCore

/// Resolves and grants App Sandbox access to a file URL via its
/// security-scoped bookmark.
///
/// Under App Sandbox, a URL picked through `NSOpenPanel` is only reachable for
/// the lifetime of that URL object unless a security-scoped bookmark is captured
/// and later resolved. This type is the single owner of that lifecycle: it
/// resolves bookmarks (detecting stale ones), and pairs every
/// `startAccessingSecurityScopedResource` with a matching `stopAccessing` via
/// `withSecurityScope`. (S2 of `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`.)
///
/// **Single owner of the bookmark lifecycle.** The URL-level overloads
/// (`resolveBookmark(for:)`, `beginScope(for:bookmark:)`, `endScope(for:)`,
/// `withSecurityScope(for:bookmark:)`) are the sole implementation; the
/// `MediaAsset` overloads only extract the asset's `originalURL` /
/// `originalBookmark` and forward to them. The bookmark resolution path is
/// implemented exactly once (requirement 3.5).
public enum SecurityScopedAccess {

    /// Resolves a bookmark to a URL, reporting staleness instead of crashing.
    ///
    /// This is the single implementation of bookmark resolution; every other
    /// overload (and the internal `ScopedAccess` helper) routes through it. A
    /// security-scoped bookmark carries the path it was captured for, so the
    /// bookmark alone determines the resolved URL — no source URL is needed.
    ///
    /// - Parameter bookmark: The security-scoped bookmark data, or `nil`.
    /// - Returns: The resolved URL and whether the bookmark was stale (the file
    ///   moved). `nil` when there is no bookmark, the data cannot be resolved,
    ///   or the file does not exist at the resolved path — all cases the caller
    ///   should treat as "re-prompt the user to relocate the media".
    public static func resolveBookmark(for bookmark: Data?) -> (url: URL, isStale: Bool)? {
        guard let bookmark, !bookmark.isEmpty else { return nil }

        // Prefer security-scoped resolution for user-selected files. Container-
        // internal files need no scope and may only carry a regular bookmark,
        // so fall back to plain resolution when the scoped form is rejected.
        for options in [URL.BookmarkResolutionOptions.withSecurityScope, []] {
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }
            guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
            return (resolved, isStale)
        }

        return nil
    }

    /// Asset overload: resolves the asset's bookmark. Delegates to the URL-level
    /// `resolveBookmark(for:)`; no bookmark logic is duplicated.
    public static func resolveBookmark(for asset: MediaAsset) -> (url: URL, isStale: Bool)? {
        resolveBookmark(for: asset.originalBookmark)
    }

    /// Runs `body` against the file inside a security scope, started from the
    /// bookmark if one is usable, otherwise against the plain `url`.
    ///
    /// This is the single implementation of the scoped-pair lifecycle. The scope
    /// is started before `body` and stopped on every exit path (return or
    /// throw), so callers cannot leak the access pair. When a usable bookmark is
    /// present it is resolved and started; otherwise `body` runs against `url`
    /// (valid outside the sandbox, and lets non-sandboxed builds and tests
    /// proceed).
    public static func withSecurityScope<T>(
        for url: URL,
        bookmark: Data?,
        body: (URL) throws -> T
    ) throws -> T {
        let access = ScopedAccess(url: url, bookmark: bookmark)
        return try body(access.url)
    }

    /// Async URL-level overload of `withSecurityScope(for:bookmark:body:)`.
    public static func withSecurityScope<T>(
        for url: URL,
        bookmark: Data?,
        body: (URL) async throws -> T
    ) async throws -> T {
        let access = ScopedAccess(url: url, bookmark: bookmark)
        return try await body(access.url)
    }

    /// Asset overload: delegates to the URL-level
    /// `withSecurityScope(for:bookmark:body:)`.
    public static func withSecurityScope<T>(
        for asset: MediaAsset,
        body: (URL) throws -> T
    ) throws -> T {
        try withSecurityScope(
            for: asset.originalURL,
            bookmark: asset.originalBookmark,
            body: body
        )
    }

    /// Async asset overload: delegates to the URL-level
    /// `withSecurityScope(for:bookmark:body:)`.
    public static func withSecurityScope<T>(
        for asset: MediaAsset,
        body: (URL) async throws -> T
    ) async throws -> T {
        try await withSecurityScope(
            for: asset.originalURL,
            bookmark: asset.originalBookmark,
            body: body
        )
    }

    /// Whether a file needs the user to relocate it: there is a bookmark but it
    /// no longer resolves to an existing file. No bookmark at all is not
    /// "needs relocation" — one was never captured.
    ///
    /// Single implementation of this predicate. The decision is driven entirely
    /// by the bookmark, so the URL-level overload takes the bookmark alone.
    public static func needsRelocation(for bookmark: Data?) -> Bool {
        resolveBookmark(for: bookmark) == nil && bookmark != nil
    }

    /// Asset overload: delegates to the URL-level `needsRelocation(for:)`.
    public static func needsRelocation(_ asset: MediaAsset) -> Bool {
        needsRelocation(for: asset.originalBookmark)
    }

    /// Builds a persistent bookmark for `url`. User-selected files prefer a
    /// security-scoped bookmark; container-internal files fall back to a regular
    /// minimal bookmark because they require no scope but still need a durable
    /// path for the recent-projects list.
    public static func makeBookmark(for url: URL) -> Data? {
        if let scoped = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return scoped
        }

        return try? url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves the bookmark and starts a security scope on the resulting URL,
    /// returning that URL for use. Callers must pair this with `endScope(for:)`
    /// on every exit path. Returns the plain `url` (no scope) when there is no
    /// usable bookmark — valid outside the sandbox and in tests. Use this pair
    /// for long-lived scopes (e.g. a player that holds an asset across many
    /// frames); prefer `withSecurityScope` for short scoped blocks.
    ///
    /// Single implementation of scope start.
    public static func beginScope(for url: URL, bookmark: Data?) -> URL {
        if let resolved = resolveBookmark(for: bookmark) {
            _ = resolved.url.startAccessingSecurityScopedResource()
            return resolved.url
        }
        return url
    }

    /// Asset overload: delegates to the URL-level `beginScope(for:bookmark:)`.
    public static func beginScope(for asset: MediaAsset) -> URL {
        beginScope(for: asset.originalURL, bookmark: asset.originalBookmark)
    }

    /// Stops a security scope previously started by `beginScope(for:bookmark:)`.
    /// Safe to call with the stored URL even when no scope was started
    /// (`stopAccessing` is a no-op in that case).
    ///
    /// URL-level by nature; there is no asset overload because the caller only
    /// holds the URL handed back by `beginScope`.
    public static func endScope(for url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

/// Owns a single started/stop security scope, stopped on deinit. Used internally
/// so that thrown errors still release the scope (the defer in the deinit path
/// is guaranteed by ARC regardless of how the scope ends).
private final class ScopedAccess {
    let url: URL
    private let started: Bool

    init(url: URL, bookmark: Data?) {
        if let resolved = SecurityScopedAccess.resolveBookmark(for: bookmark) {
            // Start the scope on the bookmark-resolved URL. Outside the sandbox
            // startAccessing returns false but is harmless; the file is still
            // reachable by path.
            self.url = resolved.url
            self.started = resolved.url.startAccessingSecurityScopedResource()
        } else {
            // No usable bookmark: fall back to the stored URL. This keeps
            // non-sandboxed builds and tests working, and lets the app layer
            // surface a relocation prompt for sandboxed builds separately.
            self.url = url
            self.started = false
        }
    }

    deinit {
        if started {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
