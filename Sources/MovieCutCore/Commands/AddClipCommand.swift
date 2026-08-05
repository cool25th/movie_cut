import Foundation

/// Adds a clip to an existing track.
public struct AddClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The destination track identifier.
    public var trackId: UUID

    /// The clip to add.
    public var clip: Clip

    /// Optional insertion index used when restoring a deleted clip.
    public var insertionIndex: Int?

    /// Creates an add-clip command.
    public init(id: UUID = UUID(), trackId: UUID, clip: Clip, insertionIndex: Int? = nil) {
        self.id = id
        self.trackId = trackId
        self.clip = clip
        self.insertionIndex = insertionIndex
    }

    public func apply(to project: inout Project) throws {
        if (try? project.clipLocation(for: clip.id)) != nil {
            throw EditorCommandError.invalidCommand("Clip already exists: \(clip.id)")
        }

        try project.insertClip(clip, into: trackId, at: insertionIndex)
        // Magnetic compaction applies only to the main video track; every other
        // track (secondary video, audio, text/sticker) keeps freely-positioned
        // clip offsets. Step 2 of the core-editing repair handoff.
        if project.isMagneticTrack(trackId) {
            try project.compactTrackMagnetically(trackId)
        }
        try project.normalizeClipZIndexes(in: trackId)
        project.normalizeTrackZIndexes()
    }
}
