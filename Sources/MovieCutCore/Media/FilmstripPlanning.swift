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

/// A quantized clip-local window that is worth decoding for the timeline.
///
/// The window is expressed in both clip pixels and source time so the UI can
/// position the decoded frames without treating the whole clip as visible.
public struct FilmstripViewportRequest: Hashable, Sendable {
    public var sourceRange: TimeRange
    public var localStartX: Double
    public var localWidth: Double
    public var targetCount: Int
    public var fullTargetCount: Int
    public var zoomBucket: FilmstripZoomBucket
    public var zoomScaleKey: Int

    public init(
        sourceRange: TimeRange,
        localStartX: Double,
        localWidth: Double,
        targetCount: Int,
        fullTargetCount: Int,
        zoomBucket: FilmstripZoomBucket,
        zoomScaleKey: Int
    ) {
        self.sourceRange = sourceRange
        self.localStartX = localStartX
        self.localWidth = localWidth
        self.targetCount = targetCount
        self.fullTargetCount = fullTargetCount
        self.zoomBucket = zoomBucket
        self.zoomScaleKey = zoomScaleKey
    }
}

/// Maps a clip's actual frame inside the horizontal timeline viewport to the
/// source-time window that should be decoded.
///
/// The viewport is expanded by half a screen on each side to avoid visible
/// pop-in. Pixel bounds are quantized to tile boundaries so ordinary scrolling
/// does not restart decoding for every single pixel. Returning `nil` is an
/// explicit offscreen decision, not an empty full-clip request.
public enum FilmstripViewportPlanner {
    public static let defaultPrefetchViewportFraction = 0.5
    public static let defaultMaximumFrameCount = 32

    public static func request(
        clipMinX: Double,
        clipWidth: Double,
        viewportWidth: Double,
        sourceRange: TimeRange,
        pixelsPerSecond: Double,
        tileWidth: Double,
        prefetchViewportFraction: Double = defaultPrefetchViewportFraction,
        maximumFrameCount: Int = defaultMaximumFrameCount
    ) -> FilmstripViewportRequest? {
        guard clipMinX.isFinite,
              clipWidth.isFinite,
              clipWidth > 0,
              viewportWidth.isFinite,
              viewportWidth > 0,
              sourceRange.start.isFinite,
              sourceRange.start >= 0,
              sourceRange.duration.isFinite,
              sourceRange.duration > 0,
              pixelsPerSecond.isFinite,
              pixelsPerSecond > 0,
              tileWidth.isFinite,
              tileWidth > 0,
              prefetchViewportFraction.isFinite,
              prefetchViewportFraction >= 0,
              maximumFrameCount > 0 else {
            return nil
        }

        let prefetchWidth = viewportWidth * prefetchViewportFraction
        let nearViewportStart = -prefetchWidth
        let nearViewportEnd = viewportWidth + prefetchWidth
        let clipMaxX = clipMinX + clipWidth
        let intersectionStart = max(clipMinX, nearViewportStart)
        let intersectionEnd = min(clipMaxX, nearViewportEnd)
        guard intersectionEnd > intersectionStart else { return nil }

        let rawLocalStart = max(0, intersectionStart - clipMinX)
        let rawLocalEnd = min(clipWidth, intersectionEnd - clipMinX)
        let quantizedLocalStart = max(0, floor(rawLocalStart / tileWidth) * tileWidth)
        let quantizedLocalEnd = min(clipWidth, ceil(rawLocalEnd / tileWidth) * tileWidth)
        let localWidth = quantizedLocalEnd - quantizedLocalStart
        guard localWidth > 0 else { return nil }

        let startFraction = quantizedLocalStart / clipWidth
        let durationFraction = localWidth / clipWidth
        let requestedSourceRange = TimeRange(
            start: sourceRange.start + sourceRange.duration * startFraction,
            duration: min(
                sourceRange.duration * durationFraction,
                sourceRange.end - (sourceRange.start + sourceRange.duration * startFraction)
            )
        )
        guard requestedSourceRange.duration > 0 else { return nil }

        let fullTargetCount = max(1, Int(ceil(clipWidth / tileWidth)))
        let targetCount = min(
            maximumFrameCount,
            max(1, Int(ceil(localWidth / tileWidth)))
        )
        let scaledZoom = (pixelsPerSecond * 1_000).rounded()
        let zoomScaleKey = scaledZoom >= Double(Int.max)
            ? Int.max
            : Int(scaledZoom)

        return FilmstripViewportRequest(
            sourceRange: requestedSourceRange,
            localStartX: quantizedLocalStart,
            localWidth: localWidth,
            targetCount: targetCount,
            fullTargetCount: fullTargetCount,
            zoomBucket: FilmstripZoomBucket.bucket(for: pixelsPerSecond),
            zoomScaleKey: zoomScaleKey
        )
    }
}

