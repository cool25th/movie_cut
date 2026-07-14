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
}
