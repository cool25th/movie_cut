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

    public func apply(to project: inout Project) throws -> CommandResult {
        guard !clipIds.isEmpty else {
            throw EditorCommandError.invalidCommand("Group command requires at least one clip.")
        }
        if groupId != nil, clipIds.count < 2 {
            throw EditorCommandError.invalidCommand("Grouping requires at least two clips.")
        }

        var previousGroups: [String: CommandResultValue] = [:]
        for clipId in clipIds {
            let location = try project.clipLocation(for: clipId)
            try project.ensureTrackIsEditable(at: location.trackIndex)

            let previousGroupId = project.timeline.tracks[location.trackIndex]
                .clips[location.clipIndex].groupId
            if let previousGroupId {
                previousGroups[Self.previousGroupKey(for: clipId)] = .uuid(previousGroupId)
            }
            project.timeline.tracks[location.trackIndex]
                .clips[location.clipIndex].groupId = groupId
        }

        let action = groupId == nil ? "Ungrouped" : "Grouped"
        return CommandResult(
            affectedClipIds: Set(clipIds),
            description: "\(action) \(clipIds.count) clips",
            undoValues: previousGroups
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        // Group membership before this command may differ per clip; restore in
        // per-previous-group batches so undo is exact.
        var clipsByPreviousGroup: [UUID?: [UUID]] = [:]
        for clipId in clipIds {
            let previous: UUID?
            if case .uuid(let value)? = result.undoValues[Self.previousGroupKey(for: clipId)] {
                previous = value
            } else {
                previous = nil
            }
            clipsByPreviousGroup[previous, default: []].append(clipId)
        }

        let restoreCommands = clipsByPreviousGroup.map { previousGroup, ids in
            GroupClipsCommand(clipIds: ids, groupId: previousGroup)
        }
        if restoreCommands.count == 1, let only = restoreCommands.first {
            return only
        }
        return RestoreClipGroupsCommand(commands: restoreCommands)
    }

    static func previousGroupKey(for clipId: UUID) -> String {
        "previousGroup.\(clipId.uuidString)"
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

    public func apply(to project: inout Project) throws -> CommandResult {
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

        return CommandResult(
            affectedClipIds: affected,
            description: "Restored clip group membership",
            undoValues: [:]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        NoOpCommand(description: "Clip group restore is not directly invertible")
    }
}
