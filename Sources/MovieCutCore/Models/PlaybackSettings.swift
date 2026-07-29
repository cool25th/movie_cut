import Foundation

/// User-selectable playback (preview) settings, distinct from export output
/// quality. These govern the editing preview experience, not the rendered file.
public struct PlaybackSettings: Codable, Sendable, Equatable {
    /// When true and a clip's media asset has a generated proxy, the preview
    /// plays back the proxy in place of the original for smoother editing on
    /// heavy media. Export always uses the original regardless of this flag.
    public var useProxyPlayback: Bool

    public init(useProxyPlayback: Bool = false) {
        self.useProxyPlayback = useProxyPlayback
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        useProxyPlayback = try container.decodeIfPresent(Bool.self, forKey: .useProxyPlayback) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(useProxyPlayback, forKey: .useProxyPlayback)
    }

    private enum CodingKeys: String, CodingKey {
        case useProxyPlayback
    }
}
