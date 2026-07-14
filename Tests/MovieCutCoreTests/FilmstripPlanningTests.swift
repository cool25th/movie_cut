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
}
