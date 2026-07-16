import Foundation
import Testing
@testable import MovieCutCore

@Suite("Filmstrip Planning")
struct FilmstripPlanningTests {
    @Test("requests sample equal tile centers without touching the exclusive end")
    func samplesTileCenters() {
        let requests = FilmstripRequestPlanner.requests(
            sourceRange: TimeRange(start: 3, duration: 2),
            targetCount: 4
        )

        #expect(requests.map(\.index) == [0, 1, 2, 3])
        #expect(requests.map(\.time) == [3.25, 3.75, 4.25, 4.75])
        #expect(requests.last?.time != 5)
    }

    @Test("single frame samples the source midpoint")
    func samplesMidpoint() {
        let requests = FilmstripRequestPlanner.requests(
            sourceRange: TimeRange(start: 1, duration: 6),
            targetCount: 1
        )

        #expect(requests == [FilmstripFrameRequest(index: 0, time: 4)])
    }

    @Test("invalid source ranges and counts fail closed")
    func rejectsInvalidInputs() {
        #expect(FilmstripRequestPlanner.requests(
            sourceRange: TimeRange(start: 0, duration: 2),
            targetCount: 0
        ).isEmpty)
        #expect(FilmstripRequestPlanner.requests(
            sourceRange: TimeRange(start: -1, duration: 2),
            targetCount: 4
        ).isEmpty)
        #expect(FilmstripRequestPlanner.requests(
            sourceRange: TimeRange(start: 0, duration: .infinity),
            targetCount: 4
        ).isEmpty)
        #expect(FilmstripRequestPlanner.requests(
            sourceRange: TimeRange(start: 0, duration: 0),
            targetCount: 4
        ).isEmpty)
    }

    @Test("zoom buckets use stable doubling boundaries across 20...300 px/s")
    func mapsZoomBuckets() {
        #expect(FilmstripZoomBucket.bucket(for: 20) == .level0)
        #expect(FilmstripZoomBucket.bucket(for: 39.999) == .level0)
        #expect(FilmstripZoomBucket.bucket(for: 40) == .level1)
        #expect(FilmstripZoomBucket.bucket(for: 79.999) == .level1)
        #expect(FilmstripZoomBucket.bucket(for: 80) == .level2)
        #expect(FilmstripZoomBucket.bucket(for: 159.999) == .level2)
        #expect(FilmstripZoomBucket.bucket(for: 160) == .level3)
        #expect(FilmstripZoomBucket.bucket(for: 300) == .level3)
        #expect(FilmstripZoomBucket.bucket(for: .nan) == .level0)
        #expect(FilmstripZoomBucket.bucket(for: 0) == .level0)
    }

    @Test("cache keys separate assets and zoom buckets")
    func separatesCacheKeys() {
        let assetID = UUID()
        let sameA = FilmstripCacheKey(assetID: assetID, zoomBucket: .level2)
        let sameB = FilmstripCacheKey(assetID: assetID, zoomBucket: .level2)
        let differentBucket = FilmstripCacheKey(assetID: assetID, zoomBucket: .level3)
        let differentAsset = FilmstripCacheKey(assetID: UUID(), zoomBucket: .level2)

        #expect(sameA == sameB)
        #expect(sameA.hashValue == sameB.hashValue)
        #expect(sameA != differentBucket)
        #expect(sameA != differentAsset)
        #expect(Set([sameA, sameB, differentBucket, differentAsset]).count == 3)
    }

    @Test("cache accounting enforces decoded-byte and key ceilings with LRU eviction")
    func cacheAccountingEnforcesLimits() {
        let assetID = UUID()
        let keys = (0..<4).map { index in
            FilmstripCacheKey(
                assetID: assetID,
                zoomBucket: FilmstripZoomBucket(rawValue: index)!,
                mediaIdentity: "media-\(index)"
            )
        }
        var accounting = FilmstripCacheAccounting(
            totalCostLimit: 100,
            maximumTrackedKeys: 2
        )

        #expect(accounting.insert(key: keys[0], cost: 40).evictedKeys.isEmpty)
        #expect(accounting.insert(key: keys[1], cost: 40).evictedKeys.isEmpty)
        accounting.touch(keys[0])
        let byteEviction = accounting.insert(key: keys[2], cost: 40)
        #expect(byteEviction == FilmstripCacheInsertionPlan(
            shouldCache: true,
            evictedKeys: [keys[1]]
        ))
        #expect(accounting.metrics.currentTrackedCost == 80)

        let keyEviction = accounting.insert(key: keys[3], cost: 10)
        #expect(keyEviction == FilmstripCacheInsertionPlan(
            shouldCache: true,
            evictedKeys: [keys[0]]
        ))
        #expect(accounting.metrics == FilmstripCacheMetrics(
            totalCostLimit: 100,
            currentTrackedCost: 50,
            peakTrackedCost: 80,
            trackedKeyCount: 2,
            evictionCount: 2,
            oversizedRejectionCount: 0
        ))
    }

    @Test("cache accounting rejects an oversized insertion without evicting resident entries")
    func cacheAccountingRejectsOversizedEntry() {
        let resident = FilmstripCacheKey(assetID: UUID(), zoomBucket: .level0)
        let oversized = FilmstripCacheKey(assetID: UUID(), zoomBucket: .level3)
        var accounting = FilmstripCacheAccounting(
            totalCostLimit: 128,
            maximumTrackedKeys: 4
        )
        _ = accounting.insert(key: resident, cost: 64)

        let plan = accounting.insert(key: oversized, cost: 129)

        #expect(plan == FilmstripCacheInsertionPlan(shouldCache: false, evictedKeys: []))
        #expect(accounting.metrics.currentTrackedCost == 64)
        #expect(accounting.metrics.trackedKeyCount == 1)
        #expect(accounting.metrics.oversizedRejectionCount == 1)
        accounting.reconcileMissing(resident)
        #expect(accounting.metrics.currentTrackedCost == 0)
        #expect(accounting.metrics.peakTrackedCost == 64)
    }

    @Test("viewport planning follows horizontal scroll and limits a long clip to the near-visible window")
    func plansScrolledNearVisibleWindow() throws {
        let request = try #require(FilmstripViewportPlanner.request(
            clipMinX: -600,
            clipWidth: 2_400,
            viewportWidth: 1_000,
            sourceRange: TimeRange(start: 10, duration: 120),
            pixelsPerSecond: 80,
            tileWidth: 100
        ))

        #expect(request.localStartX == 100)
        #expect(request.localWidth == 2_000)
        #expect(request.sourceRange == TimeRange(start: 15, duration: 100))
        #expect(request.targetCount == 20)
        #expect(request.fullTargetCount == 24)
        #expect(request.sourceRange.duration < 120)
    }

    @Test("viewport planning skips clips outside the prefetch window")
    func skipsOffscreenClip() {
        let request = FilmstripViewportPlanner.request(
            clipMinX: 1_501,
            clipWidth: 2_400,
            viewportWidth: 1_000,
            sourceRange: TimeRange(start: 0, duration: 120),
            pixelsPerSecond: 80,
            tileWidth: 100
        )

        #expect(request == nil)
    }

    @Test("viewport planning clamps quantized windows at both source edges")
    func clampsViewportWindowAtSourceEdges() throws {
        let left = try #require(FilmstripViewportPlanner.request(
            clipMinX: 100,
            clipWidth: 400,
            viewportWidth: 300,
            sourceRange: TimeRange(start: 0, duration: 10),
            pixelsPerSecond: 40,
            tileWidth: 75,
            prefetchViewportFraction: 0
        ))
        let right = try #require(FilmstripViewportPlanner.request(
            clipMinX: -250,
            clipWidth: 400,
            viewportWidth: 300,
            sourceRange: TimeRange(start: 0, duration: 10),
            pixelsPerSecond: 40,
            tileWidth: 75,
            prefetchViewportFraction: 0
        ))

        #expect(left.localStartX == 0)
        #expect(left.sourceRange.start == 0)
        #expect(left.sourceRange.end <= 10)
        #expect(right.localStartX == 225)
        #expect(right.sourceRange.start >= 0)
        #expect(abs(right.sourceRange.end - 10) < 0.000_001)
    }

    @Test("zoom changes participate in viewport request identity")
    func zoomChangesRequestIdentity() throws {
        let before = try #require(FilmstripViewportPlanner.request(
            clipMinX: 0,
            clipWidth: 2_000,
            viewportWidth: 1_000,
            sourceRange: TimeRange(start: 0, duration: 25),
            pixelsPerSecond: 79,
            tileWidth: 100
        ))
        let after = try #require(FilmstripViewportPlanner.request(
            clipMinX: 0,
            clipWidth: 2_000,
            viewportWidth: 1_000,
            sourceRange: TimeRange(start: 0, duration: 25),
            pixelsPerSecond: 80,
            tileWidth: 100
        ))

        #expect(before.zoomScaleKey != after.zoomScaleKey)
        #expect(before.zoomBucket == .level1)
        #expect(after.zoomBucket == .level2)
        #expect(before != after)
    }

    @Test("only the current generation may replace fallback with frames")
    func rejectsStaleResults() {
        var state = FilmstripLoadState()
        let staleGeneration = state.begin()
        let currentGeneration = state.begin()

        #expect(state.showsFallbackThumbnail)
        let acceptedStaleResult = state.accept(frameCount: 8, generation: staleGeneration)
        #expect(!acceptedStaleResult)
        #expect(state.showsFallbackThumbnail)
        let acceptedCurrentResult = state.accept(frameCount: 8, generation: currentGeneration)
        #expect(acceptedCurrentResult)
        #expect(!state.showsFallbackThumbnail)
        #expect(state.phase == .ready(generation: currentGeneration, frameCount: 8))
    }

    @Test("cancellation and failure keep the single-thumbnail fallback observable")
    func cancellationAndFailureKeepFallback() {
        var cancelled = FilmstripLoadState()
        let cancelledGeneration = cancelled.begin()
        let acceptedCancellation = cancelled.cancel(generation: cancelledGeneration)
        #expect(acceptedCancellation)
        #expect(cancelled.phase == .cancelled(generation: cancelledGeneration))
        #expect(cancelled.showsFallbackThumbnail)
        let acceptedCancelledResult = cancelled.accept(frameCount: 4, generation: cancelledGeneration)
        #expect(!acceptedCancelledResult)

        var failed = FilmstripLoadState()
        let failedGeneration = failed.begin()
        let acceptedFailure = failed.fail(generation: failedGeneration)
        #expect(acceptedFailure)
        #expect(failed.phase == .failed(generation: failedGeneration))
        #expect(failed.showsFallbackThumbnail)
    }

    @Test("hover maps left, middle, and right positions through a trimmed source start")
    func hoverMapsTrimmedSourceRange() throws {
        let times = [10.0, 13.0, 16.0]
        let left = try #require(FilmstripHoverPlanner.selection(
            localX: 0,
            clipWidth: 600,
            sourceRange: TimeRange(start: 10, duration: 6),
            timelineDuration: 6,
            playbackRate: 1,
            cachedFrameTimes: times
        ))
        let middle = try #require(FilmstripHoverPlanner.selection(
            localX: 300,
            clipWidth: 600,
            sourceRange: TimeRange(start: 10, duration: 6),
            timelineDuration: 6,
            playbackRate: 1,
            cachedFrameTimes: times
        ))
        let right = try #require(FilmstripHoverPlanner.selection(
            localX: 600,
            clipWidth: 600,
            sourceRange: TimeRange(start: 10, duration: 6),
            timelineDuration: 6,
            playbackRate: 1,
            cachedFrameTimes: times
        ))

        #expect(left.requestedSourceTime == 10)
        #expect(left.frameIndex == 0)
        #expect(middle.requestedSourceTime == 13)
        #expect(middle.frameIndex == 1)
        #expect(right.requestedSourceTime == 16)
        #expect(right.frameIndex == 2)
    }

    @Test("hover maps scaled timeline duration through constant playback rate")
    func hoverMapsPlaybackRate() throws {
        let selection = try #require(FilmstripHoverPlanner.selection(
            localX: 200,
            clipWidth: 400,
            sourceRange: TimeRange(start: 5, duration: 8),
            timelineDuration: 4,
            playbackRate: 2,
            cachedFrameTimes: [5, 9, 13]
        ))

        #expect(selection.requestedSourceTime == 9)
        #expect(selection.frameIndex == 1)
        #expect(selection.frameSourceTime == 9)
    }

    @Test("hover maps display position through a normalized speed ramp")
    func hoverMapsSpeedRamp() throws {
        let points = [
            SpeedRampPoint(time: 0, rate: 1),
            SpeedRampPoint(time: 1, rate: 2)
        ]
        let curve = SpeedRampCurve(points: points)
        let sourceDuration = 8.0
        let expectedSourceFraction = 0.25
        let timelineDuration = curve.timeMapping(sourceTime: 1) * sourceDuration
        let localX = curve.timeMapping(sourceTime: expectedSourceFraction)
            / curve.timeMapping(sourceTime: 1) * 400
        let selection = try #require(FilmstripHoverPlanner.selection(
            localX: localX,
            clipWidth: 400,
            sourceRange: TimeRange(start: 5, duration: sourceDuration),
            timelineDuration: timelineDuration,
            playbackRate: 1,
            speedRampPoints: points,
            cachedFrameTimes: [5, 7, 13]
        ))

        #expect(abs(selection.requestedSourceTime - 7) < 1.0e-9)
        #expect(selection.frameIndex == 1)
        #expect(selection.frameSourceTime == 7)
    }

    @Test("hover nearest-frame ties select the earlier source timestamp deterministically")
    func hoverNearestFrameTieIsDeterministic() throws {
        let selection = try #require(FilmstripHoverPlanner.selection(
            localX: 50,
            clipWidth: 100,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineDuration: 10,
            playbackRate: 1,
            cachedFrameTimes: [6, 4]
        ))

        #expect(selection.requestedSourceTime == 5)
        #expect(selection.frameIndex == 1)
        #expect(selection.frameSourceTime == 4)
    }

    @Test("hover clamps pointer positions at both source edges")
    func hoverClampsEdges() throws {
        let left = try #require(FilmstripHoverPlanner.selection(
            localX: -500,
            clipWidth: 100,
            sourceRange: TimeRange(start: 2, duration: 4),
            timelineDuration: 4,
            playbackRate: 1,
            cachedFrameTimes: [2, 6]
        ))
        let right = try #require(FilmstripHoverPlanner.selection(
            localX: 500,
            clipWidth: 100,
            sourceRange: TimeRange(start: 2, duration: 4),
            timelineDuration: 4,
            playbackRate: 1,
            cachedFrameTimes: [2, 6]
        ))

        #expect(left.requestedSourceTime == 2)
        #expect(right.requestedSourceTime == 6)
    }

    @Test("hover rejects invalid and non-finite geometry or timing")
    func hoverRejectsInvalidInputs() {
        let validRange = TimeRange(start: 0, duration: 2)
        #expect(FilmstripHoverPlanner.selection(
            localX: .nan,
            clipWidth: 100,
            sourceRange: validRange,
            timelineDuration: 2,
            playbackRate: 1,
            cachedFrameTimes: [1]
        ) == nil)
        #expect(FilmstripHoverPlanner.selection(
            localX: 10,
            clipWidth: .infinity,
            sourceRange: validRange,
            timelineDuration: 2,
            playbackRate: 1,
            cachedFrameTimes: [1]
        ) == nil)
        #expect(FilmstripHoverPlanner.selection(
            localX: 10,
            clipWidth: 100,
            sourceRange: validRange,
            timelineDuration: .infinity,
            playbackRate: 1,
            cachedFrameTimes: [1]
        ) == nil)
        #expect(FilmstripHoverPlanner.selection(
            localX: 10,
            clipWidth: 100,
            sourceRange: validRange,
            timelineDuration: 2,
            playbackRate: .nan,
            cachedFrameTimes: [1]
        ) == nil)
        #expect(FilmstripHoverPlanner.selection(
            localX: 10,
            clipWidth: 100,
            sourceRange: validRange,
            timelineDuration: 2,
            playbackRate: 1,
            cachedFrameTimes: [.nan, .infinity]
        ) == nil)
    }

    @Test("hover cache miss returns nil without a generation seam")
    func hoverCacheMissIsHidden() {
        let selection = FilmstripHoverPlanner.selection(
            localX: 50,
            clipWidth: 100,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineDuration: 2,
            playbackRate: 1,
            cachedFrameTimes: []
        )

        #expect(selection == nil)
    }
}
