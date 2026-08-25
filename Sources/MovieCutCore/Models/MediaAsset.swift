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

    /// A security-scoped bookmark for `originalURL`, so the file can be
    /// re-reached after the app restarts under App Sandbox. Nil for assets
    /// created before the bookmark field existed (schema v1) or for assets
    /// whose bookmark is stale; the app layer resolves it and re-prompts when
    /// it no longer reaches the file. (S2)
    public var originalBookmark: Data?

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

    /// SURV-01 2차: the asset's location RELATIVE to the managed imports
    /// root (`<projectId>/<file>`) when the original was staged there by the
    /// iOS photo-picker import. The container's absolute path changes across
    /// reinstalls and device restores, so the relative reference lets
    /// `ProjectStore.rebaseManagedImports` re-point `originalURL` at the
    /// file's CURRENT location instead of losing the media. Nil for Mac
    /// (bookmark-based) assets and pre-2차 projects — the legacy absolute
    /// path then goes through a suffix-match rebase.
    public var managedImportPath: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case originalURL
        case originalBookmark
        case kind
        case duration
        case metadata
        case thumbnailData
        case proxy
        case managedImportPath
    }

    /// Creates a media asset.
    public init(
        id: UUID = UUID(),
        originalURL: URL,
        kind: MediaKind,
        duration: TimeInterval? = nil,
        metadata: MediaMetadata = MediaMetadata(),
        thumbnailData: Data? = nil,
        proxy: ProxyInfo? = nil,
        originalBookmark: Data? = nil,
        managedImportPath: String? = nil
    ) {
        self.id = id
        self.originalURL = originalURL
        self.kind = kind
        self.duration = duration
        self.metadata = metadata
        self.thumbnailData = thumbnailData
        self.proxy = proxy
        self.originalBookmark = originalBookmark
        self.managedImportPath = managedImportPath
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        originalURL = try container.decode(URL.self, forKey: .originalURL)
        // decodeIfPresent: schema v1 projects have no bookmark key; they load
        // with nil and the app re-creates a bookmark if the path still lives.
        originalBookmark = try container.decodeIfPresent(Data.self, forKey: .originalBookmark)
        kind = try container.decode(MediaKind.self, forKey: .kind)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        metadata = try container.decodeIfPresent(MediaMetadata.self, forKey: .metadata) ?? MediaMetadata()
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
        proxy = try container.decodeIfPresent(ProxyInfo.self, forKey: .proxy)
        managedImportPath = try container.decodeIfPresent(String.self, forKey: .managedImportPath)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalURL, forKey: .originalURL)
        try container.encodeIfPresent(originalBookmark, forKey: .originalBookmark)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(thumbnailData, forKey: .thumbnailData)
        try container.encodeIfPresent(proxy, forKey: .proxy)
        try container.encodeIfPresent(managedImportPath, forKey: .managedImportPath)
    }
}
