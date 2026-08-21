import Foundation

/// G-28 — the measured per-effect cost profile that gates the effect
/// browser's search/rank and feeds PERFORMANCE_SLO. The schema is the
/// PREREQUISITE the phase-2 plan calls out ("착수 전 EffectCostProfile
/// 스키마 확정"): values are MEASURED (ms/frame on a reference canvas,
/// memory peak, GPU vs CPU path), never self-reported by effects.
///
/// The profile is versioned: when the measurement environment changes
/// (new hardware, new canvas size), the `measurementVersion` bumps and
/// profiles re-measure.
public struct EffectCostProfile: Codable, Sendable, Equatable, Identifiable {
    /// The effect this profile measures.
    public var effectType: EffectType
    /// Measured cost per frame at the reference canvas (1080p), in ms.
    /// The preview SLO's primary signal — high ms/frame effects need
    /// proxy or real-time degradation before the browser ranks them
    /// prominent.
    public var millisecondsPerFrame: Double
    /// Peak memory footprint during application, in MB.
    public var peakMemoryMegabytes: Double
    /// Whether the effect's pixel path runs on the GPU (Core Image
    /// filters with hardware acceleration) or CPU (software renderers,
    /// LUT cube interpolation on CPU).
    public var computePath: ComputePath
    /// Whether the effect is real-time-safe at 1080p (ms/frame within
    /// the 30fps budget of 33.3ms, with headroom for the compositor).
    public var isRealTimeSafe: Bool
    /// The measurement environment version (bump when reference
    /// hardware or canvas changes).
    public var measurementVersion: Int
    /// The reference canvas the numbers were measured at.
    public var referenceCanvas: ReferenceCanvas

    public var id: String { "\(effectType.rawValue)-v\(measurementVersion)" }

    public enum ComputePath: String, Codable, Sendable {
        case gpu
        case cpu
    }

    public struct ReferenceCanvas: Codable, Sendable, Equatable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        public static let hd1080 = ReferenceCanvas(width: 1920, height: 1080)
    }

    public init(
        effectType: EffectType,
        millisecondsPerFrame: Double,
        peakMemoryMegabytes: Double,
        computePath: ComputePath,
        measurementVersion: Int = 1,
        referenceCanvas: ReferenceCanvas = .hd1080
    ) {
        self.effectType = effectType
        self.millisecondsPerFrame = millisecondsPerFrame
        self.peakMemoryMegabytes = peakMemoryMegabytes
        self.computePath = computePath
        // 30fps budget 33.3ms; the compositor needs ~10ms headroom.
        self.isRealTimeSafe = millisecondsPerFrame <= 23.0
        self.measurementVersion = measurementVersion
        self.referenceCanvas = referenceCanvas
    }

    /// Cost tier for the browser's visual badge: green (instant),
    /// yellow (noticeable), red (needs proxy/degradation).
    public var costTier: CostTier {
        if millisecondsPerFrame <= 5.0 {
            return .instant
        }
        if millisecondsPerFrame <= 15.0 {
            return .moderate
        }
        return .heavy
    }

    public enum CostTier: String, Codable, Sendable {
        case instant
        case moderate
        case heavy
    }
}
