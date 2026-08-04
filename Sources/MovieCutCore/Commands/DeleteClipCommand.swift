import Foundation

/// Removes a clip from its track.
public struct DeleteClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to delete.
    public var clipId: UUID

    /// Optional prior track identifier used when constructing an inverse command.
    public var deletedTrackId: UUID?

    /// Optional prior clip value used when constructing an inverse command.
    public var deletedClip: Clip?

    /// Optional prior clip index used when constructing an inverse command.
    public var deletedClipIndex: Int?

    /// Creates a delete-clip command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        deletedTrackId: UUID? = nil,
        deletedClip: Clip? = nil,
        deletedClipIndex: Int? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.deletedTrackId = deletedTrackId
        self.deletedClip = deletedClip
        self.deletedClipIndex = deletedClipIndex
    }

    public func apply(to project: inout Project) throws {
        let location = try project.clipLocation(for: clipId)
        let previousClips = project.timeline.tracks[location.trackIndex].clips
        let removed = try project.removeClip(id: clipId)
        // Normal Delete preserves gaps: it removes the clip and normalizes
        // zIndexes but does NOT compact the track. Ripple Delete (a separate
        // command) is the gap-closing variant. Step 2 of the core-editing
        // repair handoff.
        try project.normalizeClipZIndexes(in: removed.trackId)    }

    }
