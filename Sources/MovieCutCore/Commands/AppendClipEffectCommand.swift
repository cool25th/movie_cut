import Foundation

/// Atomically appends one effect to the clip's current effect list.
///
/// Unlike replacing the whole array from a UI snapshot, this command reads the
/// serialized EditorSession state at apply time, so rapid browser Apply actions
/// cannot overwrite an effect committed by an earlier action.
public struct AppendClipEffectCommand: EditorCommand {
    public let id: UUID
    public var clipId: UUID
    public var effect: Effect

    public init(id: UUID = UUID(), clipId: UUID, effect: Effect) {
        self.id = id
        self.clipId = clipId
        self.effect = effect
    }

    public func apply(to project: inout Project) throws {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].effects.append(effect)
    }
}
