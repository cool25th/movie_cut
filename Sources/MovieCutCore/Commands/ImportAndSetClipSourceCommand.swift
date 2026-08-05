import Foundation

/// Atomically registers a new media asset in the project library AND repoints a
/// clip at it, in a single dispatch.
///
/// The editor session records one undo snapshot per `dispatch`, so to make an
/// offline-render-then-swap operation (vocal separation, noise reduction, ...)
/// a **single undo unit** (requirement 9.3), the asset import and the clip
/// source swap must happen inside one `apply`. Splitting them into
/// `ImportMediaCommand` + `SetClipSourceAssetCommand` as two dispatches would be
/// two undo steps and leave a dangling imported asset if only the second were
/// undone.
///
/// The swap itself follows the same semantics as
/// ``SetClipSourceAssetCommand.apply(to:)``: it locates the clip, enforces the
/// editable-track guard, validates the asset exists in the library after import,
/// captures the previous clip for the inverse, and reassigns `assetId`/`kind`.
/// `kind` is optional so callers can keep the clip kind unchanged.
///
/// Undo is handled by the session's whole-project snapshot restore (see
/// ``AutoCutCommand``), so ``invert(from:)`` returns a no-op rather than
/// duplicating import/swap reconstruction.
public struct ImportAndSetClipSourceCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip whose source asset is being replaced.
    public var clipId: UUID

    /// The new asset to register in the media library and point the clip at.
    public var asset: MediaAsset

    /// The clip kind to set, or nil to leave the existing kind unchanged.
    public var kind: ClipKind?

    /// Creates the composite import-and-swap command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        asset: MediaAsset,
        kind: ClipKind? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.asset = asset
        self.kind = kind
    }

    public func apply(to project: inout Project) throws {
        // Mirror ImportMediaCommand: register the asset in the library.
        project.mediaLibrary.assets[asset.id] = asset

        // Mirror SetClipSourceAssetCommand: locate, guard, validate, swap.
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        // The asset must now resolve in the library. This also covers the
        // (pathological) case where a concurrent mutation removed it.
        guard project.mediaLibrary.assets[asset.id] != nil else {
            throw EditorCommandError.assetNotFound(asset.id)
        }

        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].assetId = asset.id
        if let kind {
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].kind = kind
        }
    }

    }
