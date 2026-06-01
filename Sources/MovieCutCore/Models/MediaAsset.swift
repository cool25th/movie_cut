import Foundation

/// A kind of source media supported by the editor.
public enum MediaKind: String, Codable, Sendable, Equatable, Hashable {
    /// A video asset.
    case video

    /// An audio asset.
    case audio

    /// A still image asset.
    case image
}

/// A media item imported into a project.
public struct MediaAsset: Codable, Sendable, Equatable, Identifiable {
    /// The asset identifier.
    public var id: UUID

    /// The original media URL.
    public var originalURL: URL

    /// The media kind.
    public var kind: MediaKind

    /// The duration in seconds, when known.
    public var duration: TimeInterval?

    /// Probe metadata for the original media.
    public var metadata: MediaMetadata

    /// Optional generated proxy metadata.
    public var proxy: ProxyInfo?

    /// Creates a media asset.
    public init(
        id: UUID = UUID(),
        originalURL: URL,
        kind: MediaKind,
        duration: TimeInterval? = nil,
        metadata: MediaMetadata = MediaMetadata(),
        proxy: ProxyInfo? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.kind = kind
        self.duration = duration
        self.metadata = metadata
        self.proxy = proxy
    }
}
