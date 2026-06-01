import Foundation

/// A named marker placed on the timeline.
public struct Marker: Codable, Sendable, Equatable, Identifiable {
    /// The marker identifier.
    public var id: UUID

    /// The marker time in seconds.
    public var time: TimeInterval

    /// The user-visible marker name.
    public var name: String

    /// An optional hex color string for display.
    public var color: String?

    /// Creates a timeline marker.
    public init(
        id: UUID = UUID(),
        time: TimeInterval,
        name: String,
        color: String? = nil
    ) {
        self.id = id
        self.time = time
        self.name = name
        self.color = color
    }
}
