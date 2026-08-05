import Foundation

/// Writes range-based ducking metadata onto audio clips (F-14). One dispatch
/// covers every affected clip so the whole ducking pass is a single undo unit.
public struct SetAudioDuckingCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// Clip-local ducking ranges per clip. An empty array clears that clip's
    /// ducking ranges.
    public var duckingRangesByClip: [UUID: [TimeRange]]

    /// Ducked volume multiplier 0...1 applied inside the ranges. Nil clears
    /// ducking on all listed clips.
    public var level: Double?

    /// Creates a set-audio-ducking command.
    public init(
        id: UUID = UUID(),
        duckingRangesByClip: [UUID: [TimeRange]],
        level: Double?
    ) {
        self.id = id
        self.duckingRangesByClip = duckingRangesByClip
        self.level = level
    }

    public func apply(to project: inout Project) throws {
        if let level {
            guard level >= 0, level <= 1 else {
                throw EditorCommandError.invalidCommand("Ducking level must be between 0.0 and 1.0.")
            }
        }

        for (clipId, ranges) in duckingRangesByClip {
            let location = try project.clipLocation(for: clipId)
            try project.ensureTrackIsEditable(at: location.trackIndex)

            let clearing = level == nil || ranges.isEmpty
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].duckingRanges =
                clearing ? [] : ranges
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].duckingLevel =
                clearing ? nil : level
        }
    }
}

/// Restores ducking metadata captured before a `SetAudioDuckingCommand`.
public struct RestoreClipDuckingCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// Clip snapshots whose ducking fields should be restored.
    public var clips: [Clip]

    /// Creates a restore command from prior clip snapshots.
    public init(id: UUID = UUID(), clips: [Clip]) {
        self.id = id
        self.clips = clips
    }

    public func apply(to project: inout Project) throws {
        for snapshot in clips {
            guard let location = try? project.clipLocation(for: snapshot.id) else { continue }
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].duckingRanges = snapshot.duckingRanges
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].duckingLevel = snapshot.duckingLevel
        }
    }
}
