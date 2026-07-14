import Foundation

/// A deterministic source-time request for one filmstrip tile.
public struct FilmstripFrameRequest: Sendable, Equatable {
    /// Zero-based display order in the generated strip.
    public var index: Int

    /// Source-media time in seconds.
    public var time: TimeInterval

    public init(index: Int, time: TimeInterval) {
        self.index = index
        self.time = time
    }
}

/// Pure request planning shared by the app generator and behavioral tests.
public enum FilmstripRequestPlanner {
    /// Places requests at equal-width tile centers inside the source range.
    ///
    /// Center sampling avoids requesting the exclusive end time while ensuring
    /// the first and last tiles represent the full trimmed source interval.
    public static func requests(
        sourceRange: TimeRange,
        targetCount: Int
    ) -> [FilmstripFrameRequest] {
        guard targetCount > 0,
              sourceRange.start.isFinite,
              sourceRange.duration.isFinite,
              sourceRange.start >= 0,
              sourceRange.duration > 0 else {
            return []
        }

        let step = sourceRange.duration / Double(targetCount)
        return (0..<targetCount).map { index in
            FilmstripFrameRequest(
                index: index,
                time: sourceRange.start + (Double(index) + 0.5) * step
            )
        }
    }
}

/// Four discrete cache/density levels for MovieCut's supported 20...300 px/s
/// timeline zoom range. Bucket boundaries double so small zoom changes do not
/// continuously invalidate decoded filmstrips.
public enum FilmstripZoomBucket: Int, CaseIterable, Sendable {
    case level0 = 0
    case level1 = 1
    case level2 = 2
    case level3 = 3

    public static func bucket(for pixelsPerSecond: Double) -> Self {
        guard pixelsPerSecond.isFinite, pixelsPerSecond > 0 else {
            return .level0
        }

        switch pixelsPerSecond {
        case ..<40: return .level0
        case ..<80: return .level1
        case ..<160: return .level2
        default: return .level3
        }
    }
}

/// Stable cache identity shared by the app cache and its behavioral harness.
public struct FilmstripCacheKey: Hashable, Sendable {
    public var assetID: UUID
    public var zoomBucket: FilmstripZoomBucket

    public init(assetID: UUID, zoomBucket: FilmstripZoomBucket) {
        self.assetID = assetID
        self.zoomBucket = zoomBucket
    }
}
