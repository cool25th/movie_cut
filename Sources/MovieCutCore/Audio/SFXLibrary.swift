import Foundation

/// A sound effect available for timeline insertion.
public struct SFXItem: Codable, Sendable, Identifiable, Equatable {
    /// The sound effect identifier.
    public var id: UUID

    /// The user-visible sound effect name.
    public var name: String

    /// The sound effect category.
    public var category: String

    /// The bundled audio file name.
    public var fileName: String

    /// Creates a sound effect library item.
    public init(id: UUID = UUID(), name: String, category: String, fileName: String) {
        self.id = id
        self.name = name
        self.category = category
        self.fileName = fileName
    }
}

/// A searchable collection of built-in sound effects.
public struct SFXLibrary: Sendable {
    /// Creates a sound effects library helper.
    public init() {}

    /// Built-in sound effects available until the app ships a bundled catalog.
    public static var all: [SFXItem] {
        [
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                name: "Soft Whoosh",
                category: "whoosh",
                fileName: "whoosh_soft.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
                name: "Fast Whoosh",
                category: "whoosh",
                fileName: "whoosh_fast.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                name: "Mouse Click",
                category: "click",
                fileName: "click_mouse.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                name: "Camera Click",
                category: "click",
                fileName: "click_camera.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                name: "Bubble Pop",
                category: "pop",
                fileName: "pop_bubble.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                name: "Soft Pop",
                category: "pop",
                fileName: "pop_soft.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
                name: "Bright Ding",
                category: "ding",
                fileName: "ding_bright.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
                name: "Bell Ding",
                category: "ding",
                fileName: "ding_bell.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
                name: "Deep Boom",
                category: "boom",
                fileName: "boom_deep.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
                name: "Impact Boom",
                category: "boom",
                fileName: "boom_impact.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
                name: "Message Notification",
                category: "notification",
                fileName: "notification_message.wav"
            ),
            SFXItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000602")!,
                name: "Alert Notification",
                category: "notification",
                fileName: "notification_alert.wav"
            )
        ]
    }

    /// Returns built-in sound effects grouped by category.
    public static func categorized() -> [String: [SFXItem]] {
        Dictionary(grouping: all, by: \.category)
    }

    /// Returns sound effects whose name, category, or file name contains the query.
    public static func search(query: String) -> [SFXItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return all
        }

        return all.filter { item in
            item.name.lowercased().contains(normalizedQuery)
                || item.category.lowercased().contains(normalizedQuery)
                || item.fileName.lowercased().contains(normalizedQuery)
        }
    }
}
