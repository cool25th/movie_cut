import Foundation

/// Deletes a clip and shifts subsequent clips left to close the gap.
public struct RippleDeleteCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to ripple-delete.
    public var clipId: UUID

    /// Creates a ripple-delete command.
    public init(id: UUID = UUID(), clipId: UUID) {
        self.id = id
        self.clipId = clipId
    }

    public func apply(to project: inout Project) throws {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let trackId = project.timeline.tracks[location.trackIndex].id
        let deletedClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        let duration = deletedClip.timelineRange.duration
        guard duration >= 0 else {
            throw EditorCommandError.invalidCommand("Clip duration cannot be negative.")
        }

        project.timeline.tracks[location.trackIndex].clips.remove(at: location.clipIndex)

        let clipCount = project.timeline.tracks[location.trackIndex].clips.count
        for index in location.clipIndex..<clipCount {
            project.timeline.tracks[location.trackIndex].clips[index].timelineRange.start -= duration
        }
    }
}

struct RestoreRippleDeleteCommand: EditorCommand {
    let id: UUID
    var trackId: UUID
    var clip: Clip
    var insertionIndex: Int

    init(id: UUID = UUID(), trackId: UUID, clip: Clip, insertionIndex: Int) {
        self.id = id
        self.trackId = trackId
        self.clip = clip
        self.insertionIndex = insertionIndex
    }

    func apply(to project: inout Project) throws {
        let trackIndex = try project.trackIndex(for: trackId)
        try project.ensureTrackIsEditable(at: trackIndex)
        guard insertionIndex >= 0, insertionIndex <= project.timeline.tracks[trackIndex].clips.count else {
            throw EditorCommandError.invalidCommand("Clip insertion index is out of bounds.")
        }

        let duration = clip.timelineRange.duration
        for index in insertionIndex..<project.timeline.tracks[trackIndex].clips.count {
            project.timeline.tracks[trackIndex].clips[index].timelineRange.start += duration
        }
        project.timeline.tracks[trackIndex].clips.insert(clip, at: insertionIndex)
    }

    }
