import Foundation

/// The editable timeline for a MovieCut project.
public struct Timeline: Codable, Sendable, Equatable, Identifiable {
    /// The timeline identifier.
    public var id: UUID

    /// The project editing frame rate.
    public var frameRate: Rational

    /// The render canvas size.
    public var canvasSize: CGSize

    /// The canvas aspect-ratio preset.
    public var aspectRatio: AspectRatio

    /// Ordered timeline tracks.
    public var tracks: [Track]

    /// User-defined timeline markers.
    public var markers: [Marker]

    /// Creates a timeline with common 1080p defaults.
    public init(
        id: UUID = UUID(),
        frameRate: Rational = Rational(numerator: 30, denominator: 1),
        canvasSize: CGSize = CGSize(width: 1920, height: 1080),
        aspectRatio: AspectRatio = .landscape16x9,
        tracks: [Track] = [],
        markers: [Marker] = []
    ) {
        self.id = id
        self.frameRate = frameRate
        self.canvasSize = canvasSize
        self.aspectRatio = aspectRatio
        self.tracks = tracks
        self.markers = markers
    }

    /// The timeline duration derived from the furthest clip end time.
    public var duration: TimeInterval {
        tracks
            .flatMap(\.clips)
            .map(\.timelineRange.end)
            .max() ?? 0
    }
}
