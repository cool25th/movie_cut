import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import os.log

enum TimelineFilmstripInstrumentation {
    static let log = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.moviecut.mac",
        category: "TimelineFilmstrip"
    )
}

/// One production request trace shared by the store task and SwiftUI consumer.
/// The lock only protects idempotent interval closure across cancellation races;
/// filmstrip state itself remains MainActor/actor isolated.
final class TimelineFilmstripTrace: @unchecked Sendable {
    let signpostID: OSSignpostID

    private let lock = NSLock()
    private var lifecycleEnded = false

    init(requestID: TimelineFilmstripRequestID, generation: UInt64) {
        signpostID = OSSignpostID(log: TimelineFilmstripInstrumentation.log)
        os_signpost(
            .begin,
            log: TimelineFilmstripInstrumentation.log,
            name: "RequestLifecycle",
            signpostID: signpostID,
            "clip=%{public}@ generation=%llu bucket=%d zoom=%d target=%d",
            requestID.clipID.uuidString as NSString,
            generation,
            requestID.viewportRequest.zoomBucket.rawValue,
            requestID.viewportRequest.zoomScaleKey,
            requestID.viewportRequest.targetCount
        )
    }

    func beginCacheLookup() {
        os_signpost(
            .begin,
            log: TimelineFilmstripInstrumentation.log,
            name: "CacheLookup",
            signpostID: signpostID
        )
    }

    func endCacheLookup(hit: Bool) {
        os_signpost(
            .end,
            log: TimelineFilmstripInstrumentation.log,
            name: "CacheLookup",
            signpostID: signpostID,
            "hit=%d",
            hit ? 1 : 0
        )
    }

    func beginDecode() {
        os_signpost(
            .begin,
            log: TimelineFilmstripInstrumentation.log,
            name: "Decode",
            signpostID: signpostID
        )
    }

    func endDecode(frameCount: Int, succeeded: Bool) {
        os_signpost(
            .end,
            log: TimelineFilmstripInstrumentation.log,
            name: "Decode",
            signpostID: signpostID,
            "frames=%d success=%d",
            frameCount,
            succeeded ? 1 : 0
        )
    }

    func beginCacheInsert() {
        os_signpost(
            .begin,
            log: TimelineFilmstripInstrumentation.log,
            name: "CacheInsert",
            signpostID: signpostID
        )
    }

    func endCacheInsert(metrics: FilmstripCacheMetrics) {
        os_signpost(
            .end,
            log: TimelineFilmstripInstrumentation.log,
            name: "CacheInsert",
            signpostID: signpostID,
            "current=%d peak=%d limit=%d keys=%d evictions=%d",
            metrics.currentTrackedCost,
            metrics.peakTrackedCost,
            metrics.totalCostLimit,
            metrics.trackedKeyCount,
            metrics.evictionCount
        )
    }

    func beginPublish(frameCount: Int) {
        os_signpost(
            .begin,
            log: TimelineFilmstripInstrumentation.log,
            name: "Publish",
            signpostID: signpostID,
            "frames=%d",
            frameCount
        )
    }

    func endPublish(accepted: Bool) {
        os_signpost(
            .end,
            log: TimelineFilmstripInstrumentation.log,
            name: "Publish",
            signpostID: signpostID,
            "accepted=%d",
            accepted ? 1 : 0
        )
    }

    func consumerRendered(frameCount: Int) {
        os_signpost(
            .event,
            log: TimelineFilmstripInstrumentation.log,
            name: "UIConsumerRendered",
            signpostID: signpostID,
            "frames=%d",
            frameCount
        )
        endLifecycle(outcome: "consumed")
    }

    func endLifecycle(outcome: String) {
        lock.lock()
        guard !lifecycleEnded else {
            lock.unlock()
            return
        }
        lifecycleEnded = true
        lock.unlock()
        os_signpost(
            .end,
            log: TimelineFilmstripInstrumentation.log,
            name: "RequestLifecycle",
            signpostID: signpostID,
            "outcome=%{public}@",
            outcome as NSString
        )
    }
}

