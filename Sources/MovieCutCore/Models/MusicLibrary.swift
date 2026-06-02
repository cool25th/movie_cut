import Foundation

/// A music item available for timeline insertion.
public struct MusicTrack: Codable, Sendable, Equatable, Identifiable {
    /// The track identifier.
    public var id: UUID

    /// The user-visible title.
    public var title: String

    /// The artist or source attribution.
    public var artist: String

    /// The track duration in seconds.
    public var duration: TimeInterval

    /// The local audio file URL.
    public var fileURL: URL

    /// Genre and mood tags used by filtering.
    public var tags: [String]

    /// Whether the track is bundled with the app.
    public var isBuiltIn: Bool

    /// Creates a music track.
    public init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        duration: TimeInterval,
        fileURL: URL,
        tags: [String] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.fileURL = fileURL
        self.tags = tags
        self.isBuiltIn = isBuiltIn
    }
}

/// A searchable collection of background music tracks.
public struct MusicLibrary: Codable, Sendable, Equatable {
    /// Available music tracks.
    public var tracks: [MusicTrack]

    /// Creates a music library.
    public init(tracks: [MusicTrack] = []) {
        self.tracks = tracks
    }

    /// Example tracks used until the app ships a bundled catalog.
    public static func placeholder() -> MusicLibrary {
        MusicLibrary(tracks: [
            MusicTrack(
                title: "Bright Pop Cue",
                artist: "MovieCut",
                duration: 28,
                fileURL: URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff"),
                tags: ["pop", "bright", "intro"],
                isBuiltIn: true
            ),
            MusicTrack(
                title: "Soft Ambient Bed",
                artist: "MovieCut",
                duration: 42,
                fileURL: URL(fileURLWithPath: "/System/Library/Sounds/Submarine.aiff"),
                tags: ["ambient", "calm", "background"],
                isBuiltIn: true
            ),
            MusicTrack(
                title: "Upbeat Marker",
                artist: "MovieCut",
                duration: 16,
                fileURL: URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff"),
                tags: ["upbeat", "short", "social"],
                isBuiltIn: true
            )
        ])
    }

    /// Returns tracks whose title, artist, or tags contain the query.
    public func search(query: String) -> [MusicTrack] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return tracks
        }

        return tracks.filter { track in
            track.title.lowercased().contains(normalizedQuery)
                || track.artist.lowercased().contains(normalizedQuery)
                || track.tags.contains { $0.lowercased().contains(normalizedQuery) }
        }
    }

    /// Returns tracks tagged with the supplied exact tag, case-insensitively.
    public func tracks(tagged tag: String) -> [MusicTrack] {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTag.isEmpty else { return [] }

        return tracks.filter { track in
            track.tags.contains { $0.lowercased() == normalizedTag }
        }
    }
}
