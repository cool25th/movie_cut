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
