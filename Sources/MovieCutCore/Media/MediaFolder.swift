import Foundation

/// A user-visible folder that groups media assets in the project media library.
public struct MediaFolder: Codable, Sendable, Identifiable, Equatable {
    /// The folder identifier.
    public var id: UUID

    /// The user-visible folder name.
    public var name: String

    /// Media asset identifiers contained in this folder.
    public var assetIds: Set<UUID>

    /// The parent folder identifier, or nil when this folder is at the root level.
    public var parentFolderId: UUID?

    /// Creates a media folder.
    public init(
        id: UUID = UUID(),
        name: String,
        assetIds: Set<UUID> = [],
        parentFolderId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.assetIds = assetIds
        self.parentFolderId = parentFolderId
    }

    /// Adds an asset to the folder.
    public mutating func add(_ assetId: UUID) {
        assetIds.insert(assetId)
    }

    /// Removes an asset from the folder.
    public mutating func remove(_ assetId: UUID) {
        assetIds.remove(assetId)
    }
}