/// A cache-only hover result for a timeline filmstrip.
public struct FilmstripHoverSelection: Sendable, Equatable {
    /// Source time represented by the pointer position.
    public var requestedSourceTime: TimeInterval

    /// Index in the caller's already-published frame array.
    public var frameIndex: Int

    /// Actual decoded source timestamp for the selected cached frame.
    public var frameSourceTime: TimeInterval

    public init(
        requestedSourceTime: TimeInterval,
        frameIndex: Int,
        frameSourceTime: TimeInterval
    ) {
        self.requestedSourceTime = requestedSourceTime
        self.frameIndex = frameIndex
        self.frameSourceTime = frameSourceTime
    }
}

/// Pure pointer-to-source-time and nearest-cached-frame planning.
///
/// This planner has no generation seam by design: an empty/not-ready timestamp
/// array returns `nil`, so hover cannot synchronously decode or enqueue frames.
public enum FilmstripHoverPlanner {
    public static func selection(
        localX: Double,
        clipWidth: Double,
        sourceRange: TimeRange,
        timelineDuration: TimeInterval,
        playbackRate: Double,
        speedRampPoints: [SpeedRampPoint] = [],
        cachedFrameTimes: [TimeInterval]
    ) -> FilmstripHoverSelection? {
        guard localX.isFinite,
              clipWidth.isFinite,
              clipWidth > 0,
              sourceRange.start.isFinite,
              sourceRange.start >= 0,
              sourceRange.duration.isFinite,
              sourceRange.duration > 0,
              timelineDuration.isFinite,
              timelineDuration > 0,
              playbackRate.isFinite,
              playbackRate > 0,
              speedRampPoints.allSatisfy({
                  $0.time.isFinite && $0.rate.isFinite && $0.rate > 0
              }) else {
            return nil
        }

        let clampedX = min(max(localX, 0), clipWidth)
        let timelineOffset = (clampedX / clipWidth) * timelineDuration
        let sourceOffset: TimeInterval
        if speedRampPoints.count >= 2 {
            let normalizedOutputTime = timelineOffset / sourceRange.duration
            let normalizedSourceTime = SpeedRampCurve(points: speedRampPoints)
                .inverseMapping(outputTime: normalizedOutputTime)
            sourceOffset = normalizedSourceTime * sourceRange.duration
        } else {
            sourceOffset = timelineOffset * playbackRate
        }
        guard sourceOffset.isFinite else { return nil }

        let requestedSourceTime = sourceRange.start
            + min(max(sourceOffset, 0), sourceRange.duration)
        var nearest: (index: Int, time: TimeInterval, distance: TimeInterval)?
        for (index, frameTime) in cachedFrameTimes.enumerated() where frameTime.isFinite {
            let distance = abs(frameTime - requestedSourceTime)
            guard let current = nearest else {
                nearest = (index, frameTime, distance)
                continue
            }
            if distance < current.distance
                || (distance == current.distance && frameTime < current.time)
                || (distance == current.distance && frameTime == current.time && index < current.index) {
                nearest = (index, frameTime, distance)
            }
        }

        guard let nearest else { return nil }
        return FilmstripHoverSelection(
            requestedSourceTime: requestedSourceTime,
            frameIndex: nearest.index,
            frameSourceTime: nearest.time
        )
    }
}

