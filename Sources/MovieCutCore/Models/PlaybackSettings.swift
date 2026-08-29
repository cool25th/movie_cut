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

    /// CA-22: when true (default), a video import automatically starts proxy
    /// generation in the background — the proxy is ready before the user
    /// needs it, instead of requiring a manual trip to the media browser.
    /// Skipped under critical thermal pressure. The user can turn this off
    /// to keep imports instant on battery-constrained or disk-tight setups.
    public var autoGenerateProxyOnImport: Bool

    /// The render resolution `PlaybackEngine` scales the project canvas down to
    /// for the editing preview (Requirement 5). Export always uses
    /// `project.canvas`, so this never changes the exported file. `.full` (the
    /// default) leaves the canvas untouched.
    public var previewQuality: PreviewQuality

    public init(
        useProxyPlayback: Bool = false,
        proxyResolution: ProxyResolution = .default,
        autoProxyOnThermalPressure: Bool = true,
        autoGenerateProxyOnImport: Bool = true,
        previewQuality: PreviewQuality = .default
    ) {
        self.useProxyPlayback = useProxyPlayback
        self.proxyResolution = proxyResolution
        self.autoProxyOnThermalPressure = autoProxyOnThermalPressure
        self.autoGenerateProxyOnImport = autoGenerateProxyOnImport
        self.previewQuality = previewQuality
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
        // CA-22: projects saved before auto-generation carry no key; default
        // to on so new imports get proxies without user action.
        autoGenerateProxyOnImport = try container.decodeIfPresent(Bool.self, forKey: .autoGenerateProxyOnImport) ?? true
        // Projects saved before Requirement 5 carry no key; default to full
        // canvas so their preview renders identically. The raw value is decoded
        // as a String and mapped through `init(rawValue:)` so an unknown value
        // (e.g. a case removed in a future schema) falls back to the default
        // rather than throwing — old files keep loading.
        if let rawValue = try container.decodeIfPresent(String.self, forKey: .previewQuality) {
            previewQuality = PreviewQuality(rawValue: rawValue) ?? .default
        } else {
            previewQuality = .default
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(useProxyPlayback, forKey: .useProxyPlayback)
        try container.encode(proxyResolution, forKey: .proxyResolution)
        try container.encode(autoProxyOnThermalPressure, forKey: .autoProxyOnThermalPressure)
        // Encode only when not default so existing project files stay
        // byte-identical when the user never touched this dial (CA-22).
        if !autoGenerateProxyOnImport {
            try container.encode(autoGenerateProxyOnImport, forKey: .autoGenerateProxyOnImport)
        }
        // Encode only when not default so existing project files stay
        // byte-identical when the user never touched this dial. This keeps the
        // schema-stability guarantee that a no-op setting writes nothing new.
        if previewQuality != .default {
            try container.encode(previewQuality, forKey: .previewQuality)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case useProxyPlayback
        case proxyResolution
        case autoProxyOnThermalPressure
        case autoGenerateProxyOnImport
        case previewQuality
    }
}
