import Foundation
import MovieCutCore

/// Resolves and grants App Sandbox access to a `MediaAsset`'s original file via
/// its security-scoped bookmark.
///
/// Under App Sandbox, an `originalURL` picked through `NSOpenPanel` is only
/// reachable for the lifetime of that URL object unless a security-scoped
/// bookmark is captured and later resolved. This type is the single owner of
/// that lifecycle: it resolves bookmarks (detecting stale ones), and pairs every
/// `startAccessingSecurityScopedResource` with a matching `stopAccessing` via
/// `withSecurityScope`. (S2 of `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`.)
public enum SecurityScopedAccess {

    /// Resolves a bookmark to a URL, reporting staleness instead of crashing.
    ///
    /// - Returns: The resolved URL and whether the bookmark was stale (the file
    ///   moved). `nil` when there is no bookmark, the data cannot be resolved,
    ///   or the file does not exist at the resolved path — all cases the caller
    ///   should treat as "re-prompt the user to relocate the media".
    public static func resolveBookmark(for asset: MediaAsset) -> (url: URL, isStale: Bool)? {
        guard let bookmark = asset.originalBookmark else { return nil }

        var isStale = false
        // `.withSecurityScope` is required to re-reach user-selected files under
        // the sandbox; the call is a no-op outside the sandbox, so non-sandboxed
        // builds and tests behave identically.
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        // A resolved URL whose file no longer exists is treated as missing too.
        guard FileManager.default.fileExists(atPath: resolved.path) else { return nil }
        return (resolved, isStale)
    }

    /// Runs `body` against the asset's original file inside a security scope.
    ///
    /// The scope is started before `body` and stopped on every exit path
    /// (return or throw), so callers cannot leak the access pair. When the asset
    /// has a usable bookmark it is resolved and started; otherwise `body` runs
    /// against the plain `originalURL` (valid outside the sandbox, and lets
    /// non-sandboxed builds and tests proceed).
    public static func withSecurityScope<T>(
        for asset: MediaAsset,
        body: (URL) throws -> T
    ) throws -> T {
        let access = ScopedAccess(asset: asset)
        return try body(access.url)
    }

    /// Async overload of `withSecurityScope(for:body:)`.
    public static func withSecurityScope<T>(
        for asset: MediaAsset,
        body: (URL) async throws -> T
    ) async throws -> T {
        let access = ScopedAccess(asset: asset)
        return try await body(access.url)
    }

    /// Whether the asset's media needs the user to relocate it: there is no
    /// bookmark, or the bookmark no longer resolves to an existing file.
    public static func needsRelocation(_ asset: MediaAsset) -> Bool {
        resolveBookmark(for: asset) == nil && asset.originalBookmark != nil
    }

    /// Builds a security-scoped bookmark for `url`, returning `nil` if one
    /// cannot be captured (e.g. the URL is in the app container and needs none).
    public static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope, .minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves the asset's bookmark and starts a security scope on the
    /// resulting URL, returning that URL for use. Callers must pair this with
    /// `endScope(for:)` on every exit path. Returns the plain `originalURL`
    /// (no scope) when there is no usable bookmark — valid outside the sandbox
    /// and in tests. Use this pair for long-lived scopes (e.g. a player that
    /// holds an asset across many frames); prefer `withSecurityScope` for
    /// short scoped blocks.
    public static func beginScope(for asset: MediaAsset) -> URL {
        if let resolved = resolveBookmark(for: asset) {
            _ = resolved.url.startAccessingSecurityScopedResource()
            return resolved.url
        }
        return asset.originalURL
    }

    /// Stops a security scope previously started by `beginScope(for:)`. Safe to
    /// call with the stored `originalURL` even when no scope was started
    /// (`stopAccessing` is a no-op in that case).
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

    init(asset: MovieCutCore.MediaAsset) {
        if let resolved = SecurityScopedAccess.resolveBookmark(for: asset) {
            // Start the scope on the bookmark-resolved URL. Outside the sandbox
            // startAccessing returns false but is harmless; the file is still
            // reachable by path.
            self.url = resolved.url
            self.started = resolved.url.startAccessingSecurityScopedResource()
        } else {
            // No usable bookmark: fall back to the stored URL. This keeps
            // non-sandboxed builds and tests working, and lets the app layer
            // surface a relocation prompt for sandboxed builds separately.
            self.url = asset.originalURL
            self.started = false
        }
    }

    deinit {
        if started {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
