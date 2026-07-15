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

struct TimelineFilmstripHoverPreview {
    let clipID: UUID
    let image: CGImage
    let localX: CGFloat
    let requestedSourceTime: TimeInterval
    let selectedRequestedTime: TimeInterval
    let selectedActualTime: TimeInterval
    let digest: String
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

    /// Resolves only from the frames already published to the real timeline.
    /// This synchronous MainActor read deliberately has no cache or generator
    /// call, so pointer movement cannot enqueue work or block on media I/O.
    func hoverPreview(
        for clip: Clip,
        localX: Double,
        clipWidth: Double
    ) -> TimelineFilmstripHoverPreview? {
        guard let entry = entries[clip.id],
              entry.requestID.clipSourceRange == clip.sourceRange,
              entry.requestID.clipTimelineRange == clip.timelineRange,
              case .ready = entry.loadState.phase,
              !entry.frames.isEmpty,
              let selection = FilmstripHoverPlanner.selection(
                  localX: localX,
                  clipWidth: clipWidth,
                  sourceRange: clip.sourceRange,
                  timelineDuration: clip.timelineRange.duration,
                  playbackRate: clip.playbackRate,
                  speedRampPoints: clip.speedRampPoints,
                  cachedFrameTimes: entry.frames.map(\.actualTime)
              ),
              entry.frames.indices.contains(selection.frameIndex) else {
            return nil
        }

        let frame = entry.frames[selection.frameIndex]
        return TimelineFilmstripHoverPreview(
            clipID: clip.id,
            image: frame.image,
            localX: CGFloat(min(max(localX, 0), clipWidth)),
            requestedSourceTime: selection.requestedSourceTime,
            selectedRequestedTime: frame.requestedTime,
            selectedActualTime: frame.actualTime,
            digest: frame.digest
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
                    #if DEBUG
                    TimelineFilmstripDebugProbe.shared.recordGenerationStarted()
                    #endif
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

struct TimelineFilmstripHoverModifier: ViewModifier {
    static let previewImageSize = CGSize(width: 120, height: 68)

    let clip: Clip
    let clipWidth: CGFloat
    let supportsFilmstrip: Bool
    let store: TimelineFilmstripStore

    @State private var preview: TimelineFilmstripHoverPreview?

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                handleHover(phase)
            }
            .overlay(alignment: .topLeading) {
                if let preview {
                    hoverPreviewView(preview)
                        .offset(
                            x: previewOffsetX(for: preview),
                            y: -(Self.previewImageSize.height + MovieCutSpacing.large + MovieCutSpacing.medium)
                        )
                }
            }
            #if DEBUG
            .onAppear {
                registerDebugHoverDriver()
            }
            .onChange(of: clipWidth) { _, _ in
                registerDebugHoverDriver()
            }
            .onChange(of: clip) { _, _ in
                registerDebugHoverDriver()
            }
            .onDisappear {
                TimelineFilmstripDebugProbe.shared.unregisterHoverDriver(clipID: clip.id)
            }
            #endif
    }

    @MainActor
    private func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            resolveHover(localX: location.x)
        case .ended:
            endHover()
        }
    }

    @MainActor
    private func resolveHover(localX: CGFloat) {
        guard supportsFilmstrip else {
            preview = nil
            #if DEBUG
            TimelineFilmstripDebugProbe.shared.recordHoverHidden(
                clipID: clip.id,
                reason: .unsupported
            )
            #endif
            return
        }

        let resolved = store.hoverPreview(
            for: clip,
            localX: Double(localX),
            clipWidth: Double(clipWidth)
        )
        preview = resolved
        #if DEBUG
        if let resolved {
            TimelineFilmstripDebugProbe.shared.recordHoverResolved(resolved)
        } else {
            TimelineFilmstripDebugProbe.shared.recordHoverHidden(
                clipID: clip.id,
                reason: .notReady
            )
        }
        #endif
    }

    @MainActor
    private func endHover() {
        #if DEBUG
        TimelineFilmstripDebugProbe.shared.recordHoverExitRequested(clipID: clip.id)
        #endif
        preview = nil
    }

    private func previewOffsetX(for preview: TimelineFilmstripHoverPreview) -> CGFloat {
        let previewWidth = Self.previewImageSize.width
        guard clipWidth >= previewWidth else {
            return (clipWidth - previewWidth) / 2
        }
        return min(max(preview.localX - previewWidth / 2, 0), clipWidth - previewWidth)
    }

    private func hoverPreviewView(_ preview: TimelineFilmstripHoverPreview) -> some View {
        let label = sourceTimeLabel(preview.requestedSourceTime)
        return VStack(spacing: 0) {
            Image(decorative: preview.image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(
                    width: Self.previewImageSize.width,
                    height: Self.previewImageSize.height
                )
                .clipped()
                #if DEBUG
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                TimelineFilmstripDebugProbe.shared.recordHoverImageRendered(
                                    preview,
                                    size: proxy.size
                                )
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                TimelineFilmstripDebugProbe.shared.recordHoverImageRendered(
                                    preview,
                                    size: newSize
                                )
                            }
                    }
                }
                #endif

            Text(label)
                .font(MovieCutTypography.metadata.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, MovieCutSpacing.xSmall)
                .padding(.vertical, MovieCutSpacing.xSmall)
                .frame(maxWidth: .infinity)
                .background(MovieCutTheme.controlSurface)
                #if DEBUG
                .onAppear {
                    TimelineFilmstripDebugProbe.shared.recordHoverLabelRendered(
                        preview,
                        label: label
                    )
                }
                #endif
        }
        .frame(width: Self.previewImageSize.width)
        .background(MovieCutTheme.panelBackgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .stroke(MovieCutTheme.border, lineWidth: 0.5)
        }
        .shadow(color: MovieCutTheme.previewBackground.opacity(0.72), radius: MovieCutRadius.medium)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(NSLocalizedString("Filmstrip hover preview", comment: ""))
        .accessibilityValue(label)
        #if DEBUG
        .onDisappear {
            TimelineFilmstripDebugProbe.shared.recordHoverOverlayDisappeared(clipID: preview.clipID)
        }
        #endif
    }

    private func sourceTimeLabel(_ sourceTime: TimeInterval) -> String {
        let boundedTime = max(0, sourceTime.isFinite ? sourceTime : 0)
        let minutes = Int(boundedTime / 60)
        let seconds = boundedTime - Double(minutes * 60)
        return String(
            format: NSLocalizedString("Source %02d:%05.2f", comment: ""),
            minutes,
            seconds
        )
    }

    #if DEBUG
    @MainActor
    private func registerDebugHoverDriver() {
        TimelineFilmstripDebugProbe.shared.registerHoverDriver(
            clipID: clip.id,
            kind: clip.kind,
            supportsFilmstrip: supportsFilmstrip,
            clipWidth: clipWidth
        ) { action in
            switch action {
            case .active(let localX):
                resolveHover(localX: localX)
            case .ended:
                endHover()
            }
        }
    }
    #endif
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
enum TimelineFilmstripDebugHoverAction {
    case active(localX: CGFloat)
    case ended
}

