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

    public func apply(to project: inout Project) throws -> CommandResult {
        project.mediaLibrary.assets[asset.id] = asset
        return CommandResult(description: "Imported media asset \(asset.id)")
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RemoveMediaAssetCommand(asset: asset)
    }
}

struct RemoveMediaAssetCommand: EditorCommand {
    let id: UUID
    let asset: MediaAsset

    init(id: UUID = UUID(), asset: MediaAsset) {
        self.id = id
        self.asset = asset
    }

    func apply(to project: inout Project) throws -> CommandResult {
        guard project.mediaLibrary.assets.removeValue(forKey: asset.id) != nil else {
            throw EditorCommandError.assetNotFound(asset.id)
        }
        return CommandResult(description: "Removed media asset \(asset.id)")
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        ImportMediaCommand(asset: asset)
    }
}

/// Replaces stored metadata for an imported media asset.
public struct UpdateMediaAssetCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var asset: MediaAsset

    public init(id: UUID = UUID(), asset: MediaAsset) {
        self.id = id
        self.asset = asset
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        guard let previousAsset = project.mediaLibrary.assets[asset.id] else {
            throw EditorCommandError.assetNotFound(asset.id)
        }

        project.mediaLibrary.assets[asset.id] = asset
        return CommandResult(
            description: "Updated media asset \(asset.id)",
            undoValues: ["asset": .mediaAsset(previousAsset)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .mediaAsset(let previousAsset)? = result.undoValues["asset"] {
            return UpdateMediaAssetCommand(asset: previousAsset)
        }

        return NoOpCommand(description: "Missing media asset snapshot for inverse")
    }
}
