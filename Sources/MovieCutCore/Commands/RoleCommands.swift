import Foundation

/// CA-20 stage 1 (W4): role registry + clip tagging commands. The
/// timeline-index UI (stage 2) drives these — the registry upsert and the
/// batch assignment are the two editing verbs every surface funnels
/// through, so registry integrity (unique names, no dangling clip
/// references) is enforced here rather than per-caller.
public struct AddTimelineRoleCommand: EditorCommand {
    public let id: UUID
    public var role: TimelineRole

    public init(id: UUID = UUID(), role: TimelineRole) {
        self.id = id
        self.role = role
    }

    public func apply(to project: inout Project) throws {
        // Names are the user-facing identity in the index UI — a duplicate
        // name would make role filtering ambiguous. Exact-match guard
        // (case is preserved verbatim; "Music" vs "music" are distinct
        // roles, matching how FCP treats role names as free text).
        guard !project.roles.contains(where: { $0.name == role.name }) else {
            throw EditorCommandError.invalidCommand("Role name already exists: \(role.name)")
        }
        guard !project.roles.contains(where: { $0.id == role.id }) else {
            throw EditorCommandError.invalidCommand("Role already exists: \(role.id)")
        }
        project.roles.append(role)
    }
}

/// Tags a batch of clips with a role (or clears the tag with nil).
///
/// Atomicity: an unknown clip id or a role id absent from the registry
/// rejects the WHOLE command before any mutation — a partially-applied
/// batch would be indistinguishable from a successful one in the undo
/// snapshot (the CODEX-18 atomicity lesson).
///
/// Role tagging is metadata, not timeline geometry: it deliberately does
/// NOT route through `ensureTrackIsEditable` — FCP roles apply to locked
/// tracks too, and the tag changes no placement, trim, or content.
public struct SetClipRoleCommand: EditorCommand {
    public let id: UUID
    public var clipIds: [UUID]
    public var roleId: UUID?

    public init(id: UUID = UUID(), clipIds: [UUID], roleId: UUID?) {
        self.id = id
        self.clipIds = clipIds
        self.roleId = roleId
    }

    public func apply(to project: inout Project) throws {
        // Pre-validate EVERYTHING before the first mutation — validating
        // after the loop would leave a partially-applied batch that the
        // undo snapshot cannot distinguish from a success (the CODEX-18
        // atomicity lesson; the first draft of this command made exactly
        // that mistake and the test caught it).
        let distinctIds = Set(clipIds)
        let existingIds = Set(project.timeline.tracks.flatMap { $0.clips.map(\.id) })
        guard distinctIds.isSubset(of: existingIds) else {
            throw EditorCommandError.invalidCommand(
                "Role assignment referenced unknown clip(s) — nothing applied"
            )
        }
        guard roleId == nil || project.roles.contains(where: { $0.id == roleId }) else {
            throw EditorCommandError.invalidCommand("Unknown role: \(String(describing: roleId))")
        }
        for trackIndex in project.timeline.tracks.indices {
            for clipIndex in project.timeline.tracks[trackIndex].clips.indices
            where distinctIds.contains(project.timeline.tracks[trackIndex].clips[clipIndex].id) {
                project.timeline.tracks[trackIndex].clips[clipIndex].roleId = roleId
            }
        }
    }
}

/// Renames an existing role in `project.roles` while preserving its `UUID` so
/// all clips tagged with `roleId` automatically reflect the new name without
/// re-tagging. Rejects empty names, unknown `roleId`, or collisions with
/// another registered role's name.
public struct RenameTimelineRoleCommand: EditorCommand {
    public let id: UUID
    public var roleId: UUID
    public var newName: String

    public init(id: UUID = UUID(), roleId: UUID, newName: String) {
        self.id = id
        self.roleId = roleId
        self.newName = newName
    }

    public func apply(to project: inout Project) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EditorCommandError.invalidCommand("Role name cannot be empty")
        }
        guard let roleIndex = project.roles.firstIndex(where: { $0.id == roleId }) else {
            throw EditorCommandError.invalidCommand("Unknown role: \(roleId)")
        }
        guard !project.roles.enumerated().contains(where: { $0.offset != roleIndex && $0.element.name == trimmed }) else {
            throw EditorCommandError.invalidCommand("Role name already exists: \(trimmed)")
        }
        project.roles[roleIndex].name = trimmed
    }
}

/// Removes a role from `project.roles` and atomically clears `clip.roleId` on
/// any timeline clip referencing it so no dangling `roleId` remains. Undo via
/// `EditorSession` snapshot restores both the registry entry (at its original
/// order) and all previously tagged clips.
public struct RemoveTimelineRoleCommand: EditorCommand {
    public let id: UUID
    public var roleId: UUID

    public init(id: UUID = UUID(), roleId: UUID) {
        self.id = id
        self.roleId = roleId
    }

    public func apply(to project: inout Project) throws {
        guard let roleIndex = project.roles.firstIndex(where: { $0.id == roleId }) else {
            throw EditorCommandError.invalidCommand("Unknown role: \(roleId)")
        }
        project.roles.remove(at: roleIndex)
        for trackIndex in project.timeline.tracks.indices {
            for clipIndex in project.timeline.tracks[trackIndex].clips.indices
            where project.timeline.tracks[trackIndex].clips[clipIndex].roleId == roleId {
                project.timeline.tracks[trackIndex].clips[clipIndex].roleId = nil
            }
        }
    }
}

