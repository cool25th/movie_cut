import CoreMedia
import Foundation

/// G-25 stage-1 audio render graph SPECIFICATION — the single source both the
/// preview and the export engine build their graphs from
/// (docs/AUDIO_RENDER_GRAPH_SPEC_20260817.md). This file is the pure,
/// renderless model layer (Inc 7): types, serialization, and the stage-1
/// support classification only. Engines, latency compensation, and the null
/// test are Inc 8; meters/UI and the AAC post-check are Inc 9.
///
/// Structure (spec §1):
///
///     sources[]     original or versioned derived media (stems etc.)
///     clipStrips[]  per-clip chain: channelMapping → gain/fades → … → pan
///     trackBuses[]  per-track: summing → ducking → fader → meter
///     masterBus     master chain → LUFS/true-peak meter → encoder
public struct AudioRenderGraphSpec: Codable, Sendable, Equatable {
    /// Schema version; starts at 1. Any change to these types must bump it
    /// and add a migration test (spec §2).
    public var version: Int
    public var sources: [AudioGraphSource]
    public var clipStrips: [AudioGraphClipStrip]
    public var trackBuses: [AudioGraphTrackBus]
    public var masterBus: AudioGraphMasterBus
    public var timebase: AudioGraphTimebase
    public var rendering: AudioGraphRenderRules

    public init(
        version: Int = 1,
        sources: [AudioGraphSource] = [],
        clipStrips: [AudioGraphClipStrip] = [],
        trackBuses: [AudioGraphTrackBus] = [],
        masterBus: AudioGraphMasterBus = AudioGraphMasterBus(),
        timebase: AudioGraphTimebase = AudioGraphTimebase(),
        rendering: AudioGraphRenderRules = AudioGraphRenderRules()
    ) {
        self.version = version
        self.sources = sources
        self.clipStrips = clipStrips
        self.trackBuses = trackBuses
        self.masterBus = masterBus
        self.timebase = timebase
        self.rendering = rendering
    }
}

/// An original media file or a versioned derived media (ML stem, NR output).
/// Derived media is CONSUMED as a source in stage 1; replacing the
/// destructive pipeline is G-26 (spec §0).
public struct AudioGraphSource: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case original
        case derived
    }

    public var id: UUID
    public var kind: Kind
    public var url: URL
    /// Set for derived media: the source this was derived from.
    public var derivedFrom: UUID?
    /// Algorithm identity recorded when the derived media was produced
    /// (spec §6 — reuse-over-regenerate on version mismatch).
    public var algorithmVersion: String?
    /// The source's own sample rate when it differs from the graph rate;
    /// the engine resamples to the graph rate (spec §3, mixed-rate rule).
    public var nativeSampleRate: Double?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        url: URL,
        derivedFrom: UUID? = nil,
        algorithmVersion: String? = nil,
        nativeSampleRate: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.derivedFrom = derivedFrom
        self.algorithmVersion = algorithmVersion
        self.nativeSampleRate = nativeSampleRate
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, url
        case derivedFrom, algorithmVersion, nativeSampleRate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        url = try container.decode(URL.self, forKey: .url)
        derivedFrom = try container.decodeIfPresent(UUID.self, forKey: .derivedFrom)
        algorithmVersion = try container.decodeIfPresent(String.self, forKey: .algorithmVersion)
        nativeSampleRate = try container.decodeIfPresent(Double.self, forKey: .nativeSampleRate)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(url, forKey: .url)
        // Optional node data is encodeIfPresent so an empty graph's JSON
        // bytes stay canonical (spec §2).
        try container.encodeIfPresent(derivedFrom, forKey: .derivedFrom)
        try container.encodeIfPresent(algorithmVersion, forKey: .algorithmVersion)
        try container.encodeIfPresent(nativeSampleRate, forKey: .nativeSampleRate)
    }
}

/// Per-clip processing chain specification (spec §1). Stage-1 processor
/// slots are intentionally ABSENT from this struct — unimplemented node
/// kinds only exist as enum cases and are rejected by consuming engines
/// (spec §5), so the spec can never describe a render it cannot produce.
public struct AudioGraphClipStrip: Codable, Sendable, Equatable {
    public var clipId: UUID
    public var sourceId: UUID
    public var channelMapping: AudioGraphChannelMapping
    public var gain: [AudioGraphAutomationPoint]
    public var fades: [AudioGraphFade]
    public var pan: [AudioGraphAutomationPoint]
    /// Node kinds disabled for this strip (bypass). nil = none.
    public var disabledNodeKinds: [AudioGraphNodeKind]?

