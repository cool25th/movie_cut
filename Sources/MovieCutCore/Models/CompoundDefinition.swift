import Foundation

/// Definition of a compound clip (Inc 1 — a single-level nesting unit with no
/// internal editing). Holds the constituent child clips whose `timelineRange`
/// values are stored **relative to the compound's own zero point**. When a
/// container clip in the timeline carries the matching `compoundId`, the flatten
/// pass (`Task 5.8`) expands the container into these children shifted by the
/// container's timeline start, so moving/trimming/copying the container
/// preserves the internal composition relatively (Requirement 7.2).
///
/// **No nesting (Requirement 7.3 deferral).** Inc 1 forbids nesting: no child
/// clip may itself carry a `compoundId`. This is enforced at creation time
/// (`CreateCompoundClipCommand`) and re-checked at load time
/// (`Project.validateCompounds`). The flatten pass is therefore a single-level,
/// non-recursive expansion.
///
/// `currentSchemaVersion` is intentionally not bumped for this additive field:
/// `compounds` decodes to `[]` and `Clip.compoundId` decodes to `nil` for
/// legacy projects, so a compound-free fixture stays byte-identical. The schema
/// bump is deferred to task 6.
public struct CompoundDefinition: Codable, Sendable, Equatable, Identifiable {
    /// The compound definition identifier. `Clip.compoundId` references this.
    public var id: UUID

    /// The user-visible compound name.
    public var name: String

    /// The constituent clips, with `timelineRange` stored relative to the
    /// compound's local zero. None may carry a `compoundId` (no nesting).
    public var childClips: [Clip]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case childClips
    }

    /// Creates a compound definition.
    public init(
        id: UUID = UUID(),
        name: String,
        childClips: [Clip]
    ) {
        self.id = id
        self.name = name
        self.childClips = childClips
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // decodeIfPresent ?? [] so legacy files and partial payloads still load.
        childClips = try container.decodeIfPresent([Clip].self, forKey: .childClips) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(childClips, forKey: .childClips)
    }
}
