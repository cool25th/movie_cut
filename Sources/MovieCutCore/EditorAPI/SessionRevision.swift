import Foundation

/// Monotonically increasing session revision identifying an exact edit generation.
///
/// Used to guard against applying stale plans when asynchronous planning (e.g., AI/VLM,
/// background media probes) runs concurrently with user edits.
public struct SessionRevision: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    /// A unique identifier for the lifetime/epoch of an `EditorSession`.
    public let epoch: UUID
    /// Monotonically increasing revision counter within this session epoch.
    public let value: UInt64

    /// Creates a session revision token.
    public init(epoch: UUID = UUID(), value: UInt64 = 0) {
        self.epoch = epoch
        self.value = value
    }

    /// Returns the next revision in the sequence.
    public func advanced() -> SessionRevision {
        SessionRevision(epoch: epoch, value: value + 1)
    }

    public var description: String {
        "SessionRevision(epoch: \(epoch.uuidString.prefix(8)), value: \(value))"
    }
}
