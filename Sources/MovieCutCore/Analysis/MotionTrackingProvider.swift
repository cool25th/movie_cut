import AVFoundation
import CoreGraphics
import Foundation

#if canImport(Vision)
import Vision
#endif

/// A normalized object-tracking box at a source timestamp.
public struct TrackingResult: Sendable, Codable, Equatable {
    /// Source time in seconds.
    public var timestamp: TimeInterval

    /// Normalized display-space rectangle, using a top-left origin.
    public var rect: CGRect

    /// Vision confidence for this tracked box, when available.
    public var confidence: Float?

    /// Creates a tracking result.
    public init(timestamp: TimeInterval, rect: CGRect, confidence: Float? = nil) {
        self.timestamp = timestamp
        self.rect = rect
        self.confidence = confidence
    }
}

/// Pure loss/recovery state machine used by `MotionTrackingProvider`.
///
/// Vision's sequential tracker can keep returning a plausible rectangle after
/// the selected subject disappears behind an occluder. Recovery therefore
/// cannot depend on `results == nil` alone: a candidate must be both confident
/// and motion-consistent with the last trusted trajectory. Once a candidate is
/// rejected, the planner keeps extrapolating the last trusted velocity and
/// asks the provider to recreate the Vision request around that predicted box.
///
/// This is intentionally detector-free v1 behavior. It does not pretend to
/// semantically re-identify arbitrary objects; it provides a bounded local
/// reacquisition policy for short occlusions while failing closed on stale or
/// implausible observations.
public struct MotionTrackingRecoveryPlanner: Sendable {
    /// Tunable recovery policy. Defaults are deliberately conservative: the
    /// confidence floor is low enough not to disturb the established normal
    /// fixture while the prediction IoU rejects a tracker that latches onto a
    /// stationary occluder as the expected subject keeps moving.
    public struct Configuration: Sendable, Equatable {
        public var minimumTrustedConfidence: Float
        public var minimumPredictionIoU: Double
        public var maximumRecoveryDuration: TimeInterval
        public var maximumNormalizedVelocityPerSecond: CGFloat

        public init(
            minimumTrustedConfidence: Float = 0.25,
            minimumPredictionIoU: Double = 0.30,
            maximumRecoveryDuration: TimeInterval = 2.25,
            maximumNormalizedVelocityPerSecond: CGFloat = 1.5
        ) {
            self.minimumTrustedConfidence = min(max(minimumTrustedConfidence, 0), 1)
            self.minimumPredictionIoU = min(max(minimumPredictionIoU, 0), 1)
            self.maximumRecoveryDuration = max(maximumRecoveryDuration, 0)
            self.maximumNormalizedVelocityPerSecond = max(maximumNormalizedVelocityPerSecond, 0)
        }
    }

    /// Why an observation was rejected and the tracker should be re-seeded.
    public enum ReseedReason: Sendable, Equatable {
        case lostObservation
        case lowConfidence
        case motionInconsistent
    }

    /// Decision for one decoded frame.
    public enum Decision: Sendable, Equatable {
        /// Candidate is trusted. `reacquired` is true for the first trusted
        /// result after one or more recovery frames.
        case accept(result: TrackingResult, reacquired: Bool)
        /// Candidate is not trusted. The provider should start a new Vision
        /// tracking sequence from `predictedRect` for the next frame.
        case reseed(predictedRect: CGRect, reason: ReseedReason)
        /// Recovery exceeded the bounded duration. The provider should stop
        /// rather than loop indefinitely on a lost subject.
        case exhausted
    }

    public let configuration: Configuration

    private var previousTrusted: TrackingResult?
    private var lastTrusted: TrackingResult
    private var recoveryStartedAt: TimeInterval?

    public init(seed: TrackingResult, configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.previousTrusted = nil
        self.lastTrusted = seed
        self.recoveryStartedAt = nil
    }

    /// Whether the planner is currently attempting to recover a lost subject.
    public var isRecovering: Bool {
        recoveryStartedAt != nil
    }

