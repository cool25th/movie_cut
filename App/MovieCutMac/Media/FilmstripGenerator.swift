import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore

/// One decoded frame and the source timestamps used to produce it.
struct FilmstripFrame: @unchecked Sendable {
    let image: CGImage
    let requestedTime: TimeInterval
    let actualTime: TimeInterval

    var byteCost: Int {
        image.bytesPerRow * image.height
    }
}

enum FilmstripGeneratorError: LocalizedError {
    case noFrameRequests
    case frameGenerationFailed(index: Int, underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .noFrameRequests:
            "Filmstrip requires a positive frame count and source duration."
        case .frameGenerationFailed(let index, let underlying):
            "Filmstrip frame \(index) failed: \(underlying.localizedDescription)"
        }
    }
}

/// Asynchronously decodes time-varying timeline frames without blocking the UI.
struct FilmstripGenerator: Sendable {
    static let requestedTimeTolerance: TimeInterval = 0.2

    func frames(
        for assetURL: URL,
        sourceRange: TimeRange,
        targetCount: Int,
        maxHeight: CGFloat = 60
    ) async throws -> [FilmstripFrame] {
        let requests = FilmstripRequestPlanner.requests(
            sourceRange: sourceRange,
            targetCount: targetCount
        )
        guard !requests.isEmpty else {
            throw FilmstripGeneratorError.noFrameRequests
        }

        let boundedHeight = max(1, min(maxHeight.isFinite ? maxHeight : 60, 60))
        return try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: assetURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: boundedHeight * 16 / 9, height: boundedHeight)
            let tolerance = CMTime(
                seconds: Self.requestedTimeTolerance,
                preferredTimescale: 600
            )
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance

            var frames: [FilmstripFrame] = []
            frames.reserveCapacity(requests.count)

            for request in requests {
                try Task.checkCancellation()
                let requestedTime = CMTime(seconds: request.time, preferredTimescale: 600)
                var actualTime = CMTime.invalid

                do {
                    let image = try generator.copyCGImage(
                        at: requestedTime,
                        actualTime: &actualTime
                    )
                    let decodedActualTime = actualTime.seconds
                    frames.append(
                        FilmstripFrame(
                            image: image,
                            requestedTime: request.time,
                            actualTime: decodedActualTime.isFinite ? decodedActualTime : request.time
                        )
                    )
                } catch {
                    throw FilmstripGeneratorError.frameGenerationFailed(
                        index: request.index,
                        underlying: error
                    )
                }
            }

            return frames
        }.value
    }
}

struct FilmstripCacheStats: Sendable, Equatable {
    var hits = 0
    var misses = 0
    var inserts = 0
}

private final class FilmstripCacheKeyBox: NSObject {
    let key: FilmstripCacheKey

    init(_ key: FilmstripCacheKey) {
        self.key = key
    }

    override var hash: Int {
        key.hashValue
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FilmstripCacheKeyBox else { return false }
        return key == other.key
    }
}

private final class FilmstripFrameBox {
    let frames: [FilmstripFrame]

    init(_ frames: [FilmstripFrame]) {
        self.frames = frames
    }
}

/// Memory-bounded decoded filmstrip cache isolated from view lifecycle races.
actor FilmstripCache {
    static let defaultTotalCostLimit = 128 * 1024 * 1024

    private let storage = NSCache<FilmstripCacheKeyBox, FilmstripFrameBox>()
    private var counters = FilmstripCacheStats()
    private let totalCostLimit: Int

    init(totalCostLimit: Int = FilmstripCache.defaultTotalCostLimit) {
        let boundedLimit = max(1, totalCostLimit)
        self.totalCostLimit = boundedLimit
        storage.totalCostLimit = boundedLimit
    }

    func frames(for key: FilmstripCacheKey) -> [FilmstripFrame]? {
        if let value = storage.object(forKey: FilmstripCacheKeyBox(key)) {
            counters.hits += 1
            return value.frames
        }

        counters.misses += 1
        return nil
    }

    func insert(_ frames: [FilmstripFrame], for key: FilmstripCacheKey) {
        let cost = frames.reduce(into: 0) { total, frame in
            total += frame.byteCost
        }
        storage.setObject(
            FilmstripFrameBox(frames),
            forKey: FilmstripCacheKeyBox(key),
            cost: cost
        )
        counters.inserts += 1
    }

    func remove(assetID: UUID) {
        for bucket in FilmstripZoomBucket.allCases {
            storage.removeObject(
                forKey: FilmstripCacheKeyBox(
                    FilmstripCacheKey(assetID: assetID, zoomBucket: bucket)
                )
            )
        }
    }

    func removeAll() {
        storage.removeAllObjects()
    }

    func stats() -> FilmstripCacheStats {
        counters
    }

    func configuredTotalCostLimit() -> Int {
        totalCostLimit
    }
}
