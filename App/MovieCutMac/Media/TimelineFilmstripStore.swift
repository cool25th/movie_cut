import Foundation
import MovieCutCore
import Observation
import SwiftUI

enum TimelineFilmstripCoordinateSpace {
    static let viewport = "moviecut.timeline.horizontal-viewport"
}

struct TimelineFilmstripRequestID: Hashable, Sendable {
    let clipID: UUID
    let assetID: UUID
    let mediaIdentity: String
    let clipSourceRange: TimeRange
    let clipTimelineRange: TimeRange
    let viewportRequest: FilmstripViewportRequest
    let maxHeightKey: Int
}

struct TimelineFilmstripSnapshot {
    let requestID: TimelineFilmstripRequestID
    let viewportRequest: FilmstripViewportRequest
    let frames: [FilmstripFrame]
    let loadState: FilmstripLoadState

    var readyGeneration: UInt64? {
        guard case .ready(let generation, _) = loadState.phase else { return nil }
        return generation
    }
}

/// MainActor-owned per-clip async state for the real timeline consumer.
///
/// Entries only exist for visible/near-visible clips and are capped separately
/// from the 128MB decoded-frame cache. AppKit image objects never cross actors;
/// the store keeps immutable CGImages produced by FilmstripGenerator.
@MainActor
@Observable
final class TimelineFilmstripStore {
    private struct Entry {
        var requestID: TimelineFilmstripRequestID
        var frames: [FilmstripFrame]
        var loadState: FilmstripLoadState
    }

    private let maximumActiveEntries: Int
    private var entries: [UUID: Entry] = [:]
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var recency: [UUID] = []
    @ObservationIgnored private let cache: FilmstripCache
    @ObservationIgnored private let generator: FilmstripGenerator

    init(
        cache: FilmstripCache = FilmstripCache(),
        generator: FilmstripGenerator = FilmstripGenerator(),
        maximumActiveEntries: Int = 32
    ) {
        self.cache = cache
        self.generator = generator
        self.maximumActiveEntries = max(1, maximumActiveEntries)
    }

    func snapshot(for clipID: UUID) -> TimelineFilmstripSnapshot? {
        guard let entry = entries[clipID] else { return nil }
        return TimelineFilmstripSnapshot(
            requestID: entry.requestID,
            viewportRequest: entry.requestID.viewportRequest,
            frames: entry.frames,
            loadState: entry.loadState
        )
    }

