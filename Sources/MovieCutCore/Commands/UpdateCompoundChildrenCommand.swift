import Foundation

/// Command to update the constituent child clips of a compound definition (Inc 2).
///
/// Dispatched when editing inside a compound sequence (e.g. splitting, trimming,
/// reordering, adding/deleting clips). Updates `Project.compounds` in place and
/// adjusts container clip durations to match the new children span.
public struct UpdateCompoundChildrenCommand: EditorCommand, Sendable, Equatable {
    public let id: UUID
    public let compoundId: UUID
    public let newChildClips: [Clip]
    public let oldChildClips: [Clip]

    public init(
        id: UUID = UUID(),
        compoundId: UUID,
        newChildClips: [Clip],
        oldChildClips: [Clip]
    ) {
        self.id = id
        self.compoundId = compoundId
        self.newChildClips = newChildClips
        self.oldChildClips = oldChildClips
    }

    public func apply(to project: inout Project) throws {
        guard let index = project.compounds.firstIndex(where: { $0.id == compoundId }) else {
            throw EditorCommandError.invalidCommand(
                "Compound definition not found: \(compoundId)"
            )
        }

        // Validate no nesting: none of the new children may carry a compoundId
        for clip in newChildClips {
            if clip.compoundId != nil {
                throw EditorCommandError.invalidCommand(
                    "A compound clip cannot contain another compound clip."
                )
            }
        }

        project.compounds[index].childClips = newChildClips

        // Calculate total duration of new children
        let totalDuration = newChildClips.reduce(0.0) { max($0, $1.timelineRange.end) }
        let clampedDuration = max(totalDuration, 0.1)

        // Adjust timeline container clips referencing this compound
        for trackIndex in project.timeline.tracks.indices {
            for clipIndex in project.timeline.tracks[trackIndex].clips.indices {
                if project.timeline.tracks[trackIndex].clips[clipIndex].compoundId == compoundId {
                    var container = project.timeline.tracks[trackIndex].clips[clipIndex]
                    container.sourceRange.duration = clampedDuration
                    let rate = container.playbackRate > 0 ? container.playbackRate : 1.0
                    container.timelineRange.duration = clampedDuration / rate
                    project.timeline.tracks[trackIndex].clips[clipIndex] = container
                }
            }
        }
    }

    public func invert(from project: Project) -> any EditorCommand {
        UpdateCompoundChildrenCommand(
            id: UUID(),
            compoundId: compoundId,
            newChildClips: oldChildClips,
            oldChildClips: newChildClips
        )
    }
}
