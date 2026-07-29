import Foundation

/// Metadata about an optional proxy media file.
public struct ProxyInfo: Codable, Sendable, Equatable {
    /// The proxy media URL, when generated.
    public var proxyURL: URL?

    /// The proxy frame size.
    public var resolution: CGSize?

    /// Creates proxy metadata.
    public init(proxyURL: URL? = nil, resolution: CGSize? = nil) {
        self.proxyURL = proxyURL
        self.resolution = resolution
    }
}

/// Whether a clip shows a proxy badge, and whether that proxy is what preview
/// is actually playing.
///
/// `CAPCUT_BENCHMARK_STANDARD.md` B-I7 asks for a badge on the clip "once
/// generation completes". MovieCut splits generation (per asset) from
/// consumption (the project-wide `PlaybackSettings.useProxyPlayback` toggle) —
/// a split CapCut's single Proxy Mode does not have. A badge that only meant
/// "a proxy file exists" would leave a user wondering why preview is still
/// slow, so the badge carries both facts: it appears as soon as a proxy exists
/// (matching B-I7) and distinguishes whether that proxy is in effect.
public enum ProxyBadgeState: String, Sendable, Equatable, CaseIterable {
    /// A proxy file exists but preview is still playing the original.
    case idle
    /// The proxy is what preview is playing.
    case active

    /// Resolves the badge state for one media asset.
    ///
    /// - Parameters:
    ///   - proxy: the asset's proxy metadata, if any.
    ///   - useProxyPlayback: the project's proxy-playback setting.
    /// - Returns: `nil` when no proxy file exists, meaning no badge is shown.
    ///   `ProxyInfo` with a `nil` `proxyURL` counts as no proxy — the struct can
    ///   exist before generation finishes.
    public static func resolve(proxy: ProxyInfo?, useProxyPlayback: Bool) -> ProxyBadgeState? {
        guard proxy?.proxyURL != nil else { return nil }
        return useProxyPlayback ? .active : .idle
    }
}
