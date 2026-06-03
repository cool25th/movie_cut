import Foundation

/// Repoints a clip at a different media asset.
public struct SetClipSourceAssetCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID
    public var assetId: UUID?
    public var kind: ClipKind?

    public init(
        id: UUID = UUID(),
        clipId: UUID,
        assetId: UUID?,
        kind: ClipKind? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.assetId = assetId
        self.kind = kind
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        if let assetId, project.mediaLibrary.assets[assetId] == nil {
            throw EditorCommandError.assetNotFound(assetId)
        }

        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].assetId = assetId
        if let kind {
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].kind = kind
        }

        return CommandResult(
            affectedClipIds: [clipId],
            description: "Set source asset for clip \(clipId)",
            undoValues: ["clip": .clip(previousClip)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .clip(let clip)? = result.undoValues["clip"] {
            return SetClipSourceAssetCommand(clipId: clipId, assetId: clip.assetId, kind: clip.kind)
        }

        return NoOpCommand(description: "Missing clip snapshot for inverse")
    }
}