    /// Evaluates a Vision candidate for `timestamp`.
    ///
    /// A missing/invalid candidate, low confidence, or trajectory-inconsistent
    /// candidate starts/continues recovery. A trusted candidate resets recovery
    /// and becomes the new velocity anchor.
    public mutating func evaluate(
        timestamp: TimeInterval,
        candidateRect: CGRect?,
        confidence: Float?
    ) -> Decision {
        let predicted = predictedRect(at: timestamp)
        let wasRecovering = isRecovering

        guard let candidateRect,
              let candidate = MotionTrackingProvider.clampedNormalizedRect(candidateRect)
        else {
            return registerLoss(timestamp: timestamp, predictedRect: predicted, reason: .lostObservation)
        }

        let resolvedConfidence = confidence ?? 0
        guard resolvedConfidence >= configuration.minimumTrustedConfidence else {
            return registerLoss(timestamp: timestamp, predictedRect: predicted, reason: .lowConfidence)
        }

        // With only the initial seed there is not enough history to infer a
        // velocity; accept the first confident candidate and establish it.
        // Thereafter, reject candidates that have drifted away from the trusted
        // trajectory. During recovery this is also the reacquisition gate.
        if previousTrusted != nil {
            let predictionIoU = Self.intersectionOverUnion(candidate, predicted)
            guard predictionIoU >= configuration.minimumPredictionIoU else {
                return registerLoss(
                    timestamp: timestamp,
                    predictedRect: predicted,
                    reason: .motionInconsistent
                )
            }
        }

        let result = TrackingResult(
            timestamp: timestamp,
            rect: candidate,
            confidence: resolvedConfidence
        )
        previousTrusted = lastTrusted
        lastTrusted = result
        recoveryStartedAt = nil
        return .accept(result: result, reacquired: wasRecovering)
    }

    /// Constant-velocity extrapolation from the last two trusted centers.
    /// Size is deliberately held at the most recent trusted size so a noisy
    /// Vision box cannot create a runaway scale during an occlusion.
    public func predictedRect(at timestamp: TimeInterval) -> CGRect {
        guard let previousTrusted else {
            return Self.clampPreservingSize(lastTrusted.rect)
        }

        let sampleDelta = lastTrusted.timestamp - previousTrusted.timestamp
        guard sampleDelta.isFinite, sampleDelta > 1.0e-9 else {
            return Self.clampPreservingSize(lastTrusted.rect)
        }

        let horizon = max(timestamp - lastTrusted.timestamp, 0)
        guard horizon.isFinite else {
            return Self.clampPreservingSize(lastTrusted.rect)
        }

        let maxVelocity = configuration.maximumNormalizedVelocityPerSecond
        let rawVX = (lastTrusted.rect.midX - previousTrusted.rect.midX) / sampleDelta
        let rawVY = (lastTrusted.rect.midY - previousTrusted.rect.midY) / sampleDelta
        let vx = min(max(rawVX, -maxVelocity), maxVelocity)
        let vy = min(max(rawVY, -maxVelocity), maxVelocity)

        let center = CGPoint(
            x: lastTrusted.rect.midX + vx * horizon,
            y: lastTrusted.rect.midY + vy * horizon
        )
        let proposed = CGRect(
            x: center.x - lastTrusted.rect.width * 0.5,
            y: center.y - lastTrusted.rect.height * 0.5,
            width: lastTrusted.rect.width,
            height: lastTrusted.rect.height
        )
        return Self.clampPreservingSize(proposed)
    }

    private mutating func registerLoss(
        timestamp: TimeInterval,
        predictedRect: CGRect,
        reason: ReseedReason
    ) -> Decision {
        if recoveryStartedAt == nil {
            recoveryStartedAt = timestamp
        }

        if let recoveryStartedAt,
           timestamp - recoveryStartedAt > configuration.maximumRecoveryDuration {
            return .exhausted
        }
        return .reseed(predictedRect: predictedRect, reason: reason)
    }

    private static func clampPreservingSize(_ rect: CGRect) -> CGRect {
        let standardized = rect.standardized
        let width = min(max(standardized.width, 1.0e-6), 1)
        let height = min(max(standardized.height, 1.0e-6), 1)
        let x = min(max(standardized.minX, 0), 1 - width)
        let y = min(max(standardized.minY, 0), 1 - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return 0
        }
        let intersectionArea = Double(intersection.width * intersection.height)
        let lhsArea = Double(lhs.width * lhs.height)
        let rhsArea = Double(rhs.width * rhs.height)
        let unionArea = lhsArea + rhsArea - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }
}

/// Errors thrown by motion tracking.
public enum MotionTrackingError: Error, LocalizedError, Sendable, Equatable {
    case visionUnavailable
    case invalidInitialRect
    case invalidTimeRange
    case videoTrackUnavailable
    case trackingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .visionUnavailable:
            return "Motion tracking requires Vision on this platform."
        case .invalidInitialRect:
            return "Motion tracking needs a valid normalized selection rectangle."
        case .invalidTimeRange:
            return "Motion tracking needs a positive source time range."
        case .videoTrackUnavailable:
            return "Motion tracking needs a video track."
        case .trackingFailed(let message):
            return "Motion tracking failed: \(message)"
        }
    }
}

