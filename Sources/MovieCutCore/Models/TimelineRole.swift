import Foundation

/// CA-20 stage 1 (W4 장편 관리): a user-defined role clips can be tagged
/// with — FCP "roles". The role registry lives on the project; clips
/// reference a role by id. Names are unique within a project (the command
/// layer enforces it); `colorHex` drives the per-role lane tint planned
/// for the timeline UI (stage 2).
public struct TimelineRole: Codable, Sendable, Equatable, Identifiable {
    /// The role identity — what `Clip.roleId` references. Stable across
    /// renames (unlike name-keyed references, which would need cascading
    /// rewrite on every rename).
    public var id: UUID

    /// The user-visible role name ("Dialogue", "Music", …), unique per
    /// project.
    public var name: String

    /// The lane tint as "#RRGGBB".
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }

    /// The FCP-style starting set (dialogue / music / effects / other) the
    /// role UI offers first. Static presets carry STABLE ids so projects
    /// created through them share role ids where possible.
    public static let presets: [TimelineRole] = [
        TimelineRole(id: UUID(uuidString: "00000000-CA20-0000-0000-00000000D101")!, name: "Dialogue", colorHex: "#4C9BE8"),
        TimelineRole(id: UUID(uuidString: "00000000-CA20-0000-0000-00000000D102")!, name: "Music", colorHex: "#E84C8F"),
        TimelineRole(id: UUID(uuidString: "00000000-CA20-0000-0000-00000000D103")!, name: "Effects", colorHex: "#E8A84C"),
        TimelineRole(id: UUID(uuidString: "00000000-CA20-0000-0000-00000000D104")!, name: "Other", colorHex: "#9B9B9B")
    ]
}
