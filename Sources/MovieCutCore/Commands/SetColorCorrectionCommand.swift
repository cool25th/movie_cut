import Foundation

/// Sets the color correction values for a clip.
public struct SetColorCorrectionCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID
    public var colorCorrection: ColorCorrection?
    public var previousColorCorrection: ColorCorrection?

    public init(
        id: UUID = UUID(),
        clipId: UUID,
        colorCorrection: ColorCorrection?,
        previousColorCorrection: ColorCorrection? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.colorCorrection = colorCorrection
        self.previousColorCorrection = previousColorCorrection
    }

    public func apply(to project: inout Project) throws {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)
        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].colorCorrection = colorCorrection
    }

    }
