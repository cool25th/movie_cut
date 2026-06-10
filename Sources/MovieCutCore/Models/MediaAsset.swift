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

    /// Optional thumbnail image data generated during import.
    public var thumbnailData: Data?

    /// Optional generated proxy metadata.
    public var proxy: ProxyInfo?

    private enum CodingKeys: String, CodingKey {
        case id
        case originalURL
        case kind
        case duration
        case metadata
        case thumbnailData
        case proxy
    }

    /// Creates a media asset.
    public init(
        id: UUID = UUID(),
        originalURL: URL,
        kind: MediaKind,
        duration: TimeInterval? = nil,
        metadata: MediaMetadata = MediaMetadata(),
        thumbnailData: Data? = nil,
        proxy: ProxyInfo? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.kind = kind
        self.duration = duration
        self.metadata = metadata
        self.thumbnailData = thumbnailData
        self.proxy = proxy
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        originalURL = try container.decode(URL.self, forKey: .originalURL)
        kind = try container.decode(MediaKind.self, forKey: .kind)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        metadata = try container.decodeIfPresent(MediaMetadata.self, forKey: .metadata) ?? MediaMetadata()
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
        proxy = try container.decodeIfPresent(ProxyInfo.self, forKey: .proxy)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalURL, forKey: .originalURL)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(thumbnailData, forKey: .thumbnailData)
        try container.encodeIfPresent(proxy, forKey: .proxy)
    }
}