/// One decoded frame and the source timestamps used to produce it.
struct FilmstripFrame: @unchecked Sendable {
    let image: CGImage
    let requestedTime: TimeInterval
    let actualTime: TimeInterval
    let digest: String

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
        let decodeSignpostID = OSSignpostID(log: TimelineFilmstripInstrumentation.log)
        os_signpost(
            .begin,
            log: TimelineFilmstripInstrumentation.log,
            name: "GeneratorDecode",
            signpostID: decodeSignpostID,
            "target=%d maxHeight=%d sourceStart=%.3f sourceDuration=%.3f",
            requests.count,
            Int(boundedHeight.rounded()),
            sourceRange.start,
            sourceRange.duration
        )
        let decodeTask = Task.detached(priority: .utility) {
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
                            actualTime: decodedActualTime.isFinite ? decodedActualTime : request.time,
                            digest: Self.digest(for: image)
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
        }
        do {
            let frames = try await withTaskCancellationHandler {
                try await decodeTask.value
            } onCancel: {
                decodeTask.cancel()
            }
            os_signpost(
                .end,
                log: TimelineFilmstripInstrumentation.log,
                name: "GeneratorDecode",
                signpostID: decodeSignpostID,
                "frames=%d success=1",
                frames.count
            )
            return frames
        } catch {
            os_signpost(
                .end,
                log: TimelineFilmstripInstrumentation.log,
                name: "GeneratorDecode",
                signpostID: decodeSignpostID,
                "frames=0 success=0"
            )
            throw error
        }
    }

    /// Small deterministic pixel digest used by the DEBUG consumer evidence.
    /// Frames are capped at 60px high, so hashing their provider bytes remains
    /// cheap and stays off the MainActor with the rest of decoding.
    private static func digest(for image: CGImage) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for value in [image.width, image.height, image.bytesPerRow] {
            var bytes = UInt64(value)
            for _ in 0..<MemoryLayout<UInt64>.size {
                hash ^= bytes & 0xff
                hash &*= 1_099_511_628_211
                bytes >>= 8
            }
        }
        if let providerData = image.dataProvider?.data {
            for byte in providerData as Data {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
        }
        return String(format: "%016llx", hash)
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
    static let defaultMaximumTrackedKeys = 256

    private let storage = NSCache<FilmstripCacheKeyBox, FilmstripFrameBox>()
    private var counters = FilmstripCacheStats()
    private var accounting: FilmstripCacheAccounting

    init(
        totalCostLimit: Int = FilmstripCache.defaultTotalCostLimit,
        maximumTrackedKeys: Int = FilmstripCache.defaultMaximumTrackedKeys
    ) {
        let boundedLimit = max(1, totalCostLimit)
        self.accounting = FilmstripCacheAccounting(
            totalCostLimit: boundedLimit,
            maximumTrackedKeys: maximumTrackedKeys
        )
        storage.totalCostLimit = boundedLimit
    }

    func frames(for key: FilmstripCacheKey) -> [FilmstripFrame]? {
        if let value = storage.object(forKey: FilmstripCacheKeyBox(key)) {
            counters.hits += 1
            accounting.touch(key)
            return value.frames
        }

        counters.misses += 1
        accounting.reconcileMissing(key)
        return nil
    }

    @discardableResult
    func insert(_ frames: [FilmstripFrame], for key: FilmstripCacheKey) -> FilmstripCacheMetrics {
        let cost = frames.reduce(into: 0) { total, frame in
            total += frame.byteCost
        }
        let plan = accounting.insert(key: key, cost: cost)
        guard plan.shouldCache else {
            return accounting.metrics
        }
        for evictedKey in plan.evictedKeys {
            storage.removeObject(forKey: FilmstripCacheKeyBox(evictedKey))
        }
        storage.setObject(
            FilmstripFrameBox(frames),
            forKey: FilmstripCacheKeyBox(key),
            cost: cost
        )
        counters.inserts += 1
        return accounting.metrics
    }

    func remove(assetID: UUID) {
        for key in accounting.remove(assetID: assetID) {
            storage.removeObject(forKey: FilmstripCacheKeyBox(key))
        }
    }

    func removeAll() {
        storage.removeAllObjects()
        accounting.removeAll()
    }

    func stats() -> FilmstripCacheStats {
        counters
    }

    func configuredTotalCostLimit() -> Int {
        accounting.totalCostLimit
    }

    func metrics() -> FilmstripCacheMetrics {
        accounting.metrics
    }
}