    public init(
        clipId: UUID,
        sourceId: UUID,
        channelMapping: AudioGraphChannelMapping = .stereo,
        gain: [AudioGraphAutomationPoint] = [],
        fades: [AudioGraphFade] = [],
        pan: [AudioGraphAutomationPoint] = [],
        disabledNodeKinds: [AudioGraphNodeKind]? = nil
    ) {
        self.clipId = clipId
        self.sourceId = sourceId
        self.channelMapping = channelMapping
        self.gain = gain
        self.fades = fades
        self.pan = pan
        self.disabledNodeKinds = disabledNodeKinds
    }

    private enum CodingKeys: String, CodingKey {
        case clipId, sourceId, channelMapping, gain, fades, pan
        case disabledNodeKinds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clipId = try container.decode(UUID.self, forKey: .clipId)
        sourceId = try container.decode(UUID.self, forKey: .sourceId)
        channelMapping = try container.decode(AudioGraphChannelMapping.self, forKey: .channelMapping)
        gain = try container.decodeIfPresent([AudioGraphAutomationPoint].self, forKey: .gain) ?? []
        fades = try container.decodeIfPresent([AudioGraphFade].self, forKey: .fades) ?? []
        pan = try container.decodeIfPresent([AudioGraphAutomationPoint].self, forKey: .pan) ?? []
        disabledNodeKinds = try container.decodeIfPresent([AudioGraphNodeKind].self, forKey: .disabledNodeKinds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clipId, forKey: .clipId)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(channelMapping, forKey: .channelMapping)
        try container.encode(gain, forKey: .gain)
        try container.encode(fades, forKey: .fades)
        try container.encode(pan, forKey: .pan)
        try container.encodeIfPresent(disabledNodeKinds, forKey: .disabledNodeKinds)
    }
}

/// Per-track bus: summing → sidechain ducking → fader → meter (spec §1).
public struct AudioGraphTrackBus: Codable, Sendable, Equatable {
    public var trackId: UUID
    /// Clip strips feeding this bus, in mix order.
    public var inputStripIds: [UUID]
    public var fader: [AudioGraphAutomationPoint]
    public var mute: Bool
    public var solo: Bool
    public var ducking: AudioGraphDucking?

    public init(
        trackId: UUID,
        inputStripIds: [UUID] = [],
        fader: [AudioGraphAutomationPoint] = [],
        mute: Bool = false,
        solo: Bool = false,
        ducking: AudioGraphDucking? = nil
    ) {
        self.trackId = trackId
        self.inputStripIds = inputStripIds
        self.fader = fader
        self.mute = mute
        self.solo = solo
        self.ducking = ducking
    }

    private enum CodingKeys: String, CodingKey {
        case trackId, inputStripIds, fader, mute, solo, ducking
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackId = try container.decode(UUID.self, forKey: .trackId)
        inputStripIds = try container.decodeIfPresent([UUID].self, forKey: .inputStripIds) ?? []
        fader = try container.decodeIfPresent([AudioGraphAutomationPoint].self, forKey: .fader) ?? []
        mute = try container.decodeIfPresent(Bool.self, forKey: .mute) ?? false
        solo = try container.decodeIfPresent(Bool.self, forKey: .solo) ?? false
        ducking = try container.decodeIfPresent(AudioGraphDucking.self, forKey: .ducking)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trackId, forKey: .trackId)
        try container.encode(inputStripIds, forKey: .inputStripIds)
        try container.encode(fader, forKey: .fader)
        try container.encode(mute, forKey: .mute)
        try container.encode(solo, forKey: .solo)
        try container.encodeIfPresent(ducking, forKey: .ducking)
    }
}