    func request(
        _ requestID: TimelineFilmstripRequestID,
        assetURL: URL,
        maxHeight: CGFloat,
        fallbackThumbnailAvailable: Bool
    ) {
        if entries[requestID.clipID]?.requestID == requestID {
            touch(requestID.clipID)
            return
        }

        if let previousEntry = entries[requestID.clipID] {
            tasks[requestID.clipID]?.cancel()
            var previousState = previousEntry.loadState
            let previousGeneration = previousState.currentGeneration
            if previousState.cancel(generation: previousGeneration) {
                #if DEBUG
                TimelineFilmstripDebugProbe.shared.recordCancellation(
                    fallbackThumbnailAvailable: fallbackThumbnailAvailable
                )
                #endif
            }
        }

        var loadState = entries[requestID.clipID]?.loadState ?? FilmstripLoadState()
        let generation = loadState.begin()
        entries[requestID.clipID] = Entry(
            requestID: requestID,
            frames: [],
            loadState: loadState
        )
        touch(requestID.clipID)
        pruneIfNeeded(keeping: requestID.clipID)

        #if DEBUG
        TimelineFilmstripDebugProbe.shared.recordRequest(
            requestID: requestID,
            generation: generation
        )
        #endif

        let cacheKey = FilmstripCacheKey(
            assetID: requestID.assetID,
            zoomBucket: requestID.viewportRequest.zoomBucket,
            viewportRequest: requestID.viewportRequest,
            mediaIdentity: requestID.mediaIdentity
        )
        let boundedHeight = max(1, min(maxHeight.isFinite ? maxHeight : 60, 60))
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                #if DEBUG
                if TimelineFilmstripDebugProbe.shared.shouldDelayFirstGeneration(
                    requestID: requestID,
                    generation: generation
                ) {
                    try await Task.sleep(for: .milliseconds(250))
                }
                #endif

                let frames: [FilmstripFrame]
                if let cachedFrames = await cache.frames(for: cacheKey) {
                    frames = cachedFrames
                } else {
                    frames = try await generator.frames(
                        for: assetURL,
                        sourceRange: requestID.viewportRequest.sourceRange,
                        targetCount: requestID.viewportRequest.targetCount,
                        maxHeight: boundedHeight
                    )
                    try Task.checkCancellation()
                    await cache.insert(frames, for: cacheKey)
                }
                try Task.checkCancellation()
                publish(
                    frames: frames,
                    requestID: requestID,
                    generation: generation
                )
            } catch {
                finishFailedRequest(
                    requestID: requestID,
                    generation: generation,
                    wasCancelled: error is CancellationError || Task.isCancelled
                )
            }
        }
        tasks[requestID.clipID] = task
    }

    func cancel(clipID: UUID, offscreen: Bool, removeState: Bool = true) {
        tasks.removeValue(forKey: clipID)?.cancel()
        if var entry = entries[clipID] {
            let generation = entry.loadState.currentGeneration
            if entry.loadState.cancel(generation: generation) {
                entries[clipID] = entry
                #if DEBUG
                TimelineFilmstripDebugProbe.shared.recordCancellation(
                    fallbackThumbnailAvailable: false
                )
                #endif
            }
        }
        if removeState {
            entries[clipID] = nil
            recency.removeAll { $0 == clipID }
        }
        #if DEBUG
        if offscreen {
            TimelineFilmstripDebugProbe.shared.recordOffscreenSkip(clipID: clipID)
        }
        #endif
    }

    func cancelAll() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll(keepingCapacity: true)
        entries.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
    }

    private func publish(
        frames: [FilmstripFrame],
        requestID: TimelineFilmstripRequestID,
        generation: UInt64
    ) {
        guard var entry = entries[requestID.clipID],
              entry.requestID == requestID,
              entry.loadState.accept(frameCount: frames.count, generation: generation) else {
            #if DEBUG
            TimelineFilmstripDebugProbe.shared.recordStaleRejection()
            #endif
            return
        }
        entry.frames = frames
        entries[requestID.clipID] = entry
        if tasks[requestID.clipID] != nil {
            tasks[requestID.clipID] = nil
        }
        #if DEBUG
        TimelineFilmstripDebugProbe.shared.recordReady(
            requestID: requestID,
            frames: frames
        )
        #endif
    }

    private func finishFailedRequest(
        requestID: TimelineFilmstripRequestID,
        generation: UInt64,
        wasCancelled: Bool
    ) {
        guard var entry = entries[requestID.clipID],
              entry.requestID == requestID else {
            #if DEBUG
            TimelineFilmstripDebugProbe.shared.recordStaleRejection()
            #endif
            return
        }

        let accepted = wasCancelled
            ? entry.loadState.cancel(generation: generation)
            : entry.loadState.fail(generation: generation)
        guard accepted else {
            #if DEBUG
            TimelineFilmstripDebugProbe.shared.recordStaleRejection()
            #endif
            return
        }
        entry.frames = []
        entries[requestID.clipID] = entry
        tasks[requestID.clipID] = nil
    }

    private func touch(_ clipID: UUID) {
        recency.removeAll { $0 == clipID }
        recency.append(clipID)
    }

    private func pruneIfNeeded(keeping clipID: UUID) {
        while entries.count > maximumActiveEntries,
              let candidate = recency.first(where: { $0 != clipID }) {
            tasks.removeValue(forKey: candidate)?.cancel()
            entries[candidate] = nil
            recency.removeAll { $0 == candidate }
        }
    }
}

struct TimelineFilmstripLayer: View {
    let clip: Clip
    let asset: MediaAsset
    let pixelsPerSecond: Double
    let viewportWidth: CGFloat
    let fallbackThumbnailAvailable: Bool
    let store: TimelineFilmstripStore

