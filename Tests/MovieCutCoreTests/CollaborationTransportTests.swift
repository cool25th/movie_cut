import Foundation
import Testing
@testable import MovieCutCore

@Suite("Collaboration Transport")
struct CollaborationTransportTests {
    @Test("Loopback delivers one direction and drains, never echoing to the sender")
    func loopbackDelivery() async throws {
        let (peerA, peerB) = InMemoryLoopbackPeer.makePair()
        let message = CollaborationMessage(type: .heartbeat, senderId: peerA.id, payload: Data("hi".utf8))

        try await peerA.sendMessage(message)

        let received = try await peerB.receiveMessage()
        #expect(received?.payload == Data("hi".utf8))
        // The channel is drained after one receive.
        #expect(try await peerB.receiveMessage() == nil)
        // The sender never receives its own message.
        #expect(try await peerA.receiveMessage() == nil)
    }

    @Test("Loopback preserves FIFO order within a direction")
    func loopbackOrdering() async throws {
        let (peerA, peerB) = InMemoryLoopbackPeer.makePair()
        for index in 0..<3 {
            try await peerA.sendMessage(
                CollaborationMessage(type: .change, senderId: peerA.id, payload: Data("\(index)".utf8))
            )
        }

        var received: [String] = []
        while let message = try await peerB.receiveMessage() {
            received.append(String(data: message.payload, encoding: .utf8) ?? "")
        }
        #expect(received == ["0", "1", "2"])
    }

    @MainActor
    @Test("A change broadcast over loopback is applied by the receiving service")
    func endToEndChange() async throws {
        let serviceA = CollaborationService(userName: "A")
        let serviceB = CollaborationService(userName: "B")
        let (peerForA, peerForB) = InMemoryLoopbackPeer.makePair()

        let event = ProjectChangeEvent(
            collaboratorId: serviceA.localCollaborator.id,
            action: "splitClip",
            details: ["clipId": "42"]
        )
        try await serviceA.broadcastChange(event, via: peerForA)

        let delivered = try await serviceB.receiveMessage(from: peerForB)
        #expect(delivered != nil)
        #expect(serviceB.recentChanges.contains { $0.action == "splitClip" })
        // The receiver now tracks the sender as present.
        #expect(serviceB.collaboratorPresence[serviceA.localCollaborator.id]?.isActive == true)
    }

    @MainActor
    @Test("A join announcement registers the remote collaborator on the receiver")
    func endToEndJoin() async throws {
        let serviceA = CollaborationService(userName: "A")
        let serviceB = CollaborationService(userName: "B")
        let (peerForA, peerForB) = InMemoryLoopbackPeer.makePair()

        try await serviceA.announceJoin(via: peerForA)
        _ = try await serviceB.receiveMessage(from: peerForB)

        #expect(serviceB.activeCollaborators.contains { $0.id == serviceA.localCollaborator.id })
    }
}