/// Master bus: [master EQ]* → [limiter]* → LUFS/true-peak meter → encoder
/// (spec §1). A limiter, when present, MUST declare its latency — a graph
/// that contains an undeclared-latency processor is rejected by the engine
/// (spec §4), so the optional here pairs with `rendering.declaredLatencies`.
public struct AudioGraphMasterBus: Codable, Sendable, Equatable {
    public var fader: [AudioGraphAutomationPoint]
    public var limiter: AudioGraphNodeLatency?
    /// Target integrated loudness in LUFS for the meter guideline
    /// (spec §7: -16…-14 LUFS-I guideline, never auto-enforced).
    public var targetLoudness: Double?

    public init(
        fader: [AudioGraphAutomationPoint] = [],
        limiter: AudioGraphNodeLatency? = nil,
        targetLoudness: Double? = nil
    ) {
        self.fader = fader
        self.limiter = limiter
        self.targetLoudness = targetLoudness
    }

    private enum CodingKeys: String, CodingKey {
        case fader, limiter, targetLoudness
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fader = try container.decodeIfPresent([AudioGraphAutomationPoint].self, forKey: .fader) ?? []
        limiter = try container.decodeIfPresent(AudioGraphNodeLatency.self, forKey: .limiter)
        targetLoudness = try container.decodeIfPresent(Double.self, forKey: .targetLoudness)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fader, forKey: .fader)
        try container.encodeIfPresent(limiter, forKey: .limiter)
        try container.encodeIfPresent(targetLoudness, forKey: .targetLoudness)
    }
}

/// Stage-1 ducking parameters on a track bus. The sidechain analysis itself
/// stays in the existing planner (spec §0 — destructive ducking media is
/// unchanged in stage 1); the engine consumes this level when building the
/// bus chain.
public struct AudioGraphDucking: Codable, Sendable, Equatable {
    /// Ducking depth in dB (how far non-speech buses dip under speech).
    public var levelDb: Double

    public init(levelDb: Double) {
        self.levelDb = levelDb
    }
}

/// One automation point. Time coordinates are AUDIO SAMPLE POSITIONS in the
/// graph's timebase — storing seconds is forbidden by design (spec §3):
/// integer sample positions keep preview↔export sample alignment exact in
/// mixed-rate projects.
public struct AudioGraphAutomationPoint: Codable, Sendable, Equatable {
    /// Samples since the graph origin (0).
    public var samplePosition: Int64
    /// Gain in dB, fader in dB, pan in -1…1 (full left…full right).
    public var value: Double

    public init(samplePosition: Int64, value: Double) {
        self.samplePosition = samplePosition
        self.value = value
    }
}

/// A clip fade segment in sample coordinates. Curve semantics in stage 1 are
/// linear; the curve field is part of the schema from day one so adding
/// curves later is not a schema change.
public struct AudioGraphFade: Codable, Sendable, Equatable {
    public enum Curve: String, Codable, Sendable {
        case linear
        case exponential
    }

    /// Which direction the gain ramps inside the window:
    /// `.fadeIn` = 0→1 (a fade-in), `.fadeOut` = 1→0 (a fade-out).
    /// Without this the renderer can only express ascending ramps.
    public enum Direction: String, Codable, Sendable {
        case fadeIn
        case fadeOut
    }

    public var startSample: Int64
    public var endSample: Int64
    public var curve: Curve
    public var direction: Direction

    public init(
        startSample: Int64,
        endSample: Int64,
        curve: Curve = .linear,
        direction: Direction = .fadeIn
    ) {
        self.startSample = startSample
        self.endSample = endSample
        self.curve = curve
        self.direction = direction
    }
}

/// Channel mapping at the head of every clip strip (spec §1).
public enum AudioGraphChannelMapping: String, Codable, Sendable {
    case mono
    case stereo
    case dualMono
}

/// Node kinds of the graph. The stage-1 set is supported by both engines;
/// the rest are PLACEHOLDER slots — they exist so a serialized graph can
/// describe them, and a consuming engine that meets one MUST reject the
/// graph with an explicit error (spec §5: never silently degrade).
public enum AudioGraphNodeKind: String, Codable, Sendable, CaseIterable {
    // Stage 1 (supported).
    case channelMapping
    case gainFade
    case pan
    case summing
    case ducking
    case fader
    case meter
    case encoder

    // Placeholder slots (unimplemented — engines reject on encounter).
    case noiseReduction
    case mlStem
    case eq
    case compressor
    case creativeFX
    case masterEQ
    case limiter