/// Request lifecycle used by the app coordinator and exercised independently
/// of AVFoundation. Only the currently active generation may publish frames.
public struct FilmstripLoadState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case fallback
        case loading(generation: UInt64)
        case ready(generation: UInt64, frameCount: Int)
        case failed(generation: UInt64)
        case cancelled(generation: UInt64)
    }

    public private(set) var phase: Phase = .fallback
    public private(set) var currentGeneration: UInt64 = 0

    public init() {}

    public var showsFallbackThumbnail: Bool {
        guard case .ready(_, let frameCount) = phase else { return true }
        return frameCount <= 0
    }

    @discardableResult
    public mutating func begin() -> UInt64 {
        currentGeneration &+= 1
        phase = .loading(generation: currentGeneration)
        return currentGeneration
    }

    @discardableResult
    public mutating func accept(frameCount: Int, generation: UInt64) -> Bool {
        guard case .loading(let activeGeneration) = phase,
              activeGeneration == generation,
              generation == currentGeneration,
              frameCount > 0 else {
            return false
        }
        phase = .ready(generation: generation, frameCount: frameCount)
        return true
    }

    @discardableResult
    public mutating func fail(generation: UInt64) -> Bool {
        guard case .loading(let activeGeneration) = phase,
              activeGeneration == generation,
              generation == currentGeneration else {
            return false
        }
        phase = .failed(generation: generation)
        return true
    }

    @discardableResult
    public mutating func cancel(generation: UInt64) -> Bool {
        guard case .loading(let activeGeneration) = phase,
              activeGeneration == generation,
              generation == currentGeneration else {
            return false
        }
        phase = .cancelled(generation: generation)
        return true
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
    public var viewportRequest: FilmstripViewportRequest?
    public var mediaIdentity: String?

    public init(
        assetID: UUID,
        zoomBucket: FilmstripZoomBucket,
        viewportRequest: FilmstripViewportRequest? = nil,
        mediaIdentity: String? = nil
    ) {
        self.assetID = assetID
        self.zoomBucket = zoomBucket
        self.viewportRequest = viewportRequest
        self.mediaIdentity = mediaIdentity
    }
}

/// Observable decoded-byte accounting for the filmstrip cache.
///
/// `NSCache.totalCostLimit` remains the final memory-pressure backstop, while
/// this value records the costs MovieCut explicitly admitted. Calling it
/// "tracked" is intentional: it is decoded image byte cost, not process RSS.
public struct FilmstripCacheMetrics: Sendable, Equatable {
    public var totalCostLimit: Int
    public var currentTrackedCost: Int
    public var peakTrackedCost: Int
    public var trackedKeyCount: Int
    public var evictionCount: Int
    public var oversizedRejectionCount: Int

    public init(
        totalCostLimit: Int,
        currentTrackedCost: Int,
        peakTrackedCost: Int,
        trackedKeyCount: Int,
        evictionCount: Int,
        oversizedRejectionCount: Int
    ) {
        self.totalCostLimit = totalCostLimit
        self.currentTrackedCost = currentTrackedCost
        self.peakTrackedCost = peakTrackedCost
        self.trackedKeyCount = trackedKeyCount
        self.evictionCount = evictionCount
        self.oversizedRejectionCount = oversizedRejectionCount
    }
}

/// Exact, lossless summary of measured filmstrip-attributable work intervals.
///
/// Callers provide monotonic-clock durations in nanoseconds. Every duration is
/// retained: the accumulator does not discard warmup samples, trim outliers, or
/// clamp values. The default frame-work budget is the G-04 AC1 limit of exactly
/// 16.6ms rather than the slightly looser 1/60-second interval.
public struct FilmstripWorkTimingSummary: Sendable, Equatable {
    public var sampleCount: Int
    public var p95Nanoseconds: UInt64
    public var maxNanoseconds: UInt64
    public var overFrameBudgetCount: Int

    public init(
        sampleCount: Int,
        p95Nanoseconds: UInt64,
        maxNanoseconds: UInt64,
        overFrameBudgetCount: Int
    ) {
        self.sampleCount = sampleCount
        self.p95Nanoseconds = p95Nanoseconds
        self.maxNanoseconds = maxNanoseconds
        self.overFrameBudgetCount = overFrameBudgetCount
    }

    public var p95Milliseconds: Double {
        Double(p95Nanoseconds) / 1_000_000
    }

    public var maxMilliseconds: Double {
        Double(maxNanoseconds) / 1_000_000
    }
}

public struct FilmstripWorkTimingAccumulator: Sendable {
    public static let frameBudgetNanoseconds: UInt64 = 16_600_000

    private var durationNanoseconds: [UInt64] = []

    public init() {}

    public mutating func record(durationNanoseconds: UInt64) {
        self.durationNanoseconds.append(durationNanoseconds)
    }