    var body: some View {
        GeometryReader { proxy in
            let clipFrame = proxy.frame(in: .named(TimelineFilmstripCoordinateSpace.viewport))
            let height = max(proxy.size.height, 1)
            let tileWidth = min(max(height * 16 / 9, 44), 72)
            let viewportRequest = FilmstripViewportPlanner.request(
                clipMinX: Double(clipFrame.minX),
                clipWidth: Double(clipFrame.width),
                viewportWidth: Double(viewportWidth),
                sourceRange: clip.sourceRange,
                pixelsPerSecond: pixelsPerSecond,
                tileWidth: Double(tileWidth)
            )
            let requestID = viewportRequest.map {
                TimelineFilmstripRequestID(
                    clipID: clip.id,
                    assetID: asset.id,
                    mediaIdentity: mediaIdentity,
                    clipSourceRange: clip.sourceRange,
                    clipTimelineRange: clip.timelineRange,
                    viewportRequest: $0,
                    maxHeightKey: Int(height.rounded())
                )
            }
            let snapshot = store.snapshot(for: clip.id)

            ZStack(alignment: .leading) {
                if let requestID,
                   let snapshot,
                   snapshot.requestID == requestID,
                   !snapshot.frames.isEmpty,
                   snapshot.readyGeneration != nil {
                    generatedFrames(snapshot, height: height)
                        .id(snapshot.requestID)
                        .onAppear {
                            #if DEBUG
                            TimelineFilmstripDebugProbe.shared.recordConsumerRendered(
                                requestID: snapshot.requestID,
                                frameCount: snapshot.frames.count
                            )
                            #endif
                        }
                }
            }
            .task(id: requestID) {
                guard let requestID else {
                    store.cancel(clipID: clip.id, offscreen: true)
                    return
                }
                #if DEBUG
                if fallbackThumbnailAvailable,
                   store.snapshot(for: clip.id)?.loadState.showsFallbackThumbnail != false {
                    TimelineFilmstripDebugProbe.shared.recordFallbackBeforeReadiness()
                }
                #endif
                store.request(
                    requestID,
                    assetURL: asset.originalURL,
                    maxHeight: height,
                    fallbackThumbnailAvailable: fallbackThumbnailAvailable
                )
            }
        }
        .allowsHitTesting(false)
        .onDisappear {
            store.cancel(clipID: clip.id, offscreen: false)
        }
    }

    private var mediaIdentity: String {
        let url = asset.originalURL.standardizedFileURL.absoluteString
        let duration = asset.duration.map { String($0) } ?? "nil"
        let fileSize = asset.metadata.fileSize.map { String($0) } ?? "nil"
        let width = asset.metadata.width.map { String($0) } ?? "nil"
        let height = asset.metadata.height.map { String($0) } ?? "nil"
        return [url, duration, fileSize, width, height].joined(separator: "|")
    }

    private func generatedFrames(
        _ snapshot: TimelineFilmstripSnapshot,
        height: CGFloat
    ) -> some View {
        let count = snapshot.frames.count
        let availableWidth = max(1, CGFloat(snapshot.viewportRequest.localWidth) - CGFloat(max(0, count - 1)))
        let frameWidth = availableWidth / CGFloat(max(1, count))

        return HStack(spacing: 1) {
            ForEach(Array(snapshot.frames.enumerated()), id: \.offset) { _, frame in
                Image(decorative: frame.image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frameWidth, height: height)
                    .clipped()
            }
        }
        .frame(
            width: CGFloat(snapshot.viewportRequest.localWidth),
            height: height,
            alignment: .leading
        )
        .offset(x: CGFloat(snapshot.viewportRequest.localStartX))
        .clipped()
    }
}

#if DEBUG
@MainActor
final class TimelineFilmstripDebugProbe {
    struct Summary {
        let consumerFrameCount: Int
        let distinctDigestCount: Int
        let distinctTimestampCount: Int
        let requestedSpan: TimeInterval
        let fullSpan: TimeInterval
        let requestedCount: Int
        let fullCount: Int
        let offscreenSkipped: Bool
        let cancelled: Bool
        let staleRejected: Bool
        let fallbackBeforeReady: Bool
        let fallbackAfterCancellation: Bool
        let zoomScaleKeys: [Int]
    }

    static let shared = TimelineFilmstripDebugProbe()