    /// Whether both stage-1 engines implement this node kind. Engines use
    /// this (plus their own capability set) to reject unsupported graphs
    /// instead of silently skipping them.
    public var isStage1Supported: Bool {
        switch self {
        case .channelMapping, .gainFade, .pan, .summing, .ducking, .fader, .meter, .encoder:
            return true
        case .noiseReduction, .mlStem, .eq, .creativeFX, .masterEQ:
            return false
        case .compressor, .limiter:
            // G-26 (Phase 2): the compressor and limiter DSP are
            // implemented and wired into the graph render path via
            // AudioGraphMasterChain. The engines now SUPPORT these.
            return true
        }
    }
}

/// The graph's sample-time declaration (spec §3). `origin` is the timeline
/// instant the graph's sample 0 corresponds to, serialized as the rational
/// string "num/den" (CMTime value/timescale) so the JSON stays exact — no
/// floating-point timeline coordinates anywhere in a graph.
public struct AudioGraphTimebase: Codable, Sendable, Equatable {
    /// Graph (master output) sample rate. Mixed-rate sources declare their
    /// own `nativeSampleRate` and the engine resamples to this rate.
    public var sampleRate: Double
    public var origin: CMTime

    public init(sampleRate: Double = 48_000, origin: CMTime = .zero) {
        self.sampleRate = sampleRate
        self.origin = origin
    }

    private enum CodingKeys: String, CodingKey {
        case sampleRate, origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        let rational = try container.decode(String.self, forKey: .origin)
        origin = try Self.decodeOrigin(rational)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(Self.encodeOrigin(origin), forKey: .origin)
    }

    /// Formats a CMTime as the canonical "num/den" rational string
    /// (value/timescale; flags and epoch are not part of graph time).
    public static func encodeOrigin(_ time: CMTime) -> String {
        "\(time.value)/\(time.timescale)"
    }

    /// Parses a "num/den" rational string into a CMTime. Throws for
    /// malformed input or a zero/negative denominator — a graph with a
    /// broken timebase must not decode half-validly.
    public static func decodeOrigin(_ string: String) throws -> CMTime {
        let parts = string.split(separator: "/")
        guard parts.count == 2,
              let numerator = Int64(parts[0]),
              let denominator = Int32(parts[1]),
              denominator > 0
        else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.origin],
                debugDescription: "timebase origin must be \"num/den\" with a positive denominator, got \"\(string)\""
            ))
        }
        return CMTime(value: numerator, timescale: denominator)
    }
}

/// Render rules shared by both engines (spec §4). Every processor node
/// DECLARES its latency here; the engines compute ONE global look-ahead
/// compensation from the maximum (the compensation function itself is a
/// Core pure function delivered with the Inc 8 engines — stage-1 nodes are
/// all zero-latency, but the path exists from day one so adding processors
/// never changes the schema).
public struct AudioGraphRenderRules: Codable, Sendable, Equatable {
    public var declaredLatencies: [AudioGraphNodeLatency]?

    public init(declaredLatencies: [AudioGraphNodeLatency]? = nil) {
        self.declaredLatencies = declaredLatencies
    }

    private enum CodingKeys: String, CodingKey {
        case declaredLatencies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        declaredLatencies = try container.decodeIfPresent([AudioGraphNodeLatency].self, forKey: .declaredLatencies)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(declaredLatencies, forKey: .declaredLatencies)
    }
}

/// A processor node's latency declaration (spec §4). `algorithmVersion`
/// uses the same semantic-version identity as derived-media presets
/// (spec §6), so latency behavior is attributable to an algorithm version.
public struct AudioGraphNodeLatency: Codable, Sendable, Equatable {
    public var nodeKind: AudioGraphNodeKind
    public var algorithmVersion: String
    /// Fixed latency the node reports, in samples.
    public var reportedLatencySamples: Int64
    /// Future samples the node needs (look-ahead) — compressors etc.
    public var lookAheadSamples: Int64

    public init(
        nodeKind: AudioGraphNodeKind,
        algorithmVersion: String,
        reportedLatencySamples: Int64,
        lookAheadSamples: Int64 = 0
    ) {
        self.nodeKind = nodeKind
        self.algorithmVersion = algorithmVersion
        self.reportedLatencySamples = reportedLatencySamples
        self.lookAheadSamples = lookAheadSamples
    }
}
