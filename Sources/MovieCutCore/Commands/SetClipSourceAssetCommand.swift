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

    public func apply(to project: inout Project) throws {
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
    }

    }
