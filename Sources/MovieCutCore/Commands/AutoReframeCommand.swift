import CoreGraphics
import Foundation

/// Reframes visual clips to fill a target aspect ratio.
public struct AutoReframeCommand: EditorCommand, Sendable, Codable {
    /// The command identifier.
    public let id: UUID

    /// The desired output aspect ratio, expressed as width divided by height.
    public var targetAspect: CGFloat

    /// Creates an auto-reframe command.
    public init(id: UUID = UUID(), targetAspect: CGFloat) {
        self.id = id
        self.targetAspect = targetAspect
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        guard targetAspect.isFinite, targetAspect > 0 else {
            throw EditorCommandError.invalidCommand("Target aspect ratio must be greater than zero.")
        }

        let clipLocations = visualClipLocations(in: project)
        for location in clipLocations {
            try project.ensureTrackIsEditable(at: location.trackIndex)
        }

        let canvasSize = effectiveCanvasSize(in: project)
        var affectedClipIds = Set<UUID>()
        var undoValues: [String: CommandResultValue] = [:]

        for location in clipLocations {
            var clip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
            undoValues["clip.\(clip.id.uuidString)"] = .clip(clip)

            let sourceAspect = sourceAspect(for: clip, in: project) ?? (canvasSize.width / canvasSize.height)
            clip.transform = reframedTransform(
                from: clip.transform,
                sourceAspect: sourceAspect,
                targetAspect: targetAspect,
                canvasSize: canvasSize
            )

            project.timeline.tracks[location.trackIndex].clips[location.clipIndex] = clip
            affectedClipIds.insert(clip.id)
        }

        return CommandResult(
            affectedClipIds: affectedClipIds,
            description: "Auto reframe clips to \(targetAspect)",
            undoValues: undoValues
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        let snapshots = result.undoValues.values.compactMap { value -> AutoReframeTransformSnapshot? in
            if case .clip(let clip) = value {
                return AutoReframeTransformSnapshot(clipId: clip.id, transform: clip.transform)
            }
            return nil
        }

        guard !snapshots.isEmpty else {
            return NoOpCommand(description: "Missing clip transforms for auto-reframe inverse")
        }

        return RestoreAutoReframeCommand(snapshots: snapshots)
    }

    private func visualClipLocations(in project: Project) -> [(trackIndex: Int, clipIndex: Int)] {
        var locations: [(trackIndex: Int, clipIndex: Int)] = []

        for trackIndex in project.timeline.tracks.indices {
            let track = project.timeline.tracks[trackIndex]
            guard track.kind == .video else { continue }

            for clipIndex in track.clips.indices {
                let clip = track.clips[clipIndex]
                if clip.kind == .video || clip.kind == .image {
                    locations.append((trackIndex, clipIndex))
                }
            }
        }

        return locations
    }

    private func reframedTransform(
        from transform: ClipTransform,
        sourceAspect: CGFloat,
        targetAspect: CGFloat,
        canvasSize: CGSize
    ) -> ClipTransform {
        var updatedTransform = transform
        let scale = fillScale(sourceAspect: sourceAspect, targetAspect: targetAspect)

        updatedTransform.scale = CGSize(
            width: transform.scale.width * scale,
            height: transform.scale.height * scale
        )
        updatedTransform.position = CGPoint(
            x: canvasSize.width / 2,
            y: canvasSize.height / 2
        )

        return updatedTransform
    }

    private func sourceAspect(for clip: Clip, in project: Project) -> CGFloat? {
        guard let assetId = clip.assetId,
              let asset = project.mediaLibrary.assets[assetId],
              let width = asset.metadata.width,
              let height = asset.metadata.height,
              width > 0,
              height > 0 else {
            return nil
        }

        return CGFloat(width) / CGFloat(height)
    }

    private func effectiveCanvasSize(in project: Project) -> CGSize {
        let timelineSize = project.timeline.canvasSize
        if timelineSize.width > 0, timelineSize.height > 0 {
            return timelineSize
        }

        return project.canvas.size
    }

    private func fillScale(sourceAspect: CGFloat, targetAspect: CGFloat) -> CGFloat {
        guard sourceAspect.isFinite, sourceAspect > 0 else { return 1 }
        return max(sourceAspect / targetAspect, targetAspect / sourceAspect)
    }
}

private struct AutoReframeTransformSnapshot: Sendable, Codable, Equatable {
    var clipId: UUID
    var transform: ClipTransform
}

private struct RestoreAutoReframeCommand: EditorCommand, Sendable, Codable {
    let id: UUID
    var snapshots: [AutoReframeTransformSnapshot]

    init(id: UUID = UUID(), snapshots: [AutoReframeTransformSnapshot]) {
        self.id = id
        self.snapshots = snapshots
    }

    func apply(to project: inout Project) throws -> CommandResult {
        var affectedClipIds = Set<UUID>()
        var undoValues: [String: CommandResultValue] = [:]

        for snapshot in snapshots {
            let location = try project.clipLocation(for: snapshot.clipId)
            try project.ensureTrackIsEditable(at: location.trackIndex)

            let clip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
            undoValues["clip.\(clip.id.uuidString)"] = .clip(clip)
        }

        for snapshot in snapshots {
            let location = try project.clipLocation(for: snapshot.clipId)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].transform = snapshot.transform
            affectedClipIds.insert(snapshot.clipId)
        }

        return CommandResult(
            affectedClipIds: affectedClipIds,
            description: "Restore auto-reframe transforms",
            undoValues: undoValues
        )
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        let snapshots = result.undoValues.values.compactMap { value -> AutoReframeTransformSnapshot? in
            if case .clip(let clip) = value {
                return AutoReframeTransformSnapshot(clipId: clip.id, transform: clip.transform)
            }
            return nil
        }

        guard !snapshots.isEmpty else {
            return NoOpCommand(description: "Missing clip transforms for auto-reframe redo")
        }

        return RestoreAutoReframeCommand(snapshots: snapshots)
    }
}
