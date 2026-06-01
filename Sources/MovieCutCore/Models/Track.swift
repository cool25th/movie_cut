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

    /// Whether edit commands should avoid modifying this track.
    public var isLocked: Bool

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
        isLocked: Bool = false,
        zIndex: Int = 0,
        clips: [Clip] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.isMuted = isMuted
        self.isLocked = isLocked
        self.zIndex = zIndex
        self.clips = clips
    }
}
