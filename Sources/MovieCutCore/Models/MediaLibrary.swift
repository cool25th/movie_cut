import Foundation

/// A project-scoped collection of imported media assets.
public struct MediaLibrary: Codable, Sendable, Equatable {
    /// Assets keyed by their stable identifier.
    public var assets: [UUID: MediaAsset]

    /// Creates a media library.
    public init(assets: [UUID: MediaAsset] = [:]) {
        self.assets = assets
    }
}