/// Tracks an initial normalized object box across video frames.
public final class MotionTrackingProvider: AnalysisProvider {
    /// Probe frame shorthand for the loop instrumentation in `track(...)`.
    private typealias Frame = MotionTrackingAnalysisProbe.Frame

    /// Whether Vision-backed motion tracking can run on this platform.
    public var isAvailable: Bool {
        #if canImport(Vision)
        true
        #else
        false
        #endif
    }

    /// User-visible provider name.
    public let providerName = "MotionTracking"

    /// Creates a motion-tracking provider.
    public init() {}

    public func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult {
        AnalysisResult(suggestions: [], sourceAssetID: asset.id.uuidString, providerName: providerName)
    }

    /// Tracks an object from an initial normalized display-space rectangle.
    ///
    /// - Parameters:
    ///   - videoURL: Source video URL.
    ///   - initialRect: Normalized display-space rectangle (0...1, top-left origin).
    ///   - timeRange: Source time range to process.
    ///   - frameRate: Optional sampling rate. Nil uses the asset's nominal video frame rate.
    /// - Returns: Time-ordered trusted normalized display-space tracking boxes.
    public func track(
        videoURL: URL,
        initialRect: CGRect,
        timeRange: TimeRange,
        frameRate: Double? = nil
    ) async throws -> [TrackingResult] {
        guard let normalizedInitialRect = Self.clampedNormalizedRect(initialRect) else {
            throw MotionTrackingError.invalidInitialRect
        }
        guard timeRange.start.isFinite, timeRange.duration.isFinite, timeRange.duration > 0 else {
            throw MotionTrackingError.invalidTimeRange
        }

        #if canImport(Vision)
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw MotionTrackingError.videoTrackUnavailable
        }

        let durationSeconds = duration.seconds.isFinite ? duration.seconds : timeRange.end
        let startTime = max(0, timeRange.start)
        let endTime = min(timeRange.end, durationSeconds)
        guard endTime > startTime else {
            throw MotionTrackingError.invalidTimeRange
        }

        let nominalFrameRate = Double((try? await videoTrack.load(.nominalFrameRate)) ?? 0)
        let framesPerSecond = Self.usableFrameRate(requested: frameRate, nominal: nominalFrameRate)
        let frameDuration = 1.0 / framesPerSecond

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        func makeRequest(seedRect: CGRect) -> VNTrackObjectRequest {
            let request = VNTrackObjectRequest(
                detectedObjectObservation: VNDetectedObjectObservation(
                    boundingBox: Self.visionBoundingBox(fromDisplayRect: seedRect)
                )
            )
            request.trackingLevel = .accurate
            return request
        }

        var request = makeRequest(seedRect: normalizedInitialRect)
        var sequenceHandler = VNSequenceRequestHandler()
        var recoveryPlanner: MotionTrackingRecoveryPlanner?
        var results: [TrackingResult] = []
        var time = startTime
        var didSeedInitialObservation = false