    public func summary(
        frameBudgetNanoseconds: UInt64 = Self.frameBudgetNanoseconds
    ) -> FilmstripWorkTimingSummary {
        let sorted = durationNanoseconds.sorted()
        let p95Index = sorted.isEmpty
            ? 0
            : min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return FilmstripWorkTimingSummary(
            sampleCount: sorted.count,
            p95Nanoseconds: sorted.isEmpty ? 0 : sorted[p95Index],
            maxNanoseconds: sorted.last ?? 0,
            overFrameBudgetCount: sorted.reduce(into: 0) { count, duration in
                if duration > frameBudgetNanoseconds {
                    count += 1
                }
            }
        )
    }
}

public struct FilmstripCacheInsertionPlan: Sendable, Equatable {
    public var shouldCache: Bool
    public var evictedKeys: [FilmstripCacheKey]

    public init(shouldCache: Bool, evictedKeys: [FilmstripCacheKey]) {
        self.shouldCache = shouldCache
        self.evictedKeys = evictedKeys
    }
}

/// Deterministic LRU admission/accounting shared by the app cache and tests.
///
/// The planner applies both the decoded-byte ceiling and a key-count ceiling
/// before `NSCache` receives an object. This makes the 128MB application policy
/// enforceable and reportable rather than relying on an advisory cache limit.
public struct FilmstripCacheAccounting: Sendable {
    public let totalCostLimit: Int
    public let maximumTrackedKeys: Int

    private var costsByKey: [FilmstripCacheKey: Int] = [:]
    private var recency: [FilmstripCacheKey] = []
    private var currentTrackedCost = 0
    private var peakTrackedCost = 0
    private var evictionCount = 0
    private var oversizedRejectionCount = 0

    public init(totalCostLimit: Int, maximumTrackedKeys: Int) {
        self.totalCostLimit = max(1, totalCostLimit)
        self.maximumTrackedKeys = max(1, maximumTrackedKeys)
    }

    public mutating func insert(
        key: FilmstripCacheKey,
        cost rawCost: Int
    ) -> FilmstripCacheInsertionPlan {
        let cost = max(0, rawCost)
        guard cost <= totalCostLimit else {
            oversizedRejectionCount += 1
            return FilmstripCacheInsertionPlan(shouldCache: false, evictedKeys: [])
        }

        if let previousCost = costsByKey[key] {
            currentTrackedCost -= previousCost
            costsByKey[key] = nil
            recency.removeAll { $0 == key }
        }

        var evictedKeys: [FilmstripCacheKey] = []
        while let oldest = recency.first,
              recency.count >= maximumTrackedKeys
                || currentTrackedCost + cost > totalCostLimit {
            recency.removeFirst()
            currentTrackedCost -= costsByKey.removeValue(forKey: oldest) ?? 0
            evictionCount += 1
            evictedKeys.append(oldest)
        }

        costsByKey[key] = cost
        recency.append(key)
        currentTrackedCost += cost
        peakTrackedCost = max(peakTrackedCost, currentTrackedCost)
        return FilmstripCacheInsertionPlan(shouldCache: true, evictedKeys: evictedKeys)
    }

    public mutating func touch(_ key: FilmstripCacheKey) {
        guard costsByKey[key] != nil else { return }
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    /// Reconciles accounting when `NSCache` discarded a value under pressure.
    public mutating func reconcileMissing(_ key: FilmstripCacheKey) {
        remove(key)
    }

    public mutating func remove(_ key: FilmstripCacheKey) {
        currentTrackedCost -= costsByKey.removeValue(forKey: key) ?? 0
        recency.removeAll { $0 == key }
    }

    @discardableResult
    public mutating func remove(assetID: UUID) -> [FilmstripCacheKey] {
        let removed = recency.filter { $0.assetID == assetID }
        for key in removed {
            remove(key)
        }
        return removed
    }

    public mutating func removeAll() {
        costsByKey.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
        currentTrackedCost = 0
    }

    public var metrics: FilmstripCacheMetrics {
        FilmstripCacheMetrics(
            totalCostLimit: totalCostLimit,
            currentTrackedCost: currentTrackedCost,
            peakTrackedCost: peakTrackedCost,
            trackedKeyCount: costsByKey.count,
            evictionCount: evictionCount,
            oversizedRejectionCount: oversizedRejectionCount
        )
    }
}
