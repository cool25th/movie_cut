import Foundation

/// Adds a media asset to the project media library.
public struct ImportMediaCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The asset to import.
    public var asset: MediaAsset

    /// Creates an import command.
    public init(id: UUID = UUID(), asset: MediaAsset) {
        self.id = id
        self.asset = asset
    }

    public func apply(to project: inout Project) throws {
        project.mediaLibrary.assets[asset.id] = asset    }

    }

struct RemoveMediaAssetCommand: EditorCommand {
    let id: UUID
    let asset: MediaAsset

    init(id: UUID = UUID(), asset: MediaAsset) {
        self.id = id
        self.asset = asset
    }

    func apply(to project: inout Project) throws {
        guard project.mediaLibrary.assets.removeValue(forKey: asset.id) != nil else {
            throw EditorCommandError.assetNotFound(asset.id)
        }    }

    }

/// Replaces stored metadata for an imported media asset.
public struct UpdateMediaAssetCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var asset: MediaAsset

    public init(id: UUID = UUID(), asset: MediaAsset) {
        self.id = id
        self.asset = asset
    }

    public func apply(to project: inout Project) throws {
        guard let previousAsset = project.mediaLibrary.assets[asset.id] else {
            throw EditorCommandError.assetNotFound(asset.id)
        }

        project.mediaLibrary.assets[asset.id] = asset    }

    }