        while time <= endTime + (frameDuration * 0.5) {
            try Task.checkCancellation()

            let frameProbeStart = DispatchTime.now()
            var actualTime = CMTime.invalid
            let requestedTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let image = try? generator.copyCGImage(at: requestedTime, actualTime: &actualTime) else {
                MotionTrackingAnalysisProbe.record(Frame(
                    timestamp: time,
                    durationMs: Self.probeElapsedMs(since: frameProbeStart),
                    status: .decodeFailure
                ))
                time += frameDuration
                continue
            }

            let timestamp = actualTime.seconds.isFinite ? actualTime.seconds : time

            if !didSeedInitialObservation {
                let seed = TrackingResult(timestamp: timestamp, rect: normalizedInitialRect, confidence: 1)
                results.append(seed)
                recoveryPlanner = MotionTrackingRecoveryPlanner(seed: seed)
                request = makeRequest(seedRect: normalizedInitialRect)
                sequenceHandler = VNSequenceRequestHandler()
                didSeedInitialObservation = true
                MotionTrackingAnalysisProbe.record(Frame(
                    timestamp: timestamp,
                    durationMs: Self.probeElapsedMs(since: frameProbeStart),
                    status: .seed,
                    confidence: 1
                ))
                time += frameDuration
                continue
            }

            do {
                try sequenceHandler.perform([request], on: image)
            } catch {
                throw MotionTrackingError.trackingFailed(error.localizedDescription)
            }

            let observation = request.results?.first as? VNDetectedObjectObservation
            let candidateRect = observation.flatMap { observation in
                Self.clampedNormalizedRect(
                    Self.displayRect(fromVisionBoundingBox: observation.boundingBox)
                )
            }

            guard var planner = recoveryPlanner else {
                throw MotionTrackingError.trackingFailed("recovery planner was not initialized")
            }
            let decision = planner.evaluate(
                timestamp: timestamp,
                candidateRect: candidateRect,
                confidence: observation?.confidence
            )
            recoveryPlanner = planner

            switch decision {
            case .accept(let result, let reacquired):
                if let observation {
                    request.inputObservation = observation
                }
                results.append(result)
                MotionTrackingAnalysisProbe.record(Frame(
                    timestamp: timestamp,
                    durationMs: Self.probeElapsedMs(since: frameProbeStart),
                    status: reacquired ? .reacquired : .tracked,
                    confidence: result.confidence
                ))

            case .reseed(let predictedRect, let reason):
                // Start a fresh Vision sequence at the predicted trusted
                // trajectory. The seed is anchored to this decoded frame; the
                // newly-created request is first performed on the next frame,
                // matching the initial seed semantics above.
                request = makeRequest(seedRect: predictedRect)
                sequenceHandler = VNSequenceRequestHandler()
                MotionTrackingAnalysisProbe.record(Frame(
                    timestamp: timestamp,
                    durationMs: Self.probeElapsedMs(since: frameProbeStart),
                    status: Self.probeStatus(for: reason),
                    confidence: observation?.confidence
                ))

            case .exhausted:
                MotionTrackingAnalysisProbe.record(Frame(
                    timestamp: timestamp,
                    durationMs: Self.probeElapsedMs(since: frameProbeStart),
                    status: .recoveryExhausted,
                    confidence: observation?.confidence
                ))
                break
            }

            if case .exhausted = decision {
                break
            }
            time += frameDuration
        }

        return results.sorted { lhs, rhs in
            lhs.timestamp == rhs.timestamp ? lhs.rect.minX < rhs.rect.minX : lhs.timestamp < rhs.timestamp
        }
        #else
        throw MotionTrackingError.visionUnavailable
        #endif
    }

    #if canImport(Vision)
    private static func probeStatus(
        for reason: MotionTrackingRecoveryPlanner.ReseedReason
    ) -> MotionTrackingAnalysisProbe.Frame.Status {
        switch reason {
        case .lostObservation:
            return .lostObservation
        case .lowConfidence:
            return .lowConfidence
        case .motionInconsistent:
            return .motionInconsistent
        }
    }
    #endif

    /// Probe helper: wall-clock milliseconds elapsed since `start`.
    private static func probeElapsedMs(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
    }

    /// Clamps a normalized rectangle to the unit square. Returns nil for empty or non-finite boxes.
    public static func clampedNormalizedRect(_ rect: CGRect) -> CGRect? {
        let standardized = rect.standardized
        guard
            standardized.origin.x.isFinite,
            standardized.origin.y.isFinite,
            standardized.size.width.isFinite,
            standardized.size.height.isFinite
        else {
            return nil
        }

        let minX = clamp(standardized.minX, lower: 0, upper: 1)
        let minY = clamp(standardized.minY, lower: 0, upper: 1)
        let maxX = clamp(standardized.maxX, lower: 0, upper: 1)
        let maxY = clamp(standardized.maxY, lower: 0, upper: 1)
        let width = maxX - minX
        let height = maxY - minY

        guard width > 0, height > 0 else {
            return nil
        }

        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Converts a normalized top-left display rect into Vision's normalized bottom-left coordinate space.
    public static func visionBoundingBox(fromDisplayRect rect: CGRect) -> CGRect {
        let standardized = rect.standardized
        return CGRect(
            x: standardized.minX,
            y: 1 - standardized.maxY,
            width: standardized.width,
            height: standardized.height
        )
    }

    /// Converts Vision's normalized bottom-left bounding box into a top-left display rect.
    public static func displayRect(fromVisionBoundingBox rect: CGRect) -> CGRect {
        let standardized = rect.standardized
        return CGRect(
            x: standardized.minX,
            y: 1 - standardized.maxY,
            width: standardized.width,
            height: standardized.height
        )
    }

    private static func usableFrameRate(requested: Double?, nominal: Double) -> Double {
        let preferred = requested.flatMap { value -> Double? in
            guard value.isFinite, value > 0 else { return nil }
            return value
        } ?? nominal

        guard preferred.isFinite, preferred > 0 else {
            return 30
        }

        return min(max(preferred, 1), 120)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}