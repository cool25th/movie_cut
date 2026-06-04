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

/// Collaboration message categories exchanged with nearby peers.
public enum MessageType: String, Codable, Sendable {
    case change
    case join
    case leave
    case sync
}

/// Wire format for local collaboration messages.
public struct CollaborationMessage: Codable, Sendable {
    /// Message category.
    public var type: MessageType

    /// Sender collaborator identifier.
    public var senderId: UUID

    /// Encoded payload appropriate for the message type.
    public var payload: Data

    /// Creates a collaboration message.
    public init(type: MessageType, senderId: UUID, payload: Data) {
        self.type = type
        self.senderId = senderId
        self.payload = payload
    }
}

/// A nearby transport endpoint that can exchange collaboration messages.
public protocol NearbyPeer: Sendable {
    /// Peer identifier.
    var id: UUID { get }

    /// Sends a collaboration message to this peer.
    func sendMessage(_ message: CollaborationMessage) async throws

    /// Receives the next pending collaboration message from this peer.
    func receiveMessage() async throws -> CollaborationMessage?
}

/// Activity state for a collaborator.
public struct CollaboratorPresence: Codable, Sendable, Equatable {
    /// Whether the collaborator is currently considered active.
    public var isActive: Bool

    /// Most recent observed activity time.
    public var lastSeen: Date

    /// Creates collaborator presence metadata.
    public init(isActive: Bool, lastSeen: Date = Date()) {
        self.isActive = isActive
        self.lastSeen = lastSeen
    }
}

/// Multi-user collaboration service backed by file-friendly change events.
@MainActor
public class CollaborationService: ObservableObject, Sendable {
    /// Collaborators currently active in the project.
    @Published public private(set) var activeCollaborators: [Collaborator]

    /// Share links that have been created locally and not cleared.
    @Published public private(set) var pendingInvites: [ProjectShareLink]

    /// Most recent local collaboration change events.
    @Published public private(set) var recentChanges: [ProjectChangeEvent]

    /// Presence state keyed by collaborator identifier.
    @Published public private(set) var collaboratorPresence: [UUID: CollaboratorPresence]

    /// Local user represented as a collaborator.
    public let localCollaborator: Collaborator

    private var nearbyPeers: [UUID: any NearbyPeer]
    private var presenceHeartbeatTask: Task<Void, Never>?

    /// Creates a collaboration service for the local user.
    public init(userName: String) {
        let collaborator = Collaborator(name: userName, role: .owner)
        self.localCollaborator = collaborator
        self.activeCollaborators = [collaborator]
        self.pendingInvites = []
        self.recentChanges = []
        self.collaboratorPresence = [
            collaborator.id: CollaboratorPresence(isActive: true)
        ]
        self.nearbyPeers = [:]
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
        touchPresence(for: collaborator.id)
    }

    /// Simulates leaving a project by removing the local user from active collaborators.
    public func leaveProject(projectId: UUID) async throws {
        activeCollaborators.removeAll { collaborator in
            collaborator.id == localCollaborator.id
        }
        collaboratorPresence[localCollaborator.id] = CollaboratorPresence(isActive: false)
    }

    /// Records a local project change, retaining only the last 100 events.
    public func recordChange(action: String, details: [String: String]) {
        let event = ProjectChangeEvent(
            collaboratorId: localCollaborator.id,
            action: action,
            details: details
        )

        appendChange(event)
        touchPresence(for: localCollaborator.id)
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
        collaboratorPresence[collaboratorId] = CollaboratorPresence(isActive: false)
    }

    /// Registers a nearby peer for collaboration message exchange.
    public func addPeer(_ peer: any NearbyPeer) {
        nearbyPeers[peer.id] = peer
    }

    /// Removes a nearby peer from collaboration message exchange.
    public func removePeer(peerId: UUID) {
        nearbyPeers.removeValue(forKey: peerId)
    }

    /// Sends a collaboration message to a nearby peer.
    public func sendMessage(_ message: CollaborationMessage, to peer: any NearbyPeer) async throws {
        try await peer.sendMessage(message)
    }

    /// Receives and applies the next collaboration message from a nearby peer.
    @discardableResult
    public func receiveMessage(from peer: any NearbyPeer) async throws -> CollaborationMessage? {
        guard let message = try await peer.receiveMessage() else {
            return nil
        }

        try handleReceivedMessage(message)
        return message
    }

    /// Broadcasts a project change event to all registered peers.
    public func broadcastChange(event: ProjectChangeEvent) async throws {
        let payload = try JSONEncoder().encode(event)
        let message = CollaborationMessage(
            type: .change,
            senderId: localCollaborator.id,
            payload: payload
        )

        appendChange(event)

        for peer in Array(nearbyPeers.values) {
            try await sendMessage(message, to: peer)
        }
    }

    /// Returns a merged change event placeholder for future operation transform conflict handling.
    public func transformOperation(local: ProjectChangeEvent, remote: ProjectChangeEvent) -> ProjectChangeEvent {
        var details = remote.details
        local.details.forEach { key, value in
            details[key] = value
        }
        details["localEventId"] = local.id.uuidString
        details["remoteEventId"] = remote.id.uuidString

        return ProjectChangeEvent(
            collaboratorId: local.collaboratorId,
            timestamp: max(local.timestamp, remote.timestamp),
            action: local.action == remote.action ? local.action : "merged",
            details: details
        )
    }

    /// Starts periodic heartbeat updates for collaborator presence.
    public func startPresenceHeartbeat() {
        presenceHeartbeatTask?.cancel()
        presenceHeartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    break
                }

                self.refreshPresence()

                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    break
                }
            }
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

        touchPresence(for: collaborator.id)
    }

    private func appendChange(_ event: ProjectChangeEvent) {
        guard !recentChanges.contains(where: { $0.id == event.id }) else {
            return
        }

        recentChanges.append(event)
        if recentChanges.count > 100 {
            recentChanges.removeFirst(recentChanges.count - 100)
        }
    }

    private func handleReceivedMessage(_ message: CollaborationMessage) throws {
        touchPresence(for: message.senderId)

        let decoder = JSONDecoder()

        switch message.type {
        case .change:
            let event = try decoder.decode(ProjectChangeEvent.self, from: message.payload)
            appendChange(event)
        case .join:
            if let collaborator = try? decoder.decode(Collaborator.self, from: message.payload) {
                upsertCollaborator(collaborator)
            }
        case .leave:
            removeCollaborator(collaboratorId: message.senderId)
        case .sync:
            if let events = try? decoder.decode([ProjectChangeEvent].self, from: message.payload) {
                events.forEach { appendChange($0) }
            } else if let event = try? decoder.decode(ProjectChangeEvent.self, from: message.payload) {
                appendChange(event)
            }
        }
    }

    private func touchPresence(for collaboratorId: UUID, at date: Date = Date()) {
        collaboratorPresence[collaboratorId] = CollaboratorPresence(isActive: true, lastSeen: date)
    }

    private func refreshPresence(now: Date = Date()) {
        touchPresence(for: localCollaborator.id, at: now)

        for collaboratorId in collaboratorPresence.keys {
            guard collaboratorId != localCollaborator.id,
                  let presence = collaboratorPresence[collaboratorId] else {
                continue
            }

            let isActive = now.timeIntervalSince(presence.lastSeen) <= 30
            collaboratorPresence[collaboratorId] = CollaboratorPresence(
                isActive: isActive,
                lastSeen: presence.lastSeen
            )
        }
    }
}
