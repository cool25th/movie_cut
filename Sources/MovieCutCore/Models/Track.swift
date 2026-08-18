import Foundation

/// The supported track types for Phase 0 and Phase 1 editing.
public enum TrackKind: String, Codable, Sendable, Equatable, Hashable {
    /// A video track.
    case video

    /// An audio track.
    case audio

    /// A text overlay track.
    case text
}

/// A timeline layer that owns clips of a related kind.
public struct Track: Codable, Sendable, Equatable, Identifiable {
    /// The track identifier.
    public var id: UUID

    /// The track kind.
    public var kind: TrackKind

    /// The user-visible track name.
    public var name: String

    /// Whether playback should silence this track.
    public var isMuted: Bool

    /// Audio solo (G-25 Inc 9): when ANY track is soloed, every non-solo
    /// track's audio is silenced (mute silences one track; solo is the
    /// inverse — "hear only this"). Video content is unaffected; solo is an
    /// audio-mixing concept, matching `AudioGraphTrackBus.solo` in the
    /// render graph.
    public var isSolo: Bool

    /// Whether edit commands should avoid modifying this track.
    public var isLocked: Bool

    /// Whether this track should be hidden from preview/export visuals.
    public var isHidden: Bool

    /// The compositing or ordering index.
    public var zIndex: Int

    /// Clips placed on the track.
    public var clips: [Clip]

    /// Creates a timeline track.
    public init(
        id: UUID = UUID(),
        kind: TrackKind,
        name: String,
        isMuted: Bool = false,
        isSolo: Bool = false,
        isLocked: Bool = false,
        isHidden: Bool = false,
        zIndex: Int = 0,
        clips: [Clip] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.isLocked = isLocked
        self.isHidden = isHidden
        self.zIndex = zIndex
        self.clips = clips
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, isMuted, isSolo, isLocked, isHidden, zIndex, clips
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(TrackKind.self, forKey: .kind)
        name = try container.decode(String.self, forKey: .name)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        // Added in schema v5: pre-v5 projects decode with solo off.
        isSolo = try container.decodeIfPresent(Bool.self, forKey: .isSolo) ?? false
        isLocked = try container.decode(Bool.self, forKey: .isLocked)
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
        zIndex = try container.decode(Int.self, forKey: .zIndex)
        clips = try container.decode([Clip].self, forKey: .clips)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(isSolo, forKey: .isSolo)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(zIndex, forKey: .zIndex)
        try container.encode(clips, forKey: .clips)
    }
}
