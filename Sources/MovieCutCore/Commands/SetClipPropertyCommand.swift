import Foundation

/// A supported clip property mutation.
public enum ClipProperty: Codable, Sendable, Equatable {
    /// Replaces the clip transform.
    case transform(ClipTransform)

    /// Replaces the clip opacity.
    case opacity(Double)

    /// Replaces editable text content for a text clip.
    case textContent(TextClipContent?)

    /// Replaces the clip effects list.
    case effects([Effect])
}

/// Sets one editable clip property.
public struct SetClipPropertyCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to modify.
    public var clipId: UUID

    /// The new property value.
    public var property: ClipProperty

    /// Optional prior property value used when constructing an inverse command.
    public var previousProperty: ClipProperty?

    /// Creates a set-property command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        property: ClipProperty,
        previousProperty: ClipProperty? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.property = property
        self.previousProperty = previousProperty
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let previousProperty: ClipProperty
        switch property {
        case .transform(let transform):
            previousProperty = .transform(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].transform)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].transform = transform
        case .opacity(let opacity):
            previousProperty = .opacity(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].opacity)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].opacity = opacity
        case .textContent(let textContent):
            previousProperty = .textContent(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].textContent)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].textContent = textContent
        case .effects(let effects):
            previousProperty = .effects(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].effects)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].effects = effects
        }

        return CommandResult(
            affectedClipIds: [clipId],
            description: "Set clip property for \(clipId)",
            undoValues: ["property": .clipProperty(previousProperty)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .clipProperty(let property)? = result.undoValues["property"] {
            return SetClipPropertyCommand(clipId: clipId, property: property)
        }

        guard let previousProperty else {
            return NoOpCommand(description: "Missing previous clip property for inverse")
        }
        return SetClipPropertyCommand(clipId: clipId, property: previousProperty)
    }
}
