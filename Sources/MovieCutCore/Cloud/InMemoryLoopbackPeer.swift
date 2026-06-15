import Foundation

/// A serialized, in-process message queue shared by a connected peer pair.
private actor LoopbackMailbox {
    private var messages: [CollaborationMessage] = []

    func enqueue(_ message: CollaborationMessage) {
        messages.append(message)
    }

    func dequeue() -> CollaborationMessage? {
        messages.isEmpty ? nil : messages.removeFirst()
    }

    var count: Int { messages.count }
}

/// A working, in-process duplex transport conforming to ``NearbyPeer``.
///
/// Before this type, `NearbyPeer` had no concrete implementation, so
/// `CollaborationService` could not actually move a message between two
/// instances — join/leave were simulated. `InMemoryLoopbackPeer` provides a real
/// transport: create a connected pair with ``makePair(idA:idB:)``; a message
/// sent on one endpoint becomes available to receive on the other, and never on
/// the sender. It powers same-process collaboration (multi-window, previews) and
/// gives the collaboration pipeline an end-to-end testable transport, while a
/// radio transport (MultipeerConnectivity / Network framework) can adopt the same
/// protocol later.
public final class InMemoryLoopbackPeer: NearbyPeer, Sendable {
    /// The peer identifier.
    public let id: UUID

    /// Messages this endpoint receives (the partner's outbox).
    private let inbox: LoopbackMailbox

    /// Messages this endpoint sends (delivered to the partner's inbox).
    private let outbox: LoopbackMailbox

    private init(id: UUID, inbox: LoopbackMailbox, outbox: LoopbackMailbox) {
        self.id = id
        self.inbox = inbox
        self.outbox = outbox
    }

    /// Creates a connected pair of loopback peers.
    ///
    /// Messages sent on the first endpoint are received by the second, and vice
    /// versa. The two directions are independent FIFO channels.
    public static func makePair(
        idA: UUID = UUID(),
        idB: UUID = UUID()
    ) -> (InMemoryLoopbackPeer, InMemoryLoopbackPeer) {
        let channelAToB = LoopbackMailbox()
        let channelBToA = LoopbackMailbox()
        let peerA = InMemoryLoopbackPeer(id: idA, inbox: channelBToA, outbox: channelAToB)
        let peerB = InMemoryLoopbackPeer(id: idB, inbox: channelAToB, outbox: channelBToA)
        return (peerA, peerB)
    }

    /// Sends a message to the connected partner.
    public func sendMessage(_ message: CollaborationMessage) async throws {
        await outbox.enqueue(message)
    }

    /// Returns the next pending message from the partner, or `nil` when none is
    /// queued (non-blocking, matching the polling contract of `NearbyPeer`).
    public func receiveMessage() async throws -> CollaborationMessage? {
        await inbox.dequeue()
    }

    /// The number of messages still queued for this endpoint to receive.
    public var pendingReceiveCount: Int {
        get async { await inbox.count }
    }
}

extension CollaborationService {
    /// Announces the local collaborator joining to a connected peer, so the
    /// remote service registers this user instead of relying on a simulated join.
    public func announceJoin(via peer: any NearbyPeer) async throws {
        let payload = try JSONEncoder().encode(localCollaborator)
        let message = CollaborationMessage(
            type: .join,
            senderId: localCollaborator.id,
            payload: payload
        )
        try await peer.sendMessage(message)
    }

    /// Announces the local collaborator leaving to a connected peer.
    public func announceLeave(via peer: any NearbyPeer) async throws {
        let message = CollaborationMessage(
            type: .leave,
            senderId: localCollaborator.id,
            payload: Data()
        )
        try await peer.sendMessage(message)
    }
}
