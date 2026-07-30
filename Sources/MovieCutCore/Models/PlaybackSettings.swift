import Foundation

/// User-selectable playback (preview) settings, distinct from export output
/// quality. These govern the editing preview experience, not the rendered file.
public struct PlaybackSettings: Codable, Sendable, Equatable {
    /// When true and a clip's media asset has a generated proxy, the preview
    /// plays back the proxy in place of the original for smoother editing on
    /// heavy media. Export always uses the original regardless of this flag.
    public var useProxyPlayback: Bool

    /// The resolution newly generated proxies are transcoded to (B-I7).
    ///
    /// Changing this does not invalidate proxies already on disk: each
    /// resolution has its own file, so switching back to a previously generated
    /// size reuses it instead of transcoding again.
    public var proxyResolution: ProxyResolution

    /// When true (default), preview automatically drops to proxy playback under
    /// serious/critical thermal pressure, then restores the original when the
    /// device cools. The user can turn this off to keep the original at all
    /// times. Does not override an explicit `useProxyPlayback = true`. (S7)
    public var autoProxyOnThermalPressure: Bool

    public init(
        useProxyPlayback: Bool = false,
        proxyResolution: ProxyResolution = .default,
        autoProxyOnThermalPressure: Bool = true
    ) {
        self.useProxyPlayback = useProxyPlayback
        self.proxyResolution = proxyResolution
        self.autoProxyOnThermalPressure = autoProxyOnThermalPressure
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        useProxyPlayback = try container.decodeIfPresent(Bool.self, forKey: .useProxyPlayback) ?? false
        // Projects saved before the picker existed carry no key. They were
        // generated with the old hardwired 960x540 preset, which is exactly
        // `ProxyResolution.default`, so the fallback preserves their output.
        proxyResolution = try container.decodeIfPresent(ProxyResolution.self, forKey: .proxyResolution) ?? .default
        // Projects saved before S7 carry no key; default to the safety net on.
        autoProxyOnThermalPressure = try container.decodeIfPresent(Bool.self, forKey: .autoProxyOnThermalPressure) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(useProxyPlayback, forKey: .useProxyPlayback)
        try container.encode(proxyResolution, forKey: .proxyResolution)
        try container.encode(autoProxyOnThermalPressure, forKey: .autoProxyOnThermalPressure)
    }

    private enum CodingKeys: String, CodingKey {
        case useProxyPlayback
        case proxyResolution
        case autoProxyOnThermalPressure
    }
}