enum TimelineFilmstripDebugHoverHiddenReason {
    case notReady
    case unsupported
}

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

    struct HoverSummary {
        let visible: Bool
        let imageWidth: CGFloat
        let imageHeight: CGFloat
        let labelPresent: Bool
        let requestedSourceTime: TimeInterval
        let selectedRequestedTime: TimeInterval
        let selectedActualTime: TimeInterval
        let selectedDigest: String
        let digestBelongsToPublishedFrames: Bool
        let absoluteError: TimeInterval
        let exitHidden: Bool
        let cacheMissHidden: Bool
        let unsupportedHidden: Bool
        let requestCountDelta: Int
        let generationCountDelta: Int
    }

    private struct HoverDriver {
        let kind: ClipKind
        let supportsFilmstrip: Bool
        let clipWidth: CGFloat
        let action: @MainActor (TimelineFilmstripDebugHoverAction) -> Void
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
    private var generationStartCount = 0
    private var hoverDrivers: [UUID: HoverDriver] = [:]
    private var hoverBaselineRequestCount: Int?
    private var hoverBaselineGenerationCount: Int?
    private var activeHoverClipID: UUID?
    private var resolvedHoverPreview: TimelineFilmstripHoverPreview?
    private var renderedHoverImageSize: CGSize?
    private var renderedHoverLabel: String?
    private var hoverDigestBelongsToPublishedFrames = false
    private var hoverExitRequestedClipID: UUID?
    private var hoverExitHidden = false
    private var hoverCacheMissHidden = false
    private var hoverUnsupportedHidden = false

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
        generationStartCount = 0
        hoverDrivers.removeAll(keepingCapacity: true)
        hoverBaselineRequestCount = nil
        hoverBaselineGenerationCount = nil
        activeHoverClipID = nil
        resolvedHoverPreview = nil
        renderedHoverImageSize = nil
        renderedHoverLabel = nil
        hoverDigestBelongsToPublishedFrames = false
        hoverExitRequestedClipID = nil
        hoverExitHidden = false
        hoverCacheMissHidden = false
        hoverUnsupportedHidden = false
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

    func recordGenerationStarted() {
        guard isArmed else { return }
        generationStartCount += 1
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

    func registerHoverDriver(
        clipID: UUID,
        kind: ClipKind,
        supportsFilmstrip: Bool,
        clipWidth: CGFloat,
        action: @escaping @MainActor (TimelineFilmstripDebugHoverAction) -> Void
    ) {
        guard isArmed, clipWidth.isFinite, clipWidth > 0 else { return }
        hoverDrivers[clipID] = HoverDriver(
            kind: kind,
            supportsFilmstrip: supportsFilmstrip,
            clipWidth: clipWidth,
            action: action
        )
    }

    func unregisterHoverDriver(clipID: UUID) {
        hoverDrivers[clipID] = nil
    }

    func driveReadyHover() -> Bool {
        guard isArmed,
              let ready,
              !ready.frames.isEmpty,
              let driver = hoverDrivers[ready.id.clipID],
              driver.supportsFilmstrip,
              ready.id.clipSourceRange.duration.isFinite,
              ready.id.clipSourceRange.duration > 0 else {
            return false
        }

        let targetFrame = ready.frames[ready.frames.count / 2]
        let sourceFraction = min(
            max(
                (targetFrame.actualTime - ready.id.clipSourceRange.start)
                    / ready.id.clipSourceRange.duration,
                0
            ),
            1
        )
        hoverBaselineRequestCount = requests.count
        hoverBaselineGenerationCount = generationStartCount
        activeHoverClipID = ready.id.clipID
        resolvedHoverPreview = nil
        renderedHoverImageSize = nil
        renderedHoverLabel = nil
        hoverDigestBelongsToPublishedFrames = false
        hoverExitRequestedClipID = nil
        hoverExitHidden = false
        hoverCacheMissHidden = false
        hoverUnsupportedHidden = false
        driver.action(.active(localX: driver.clipWidth * CGFloat(sourceFraction)))
        return true
    }

    var hasRenderedHoverEvidence: Bool {
        guard let resolvedHoverPreview,
              let renderedHoverImageSize,
              let renderedHoverLabel else {
            return false
        }
        return resolvedHoverPreview.clipID == activeHoverClipID
            && renderedHoverImageSize.width > 0
            && renderedHoverImageSize.height > 0
            && !renderedHoverLabel.isEmpty
    }

    func driveHoverExit() -> Bool {
        guard let activeHoverClipID,
              let driver = hoverDrivers[activeHoverClipID],
              hasRenderedHoverEvidence else {
            return false
        }
        hoverExitRequestedClipID = activeHoverClipID
        driver.action(.ended)
        return true
    }

    func driveNotReadyHover() -> Bool {
        guard let readyClipID = ready?.id.clipID,
              let candidate = hoverDrivers.first(where: {
                  $0.key != readyClipID && $0.value.supportsFilmstrip && $0.value.kind == .video
              }) else {
            return false
        }
        candidate.value.action(.active(localX: candidate.value.clipWidth / 2))
        candidate.value.action(.ended)
        return hoverCacheMissHidden
    }

    func driveUnsupportedHover() -> Bool {
        guard let candidate = hoverDrivers.first(where: {
            !$0.value.supportsFilmstrip
        }) else {
            return false
        }
        candidate.value.action(.active(localX: candidate.value.clipWidth / 2))
        candidate.value.action(.ended)
        return hoverUnsupportedHidden
    }

    func recordHoverResolved(_ preview: TimelineFilmstripHoverPreview) {
        guard isArmed, preview.clipID == activeHoverClipID else { return }
        resolvedHoverPreview = preview
    }

    func recordHoverHidden(
        clipID: UUID,
        reason: TimelineFilmstripDebugHoverHiddenReason
    ) {
        guard isArmed else { return }
        switch reason {
        case .notReady:
            if clipID != ready?.id.clipID {
                hoverCacheMissHidden = true
            }
        case .unsupported:
            hoverUnsupportedHidden = true
        }
    }

    func recordHoverImageRendered(
        _ preview: TimelineFilmstripHoverPreview,
        size: CGSize
    ) {
        guard isArmed,
              preview.clipID == activeHoverClipID,
              preview.digest == resolvedHoverPreview?.digest else {
            return
        }
        renderedHoverImageSize = size
        hoverDigestBelongsToPublishedFrames = ready?.frames.contains(where: {
            $0.digest == preview.digest
                && $0.actualTime == preview.selectedActualTime
                && $0.requestedTime == preview.selectedRequestedTime
        }) == true
    }

    func recordHoverLabelRendered(
        _ preview: TimelineFilmstripHoverPreview,
        label: String
    ) {
        guard isArmed,
              preview.clipID == activeHoverClipID,
              preview.digest == resolvedHoverPreview?.digest else {
            return
        }
        renderedHoverLabel = label
    }

    func recordHoverExitRequested(clipID: UUID) {
        guard isArmed, clipID == activeHoverClipID else { return }
        hoverExitRequestedClipID = clipID
    }

    func recordHoverOverlayDisappeared(clipID: UUID) {
        guard isArmed, hoverExitRequestedClipID == clipID else { return }
        hoverExitHidden = true
    }

    func completedHoverSummary() -> HoverSummary? {
        guard isArmed,
              hasRenderedHoverEvidence,
              let resolvedHoverPreview,
              let renderedHoverImageSize,
              let renderedHoverLabel,
              let hoverBaselineRequestCount,
              let hoverBaselineGenerationCount,
              hoverExitHidden,
              hoverCacheMissHidden,
              hoverUnsupportedHidden else {
            return nil
        }

        return HoverSummary(
            visible: true,
            imageWidth: renderedHoverImageSize.width,
            imageHeight: renderedHoverImageSize.height,
            labelPresent: !renderedHoverLabel.isEmpty,
            requestedSourceTime: resolvedHoverPreview.requestedSourceTime,
            selectedRequestedTime: resolvedHoverPreview.selectedRequestedTime,
            selectedActualTime: resolvedHoverPreview.selectedActualTime,
            selectedDigest: resolvedHoverPreview.digest,
            digestBelongsToPublishedFrames: hoverDigestBelongsToPublishedFrames,
            absoluteError: abs(
                resolvedHoverPreview.requestedSourceTime
                    - resolvedHoverPreview.selectedActualTime
            ),
            exitHidden: true,
            cacheMissHidden: true,
            unsupportedHidden: true,
            requestCountDelta: requests.count - hoverBaselineRequestCount,
            generationCountDelta: generationStartCount - hoverBaselineGenerationCount
        )
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
