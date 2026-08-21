import Foundation

/// Harness-only per-frame probe for `MotionTrackingProvider` (T2-M). Tests arm
/// it explicitly before calling `track(...)` and take the recorded frames
/// afterwards; the provider unconditionally reports into it and the record is
/// dropped unless armed, so production analysis pays one lock round-trip per
/// frame (negligible next to the Vision call it wraps). Mirrors
/// CompositorRenderProbe's lock-guarded shared state and take-and-reset
/// semantics, but lives in Core because the provider is a Core type.
public enum MotionTrackingAnalysisProbe {
    /// One analyzed (or skipped) frame of a tracking session.
    public struct Frame: Sendable, Equatable {
        public enum Status: String, Sendable, Equatable {
            /// First decoded frame; seeds the initial rect without Vision.
            case seed
            /// Vision returned a trusted observation on the normal path.
            case tracked
            /// First trusted observation after one or more recovery frames.
            case reacquired
            /// Vision returned no usable observation; the next request is reseeded.
            case lostObservation
            /// Vision returned a box below the trusted-confidence floor; reseed follows.
            case lowConfidence
            /// Vision returned a confident box inconsistent with the trusted trajectory.
            case motionInconsistent
            /// The bounded recovery window expired without a trusted observation.
            case recoveryExhausted
            /// The frame could not be decoded.
            case decodeFailure
        }

        /// Requested source time in seconds.
        public let timestamp: Double
        /// Wall time spent on this frame in milliseconds.
        public let durationMs: Double
        public let status: Status
        public let confidence: Float?

        public init(timestamp: Double, durationMs: Double, status: Status, confidence: Float? = nil) {
            self.timestamp = timestamp
            self.durationMs = durationMs
            self.status = status
            self.confidence = confidence
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var armed = false
    nonisolated(unsafe) private static var frames: [Frame] = []

    /// Arms the probe and clears any previous session.
    public static func arm() {
        lock.lock()
        armed = true
        frames.removeAll()
        lock.unlock()
    }

    /// Records a frame if a session is armed; no-op otherwise.
    public static func record(_ frame: Frame) {
        lock.lock()
        if armed { frames.append(frame) }
        lock.unlock()
    }

    /// Returns the recorded frames of this session and disarms. Returns nil
    /// when no armed session recorded anything.
    public static func takeAndReset() -> [Frame]? {
        lock.lock()
        defer {
            armed = false
            frames.removeAll()
            lock.unlock()
        }
        guard armed, !frames.isEmpty else { return nil }
        return frames
    }
}
