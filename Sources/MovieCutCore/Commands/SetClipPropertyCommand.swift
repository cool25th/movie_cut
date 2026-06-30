import Foundation

/// A supported clip property mutation.
public enum ClipProperty: Codable, Sendable, Equatable {
    /// Replaces the clip transform.
    case transform(ClipTransform)

    /// Replaces the clip opacity.
    case opacity(Double)

    /// Replaces the clip audio volume multiplier.
    case volume(Double)

    /// Replaces the clip five-band equalizer settings.
    case equalizer(ClipEqualizerSettings?)

    /// Replaces the constant clip playback rate.
    case playbackRate(Double)

    /// Replaces the clip speed-ramp points.
    case speedRampPoints([SpeedRampPoint])

    /// Smooth slow-motion frame interpolation toggle.
    case opticalFlow(Bool)

    /// Replaces the clip animation keyframes.
    case keyframes([Keyframe])

    /// Replaces the clip transition.
    case transition(Transition?)

    /// Replaces editable text content for a text clip.
    case textContent(TextClipContent?)

    /// Replaces the clip chroma key settings.
    case chromaKey(ChromaKeySettings?)

    /// Replaces the clip effects list.
    case effects([Effect])

    /// Replaces the clip mask.
    case mask(Mask?)

    /// Replaces the clip color correction.
    case colorCorrection(ColorCorrection?)

    /// Replaces the clip 3-way color grade.
    case colorGrade(ColorGrade?)

    /// Replaces the clip's same-track layer order.
    case zIndex(Int)

    /// Person-segmentation background removal toggle.
    case isBackgroundRemoved(Bool)
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
        case .volume(let volume):
            previousProperty = .volume(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].volume)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].volume = volume
        case .equalizer(let equalizer):
            previousProperty = .equalizer(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].equalizer)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].equalizer = equalizer
        case .playbackRate(let playbackRate):
            previousProperty = .playbackRate(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].playbackRate)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].playbackRate = min(max(playbackRate, 0.25), 4.0)
        case .speedRampPoints(let speedRampPoints):
            previousProperty = .speedRampPoints(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].speedRampPoints)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].speedRampPoints = speedRampPoints
        case .opticalFlow(let useOpticalFlow):
            previousProperty = .opticalFlow(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].useOpticalFlow)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].useOpticalFlow = useOpticalFlow
        case .keyframes(let keyframes):
            previousProperty = .keyframes(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].keyframes)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].keyframes = keyframes
        case .transition(let transition):
            previousProperty = .transition(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].transition)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].transition = transition
        case .textContent(let textContent):
            previousProperty = .textContent(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].textContent)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].textContent = textContent
        case .chromaKey(let chromaKey):
            previousProperty = .chromaKey(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].chromaKey)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].chromaKey = chromaKey
        case .effects(let effects):
            previousProperty = .effects(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].effects)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].effects = effects
        case .mask(let mask):
            previousProperty = .mask(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].mask)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].mask = mask
        case .colorCorrection(let colorCorrection):
            previousProperty = .colorCorrection(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].colorCorrection)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].colorCorrection = colorCorrection
        case .colorGrade(let colorGrade):
            previousProperty = .colorGrade(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].colorGrade)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].colorGrade = colorGrade
        case .zIndex(let zIndex):
            previousProperty = .zIndex(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].zIndex)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].zIndex = zIndex
        case .isBackgroundRemoved(let isBackgroundRemoved):
            previousProperty = .isBackgroundRemoved(project.timeline.tracks[location.trackIndex].clips[location.clipIndex].isBackgroundRemoved)
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].isBackgroundRemoved = isBackgroundRemoved
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
