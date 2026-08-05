import Foundation

/// Assigns or clears a link group for a set of clips. Clips sharing a group
/// identifier are selected and edited together (CapCut-style linked clips).
public struct GroupClipsCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clips whose group membership changes.
    public var clipIds: [UUID]

    /// The group to assign, or nil to ungroup the clips.
    public var groupId: UUID?

    /// Creates a group/ungroup command.
    public init(
        id: UUID = UUID(),
        clipIds: [UUID],
        groupId: UUID?
    ) {
        self.id = id
        self.clipIds = clipIds
        self.groupId = groupId
    }

    public func apply(to project: inout Project) throws {
        guard !clipIds.isEmpty else {
            throw EditorCommandError.invalidCommand("Group command requires at least one clip.")
        }
        if groupId != nil, clipIds.count < 2 {
            throw EditorCommandError.invalidCommand("Grouping requires at least two clips.")
        }

        for clipId in clipIds {
            let location = try project.clipLocation(for: clipId)
            try project.ensureTrackIsEditable(at: location.trackIndex)

            project.timeline.tracks[location.trackIndex]
                .clips[location.clipIndex].groupId = groupId
        }
    }
}

/// Restores heterogeneous prior group memberships in one command.
public struct RestoreClipGroupsCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The restore batches to apply.
    public var commands: [GroupClipsCommand]

    /// Creates a restore command.
    public init(id: UUID = UUID(), commands: [GroupClipsCommand]) {
        self.id = id
        self.commands = commands
    }

    public func apply(to project: inout Project) throws {
        var affected = Set<UUID>()
        for command in commands {
            // Restoring may legitimately re-group a single clip, so apply
            // membership directly instead of re-entering the two-clip guard.
            for clipId in command.clipIds {
                let location = try project.clipLocation(for: clipId)
                try project.ensureTrackIsEditable(at: location.trackIndex)
                project.timeline.tracks[location.trackIndex]
                    .clips[location.clipIndex].groupId = command.groupId
                affected.insert(clipId)
            }
        }
    }

    }
