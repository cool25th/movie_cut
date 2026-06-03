import Combine
import Foundation

/// A project collaborator and their access role.
public struct Collaborator: Codable, Sendable, Identifiable, Equatable {
    /// Collaborator identifier.
    public var id: UUID

    /// User-visible collaborator name.
    public var name: String

    /// Access level for the collaborator.
    public var role: CollaborationRole

    /// Creates a collaborator.
    public init(id: UUID = UUID(), name: String, role: CollaborationRole) {
        self.id = id
        self.name = name
        self.role = role
    }
}

/// Collaboration access levels.
public enum CollaborationRole: String, Codable, Sendable, CaseIterable {
    case owner
    case editor
    case viewer
}

/// Share invitation metadata for a project.
public struct ProjectShareLink: Codable, Sendable {
    /// Share link identifier.
    public var id: UUID

    /// Shared project identifier.
    public var projectId: UUID

    /// Collaborators invited through this link.
    public var invitedCollaborators: [Collaborator]

    /// Link creation time.
    public var createdAt: Date

    /// Optional link expiration time.
    public var expiresAt: Date?

    /// Creates project share link metadata.
    public init(
        id: UUID = UUID(),
        projectId: UUID,
        invitedCollaborators: [Collaborator],
        createdAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.invitedCollaborators = invitedCollaborators
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

/// File-based collaboration change event metadata.
public struct ProjectChangeEvent: Codable, Sendable, Identifiable {
    /// Change event identifier.
    public var id: UUID

    /// Collaborator that produced the change.
    public var collaboratorId: UUID

    /// Change creation time.
    public var timestamp: Date

    /// Action name, such as `addClip`, `splitClip`, or `setVolume`.
    public var action: String

    /// Key-value metadata for the change.
    public var details: [String: String]

    /// Creates a project change event.
    public init(
        id: UUID = UUID(),
        collaboratorId: UUID,
        timestamp: Date = Date(),
        action: String,
        details: [String: String]
    ) {
        self.id = id
        self.collaboratorId = collaboratorId
        self.timestamp = timestamp
        self.action = action
        self.details = details
    }
}

/// Multi-user collaboration service backed by file-friendly change events.
public class CollaborationService: ObservableObject, @unchecked Sendable {
    /// Collaborators currently active in the project.
    @Published public private(set) var activeCollaborators: [Collaborator]

    /// Share links that have been created locally and not cleared.
    @Published public private(set) var pendingInvites: [ProjectShareLink]

    /// Most recent local collaboration change events.
    @Published public private(set) var recentChanges: [ProjectChangeEvent]

    /// Local user represented as a collaborator.
    public let localCollaborator: Collaborator

    /// Creates a collaboration service for the local user.
    public init(userName: String) {
        let collaborator = Collaborator(name: userName, role: .owner)
        self.localCollaborator = collaborator
        self.activeCollaborators = [collaborator]
        self.pendingInvites = []
        self.recentChanges = []
    }

    /// Creates a share link for a project and requested role.
    public func createShareLink(projectId: UUID, role: CollaborationRole) -> ProjectShareLink {
        let invitedCollaborator = Collaborator(
            id: localCollaborator.id,
            name: localCollaborator.name,
            role: role
        )
        let link = ProjectShareLink(
            projectId: projectId,
            invitedCollaborators: [invitedCollaborator]
        )
        pendingInvites.append(link)
        return link
    }

    /// Simulates joining a project by adding the local user to the active collaborators.
    public func joinProject(link: ProjectShareLink) async throws {
        let role = link.invitedCollaborators.first { collaborator in
            collaborator.id == localCollaborator.id
        }?.role ?? .editor

        let collaborator = Collaborator(
            id: localCollaborator.id,
            name: localCollaborator.name,
            role: role
        )
        upsertCollaborator(collaborator)
    }

    /// Simulates leaving a project by removing the local user from active collaborators.
    public func leaveProject(projectId: UUID) async throws {
        activeCollaborators.removeAll { collaborator in
            collaborator.id == localCollaborator.id
        }
    }

    /// Records a local project change, retaining only the last 100 events.
    public func recordChange(action: String, details: [String: String]) {
        let event = ProjectChangeEvent(
            collaboratorId: localCollaborator.id,
            action: action,
            details: details
        )

        recentChanges.append(event)
        if recentChanges.count > 100 {
            recentChanges.removeFirst(recentChanges.count - 100)
        }
    }

    /// Returns changes newer than the supplied date.
    public func fetchChanges(since date: Date) -> [ProjectChangeEvent] {
        recentChanges.filter { event in
            event.timestamp > date
        }
    }

    /// Updates an active collaborator's role.
    public func updateRole(collaboratorId: UUID, role: CollaborationRole) {
        guard let index = activeCollaborators.firstIndex(where: { collaborator in
            collaborator.id == collaboratorId
        }) else {
            return
        }

        activeCollaborators[index].role = role
    }

    /// Removes a collaborator from the active collaborator list.
    public func removeCollaborator(collaboratorId: UUID) {
        activeCollaborators.removeAll { collaborator in
            collaborator.id == collaboratorId
        }
    }

    private func upsertCollaborator(_ collaborator: Collaborator) {
        if let index = activeCollaborators.firstIndex(where: { activeCollaborator in
            activeCollaborator.id == collaborator.id
        }) {
            activeCollaborators[index] = collaborator
        } else {
            activeCollaborators.append(collaborator)
        }
    }
}
