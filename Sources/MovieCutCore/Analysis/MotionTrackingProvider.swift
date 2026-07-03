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
    /// - Returns: Time-ordered normalized display-space tracking boxes.
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

        let request = VNTrackObjectRequest(
            detectedObjectObservation: VNDetectedObjectObservation(
                boundingBox: Self.visionBoundingBox(fromDisplayRect: normalizedInitialRect)
            )
        )
        request.trackingLevel = .accurate

        let sequenceHandler = VNSequenceRequestHandler()
        var results: [TrackingResult] = []
        var time = startTime
        var didSeedInitialObservation = false

        while time <= endTime + (frameDuration * 0.5) {
            try Task.checkCancellation()

            var actualTime = CMTime.invalid
            let requestedTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let image = try? generator.copyCGImage(at: requestedTime, actualTime: &actualTime) else {
                time += frameDuration
                continue
            }

            let timestamp = actualTime.seconds.isFinite ? actualTime.seconds : time

            if !didSeedInitialObservation {
                results.append(TrackingResult(timestamp: timestamp, rect: normalizedInitialRect, confidence: 1))
                didSeedInitialObservation = true
                time += frameDuration
                continue
            }

            do {
                try sequenceHandler.perform([request], on: image)
            } catch {
                throw MotionTrackingError.trackingFailed(error.localizedDescription)
            }

            guard let observation = request.results?.first as? VNDetectedObjectObservation,
                  let displayRect = Self.clampedNormalizedRect(
                    Self.displayRect(fromVisionBoundingBox: observation.boundingBox)
                  )
            else {
                time += frameDuration
                continue
            }

            request.inputObservation = observation
            results.append(TrackingResult(
                timestamp: timestamp,
                rect: displayRect,
                confidence: observation.confidence
            ))
            time += frameDuration
        }

        return results.sorted { lhs, rhs in
            lhs.timestamp == rhs.timestamp ? lhs.rect.minX < rhs.rect.minX : lhs.timestamp < rhs.timestamp
        }
        #else
        throw MotionTrackingError.visionUnavailable
        #endif
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