    private var isArmed = false
    private var requests: [(id: TimelineFilmstripRequestID, generation: UInt64)] = []
    private var delayedRequest: (id: TimelineFilmstripRequestID, generation: UInt64)?
    private var ready: (id: TimelineFilmstripRequestID, frames: [FilmstripFrame])?
    private var consumer: (id: TimelineFilmstripRequestID, frameCount: Int)?
    private var offscreenClipIDs: Set<UUID> = []
    private var cancellationCount = 0
    private var staleRejectionCount = 0
    private var sawFallbackBeforeReady = false
    private var sawFallbackAfterCancellation = false

    private init() {}

    func arm() {
        isArmed = true
        requests.removeAll(keepingCapacity: true)
        delayedRequest = nil
        ready = nil
        consumer = nil
        offscreenClipIDs.removeAll(keepingCapacity: true)
        cancellationCount = 0
        staleRejectionCount = 0
        sawFallbackBeforeReady = false
        sawFallbackAfterCancellation = false
    }

    var hasVisibleRequest: Bool {
        isArmed && !requests.isEmpty
    }

    func recordRequest(requestID: TimelineFilmstripRequestID, generation: UInt64) {
        guard isArmed else { return }
        requests.append((requestID, generation))
        if delayedRequest == nil {
            delayedRequest = (requestID, generation)
        }
    }

    func shouldDelayFirstGeneration(
        requestID: TimelineFilmstripRequestID,
        generation: UInt64
    ) -> Bool {
        guard isArmed, let delayedRequest else { return false }
        return delayedRequest.id == requestID && delayedRequest.generation == generation
    }

    func recordReady(requestID: TimelineFilmstripRequestID, frames: [FilmstripFrame]) {
        guard isArmed else { return }
        ready = (requestID, frames)
    }

    func recordConsumerRendered(requestID: TimelineFilmstripRequestID, frameCount: Int) {
        guard isArmed else { return }
        consumer = (requestID, frameCount)
    }

    func recordOffscreenSkip(clipID: UUID) {
        guard isArmed else { return }
        offscreenClipIDs.insert(clipID)
    }

    func recordCancellation(fallbackThumbnailAvailable: Bool) {
        guard isArmed else { return }
        cancellationCount += 1
        if fallbackThumbnailAvailable {
            sawFallbackAfterCancellation = true
        }
    }

    func recordStaleRejection() {
        guard isArmed else { return }
        staleRejectionCount += 1
    }

    func recordFallbackBeforeReadiness() {
        guard isArmed else { return }
        sawFallbackBeforeReady = true
    }

    func completedSummary() -> Summary? {
        guard isArmed,
              Set(requests.map { $0.id.viewportRequest.zoomScaleKey }).count >= 2,
              let ready,
              let consumer,
              consumer.id == ready.id,
              consumer.frameCount > 1,
              offscreenClipIDs.contains(where: { $0 != ready.id.clipID }),
              cancellationCount > 0,
              staleRejectionCount > 0,
              sawFallbackBeforeReady,
              sawFallbackAfterCancellation else {
            return nil
        }

        let digests = Set(ready.frames.map(\.digest))
        let timestamps = Set(ready.frames.map { Int(($0.requestedTime * 1_000).rounded()) })
        let viewportRequest = ready.id.viewportRequest
        guard digests.count > 1,
              timestamps.count > 1,
              viewportRequest.sourceRange.duration < ready.id.clipSourceRange.duration,
              viewportRequest.targetCount < viewportRequest.fullTargetCount else {
            return nil
        }

        return Summary(
            consumerFrameCount: consumer.frameCount,
            distinctDigestCount: digests.count,
            distinctTimestampCount: timestamps.count,
            requestedSpan: viewportRequest.sourceRange.duration,
            fullSpan: ready.id.clipSourceRange.duration,
            requestedCount: viewportRequest.targetCount,
            fullCount: viewportRequest.fullTargetCount,
            offscreenSkipped: true,
            cancelled: true,
            staleRejected: true,
            fallbackBeforeReady: true,
            fallbackAfterCancellation: true,
            zoomScaleKeys: Array(Set(requests.map { $0.id.viewportRequest.zoomScaleKey })).sorted()
        )
    }
}
#endif
