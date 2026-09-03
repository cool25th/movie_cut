import CoreMedia
import Foundation

/// G-25 product-path migration, step 1: builds an `AudioRenderGraphSpec`
/// (+ runtime activations) from a real project's tracks — the ONE mapping
/// the preview and export generators consume as the audioMix path retires
/// ("프리뷰와 출력은 같은 명세에서 각자 그래프를 생성", spec §1).
///
/// Product model → graph model mapping (spec v1.1):
/// - `Clip.volume` (linear 0…2) → one CONSTANT gain point in dB
///   (20·log10; 0 clamps to the −120 dB digital-silence floor).
/// - `fadeInDuration`/`fadeOutDuration` → linear amplitude fades in sample
///   coordinates — the audioMix path's setVolumeRamp is linear in amplitude
///   too, so fade semantics match exactly.
/// - `Clip.duckingRanges` + `duckingLevel` → the planner's result
///   MATERIALIZED as piecewise gain automation on the clip strip
///   (spec §1.1): ranges are clip-local in the product model and are
///   REBASED to absolute graph sample positions here; ramps live INSIDE
///   each range (attack [start, start+attack], release [end−release, end])
///   — the current product's timing. Ramp shape is dB-linear (graph
///   standard) where the audioMix path ramps linear in amplitude; the
///   audioMix path's fade-window clamping is NOT reproduced (an
///   AVFoundation limitation the graph's gain×fade multiply has no need
///   for). Ranges shorter than attack+release duck nothing, as today.
/// - `Track.isMuted`/`isSolo` → bus mute/solo (audio-capable tracks only),
///   the same semantics the AVFoundation path enforces since Inc 9.
/// - `Clip.playbackRate` ≠ 1 → a PER-CLIP speed-adjusted source (§3.1):
///   the adapter time-stretches the clip's media so the graph reads at
///   speed 1. Activation math in stretched coordinates: source offset and
///   seconds divide by the clamped speed, timeline duration =
///   sourceRange.duration / speed — matching the engines' scaleTimeRange.
///   Speed RAMPS cannot map to a single rate and need pre-rendered media
///   (wiring increment).
/// - Clips on audio-kind tracks AND video clips' embedded audio become
///   strips on their track's bus. A clip whose EFFECTIVE audio media is a
///   render-time derivation (EQ/NR, spec §0 v1.1) consumes a per-clip
///   `.derived` source; the adapter derives and decodes it — the graph
///   never re-derives.
///
/// Facts the builder cannot know (media file contents) arrive as closures
/// and default to graph-rate stereo — the engine adapter supplies real
/// values after decoding (spec §3.1: adapters normalize sources to the
/// graph rate and speed 1; a non-graph rate returned here engages the
/// renderer's nearest-frame ratio read, which is the §9.2 dummy-only
/// fallback, never the product path).
public enum AudioGraphProjectBuilder {
    public struct Plan: Sendable, Equatable {
        public var spec: AudioRenderGraphSpec
        public var activations: [UUID: AudioGraphStripActivation]
        /// Asset ids the caller must decode into `AudioGraphSourceAudio`,
        /// deduplicated in first-use order.
        public var sourceAssetIds: [UUID]
        /// Clips whose effective media the caller must DERIVE (EQ/NR render)
        /// before decoding (spec §0 v1.1). Their graph source id IS the clip
        /// id; derivation input is the clip's asset.
        public var derivedClipIds: [UUID]
        /// Clips with playback speed ≠ 1 the caller must pre-render at that
        /// speed (spec §3.1 — `AudioGraphSourceAdapter.timeStretched`),
        /// before or after derivation as applicable. Their graph source id
        /// IS the clip id (a stretched source cannot be shared with
        /// speed-1 clips of the same asset).
        public var speedAdjustedSources: [SpeedAdjustedSource]
        /// Clips with a SPEED RAMP (≥2 points) the caller must pre-render
        /// through the ramp (`AudioGraphSourceAdapter.timeStretchedRamped`).
        /// Like constant-speed clips the source is per-clip, but the
        /// pre-render covers ONLY the clip's source window warped by the
        /// curve — so the activation reads from offset 0 at rate 1 over the
        /// clip's (curve-mapped) timeline duration. A ramp wins over a
        /// constant playbackRate, matching the legacy composition
        /// (`didApplySpeedRamp` skipped the plain scaling).
        public var rampAdjustedSources: [RampAdjustedSource]
    }

    /// A per-clip speed normalization request (spec §3.1).
    public struct SpeedAdjustedSource: Sendable, Equatable {
        public var clipId: UUID
        public var assetId: UUID
        /// The product's clamped playback rate (0.25–4), ≠ 1.
        public var speed: Double

        public init(clipId: UUID, assetId: UUID, speed: Double) {
            self.clipId = clipId
            self.assetId = assetId
            self.speed = speed
        }
    }

    /// A per-clip speed-RAMP pre-render request (spec §3.1). `points` are
    /// the clip's raw ramp points; the caller builds the `SpeedRampCurve`.
    public struct RampAdjustedSource: Sendable, Equatable {
        public var clipId: UUID
        public var assetId: UUID
        public var points: [SpeedRampPoint]

        public init(clipId: UUID, assetId: UUID, points: [SpeedRampPoint]) {
            self.clipId = clipId
            self.assetId = assetId
            self.points = points
        }
    }

    /// A clip's effective audio media when it is a render-time derivation
    /// (spec §0 v1.1) — e.g. the EQ/NR-rendered file the export path
    /// produces today. `algorithmVersion` uses the §6 semantic-version
    /// identity so reopens can prefer reuse-over-regenerate.
    public struct EffectiveAudioMedia: Sendable, Equatable {
        public var url: URL
        public var algorithmVersion: String?

        public init(url: URL, algorithmVersion: String? = nil) {
            self.url = url
            self.algorithmVersion = algorithmVersion
        }
    }

    public static let silenceFloorDb = -120.0

    /// - Parameters:
    ///   - tracks: the FLATTENED tracks (what the engines render); nil uses
    ///     `project.timeline.tracks`.
    ///   - decodedSampleRateFor: sample rate of the audio the caller will
    ///     SUPPLY for a source id (spec §3.1). Normalized adapters return
    ///     nil (graph rate); a non-graph rate engages the renderer's
    ///     dummy-only nearest-frame ratio read.
    ///   - channelCountFor: the supplied audio's channel count (mono sources
    ///     map through the mono channel mapping).
    ///   - effectiveMediaFor: the clip's derived effective media when the
    ///     clip consumes a render-time derivation (EQ/NR); nil = original.
    public static func build(
        project: Project,
        tracks: [Track]? = nil,
        graphSampleRate: Double = 48_000,
        decodedSampleRateFor: (UUID) -> Double? = { _ in nil },
        channelCountFor: (UUID) -> Int? = { _ in nil },
        effectiveMediaFor: (Clip) -> EffectiveAudioMedia? = { _ in nil }
    ) -> Plan {
        let timebase = AudioGraphTimebase(sampleRate: graphSampleRate, origin: .zero)
        let renderTracks = tracks ?? project.timeline.tracks

        var sources: [UUID: AudioGraphSource] = [:]
        var sourceOrder: [UUID] = []
        var plainAssetIds: [UUID] = []
        var strips: [AudioGraphClipStrip] = []
        var activations: [UUID: AudioGraphStripActivation] = [:]
        var buses: [AudioGraphTrackBus] = []
        var derivedClipIds: [UUID] = []
        var speedAdjustedSources: [SpeedAdjustedSource] = []
        var rampAdjustedSources: [RampAdjustedSource] = []

        func samplePosition(_ seconds: TimeInterval) -> Int64 {
            timebase.samplePosition(at: CMTime(seconds: seconds, preferredTimescale: 600))
        }

        for track in renderTracks.sorted(by: { $0.zIndex < $1.zIndex }) {
            var trackStripIds: [UUID] = []
            for clip in track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                guard let assetId = clip.assetId,
                      let asset = project.mediaLibrary.assets[assetId] else { continue }
                // BUG-ACC-01: an adjustment layer is a grading CONTAINER (G-03)
                // — it renders no content and must contribute no audio strip.
                // Without this guard the layer's assetId (it borrows a real
                // asset's id for scoping) made it an audible strip; combined
                // with magnetic compaction shoving the overlapped layer after
                // the visible clips, the mix's audible span grew to
                // video+BGM lengths SUMMED (2s+4s → 6s measured).
                guard !clip.isAdjustmentLayer else { continue }
                // Audio tracks carry audio clips; video tracks contribute
                // their clips' embedded audio (images/text have none).
                let carriesAudio = track.kind == .audio ? (clip.kind == .audio || clip.kind == .video)
                    : (asset.kind == .audio || asset.kind == .video)
                guard carriesAudio, clip.timelineRange.duration > 0 else { continue }

                // Effective media (spec §0 v1.1): an EQ/NR derivation is the
                // clip's own source (per-clip, since EQ settings are
                // per-clip even on a shared asset). A speed-adjusted or
                // speed-RAMPED clip (spec §3.1) is also per-clip — a
                // time-stretched source cannot be shared with speed-1 clips
                // of the same asset (and a derived+sped clip stretches the
                // derived media). Otherwise the shared original. A ramp
                // wins over a constant playbackRate (legacy semantics).
                let clampedSpeed = min(max(clip.playbackRate, 0.25), 4.0)
                let ramped = clip.speedRampPoints.count >= 2
                let speedAdjusted = clampedSpeed != 1 && !ramped
                let sourceId: UUID
                if let effective = effectiveMediaFor(clip) {
                    sourceId = clip.id
                    if sources[sourceId] == nil {
                        sources[sourceId] = AudioGraphSource(
                            id: sourceId,
                            kind: .derived,
                            url: effective.url,
                            derivedFrom: asset.id,
                            algorithmVersion: effective.algorithmVersion,
                            nativeSampleRate: decodedSampleRateFor(sourceId)
                        )
                        sourceOrder.append(sourceId)
                    }
                    if derivedClipIds.contains(clip.id) == false {
                        derivedClipIds.append(clip.id)
                    }
                } else if speedAdjusted || ramped {
                    sourceId = clip.id
                    if sources[sourceId] == nil {
                        sources[sourceId] = AudioGraphSource(
                            id: sourceId,
                            kind: .original,
                            url: asset.originalURL,
                            nativeSampleRate: decodedSampleRateFor(sourceId)
                        )
                        sourceOrder.append(sourceId)
                    }
                } else {
                    sourceId = asset.id
                    if sources[sourceId] == nil {
                        sources[sourceId] = AudioGraphSource(
                            id: sourceId,
                            kind: .original,
                            url: asset.originalURL,
                            nativeSampleRate: decodedSampleRateFor(sourceId)
                        )
                        sourceOrder.append(sourceId)
                        if plainAssetIds.contains(asset.id) == false {
                            plainAssetIds.append(asset.id)
                        }
                    }
                }
                if speedAdjusted, speedAdjustedSources.contains(where: { $0.clipId == clip.id }) == false {
                    speedAdjustedSources.append(SpeedAdjustedSource(
                        clipId: clip.id, assetId: asset.id, speed: clampedSpeed
                    ))
                }
                if ramped, rampAdjustedSources.contains(where: { $0.clipId == clip.id }) == false {
                    rampAdjustedSources.append(RampAdjustedSource(
                        clipId: clip.id, assetId: asset.id, points: clip.speedRampPoints
                    ))
                }
                let nativeRate = decodedSampleRateFor(sourceId) ?? graphSampleRate
                let channels = channelCountFor(sourceId) ?? 2
                let mapping: AudioGraphChannelMapping = channels <= 1 ? .mono : .stereo

                let stripId = clip.id
                strips.append(AudioGraphClipStrip(
                    clipId: stripId,
                    sourceId: sourceId,
                    channelMapping: mapping,
                    gain: gainAutomation(
                        for: clip,
                        clipTimelineStart: clip.timelineRange.start,
                        samplePosition: samplePosition
                    ),
                    fades: fadeAutomation(for: clip, samplePosition: samplePosition),
                    pan: []
                ))
                trackStripIds.append(stripId)

                // Activation in the §3.1-normalized source's coordinates.
                // Constant-speed: the engines put a sped clip on the
                // timeline for sourceRange.duration / speed seconds
                // (scaleTimeRange), and the stretched source N satisfies
                // N(τ) = S(τ·speed), so source time `a` begins at
                // normalized offset a/speed. Ramp: the pre-render is the
                // clip's own source window warped by the curve, so the
                // activation reads from offset 0 at rate 1 over the clip's
                // (curve-mapped) timeline duration.
                let rangeStart = samplePosition(clip.timelineRange.start)
                let timelineDuration = speedAdjusted
                    ? clip.sourceRange.duration / clampedSpeed
                    : clip.timelineRange.duration
                let rangeEnd = samplePosition(clip.timelineRange.start + timelineDuration)
                let offsetSeconds: Double
                if speedAdjusted {
                    offsetSeconds = clip.sourceRange.start / clampedSpeed
                } else if ramped {
                    offsetSeconds = 0
                } else {
                    offsetSeconds = clip.sourceRange.start
                }
                activations[stripId] = AudioGraphStripActivation(
                    sampleRange: rangeStart..<max(rangeStart + 1, rangeEnd),
                    sourceFrameOffset: Int64((offsetSeconds * nativeRate).rounded(.down)),
                    playbackRate: nativeRate / graphSampleRate
                )
            }

            guard !trackStripIds.isEmpty else { continue }
            buses.append(AudioGraphTrackBus(
                trackId: track.id,
                inputStripIds: trackStripIds,
                mute: track.isMuted,
                solo: track.isSolo
            ))
        }

        // G-26 §6 serialization: expand the project's master processing
        // preset into the master bus — the chain's FULL parameters plus
        // the preset algorithm version and the limiter's latency
        // declaration (spec §4). The renderers consume these serialized
        // values; nil preset = the default, no-processing bus.
        var masterBus = AudioGraphMasterBus()
        if let preset = project.masterAudioProcessing {
            switch preset {
            case .sns:
                masterBus.masterChain = .sns
                masterBus.presetAlgorithmVersion = AudioGraphMasterChain.snsPresetAlgorithmVersion
                masterBus.limiter = AudioGraphMasterChain.snsLimiterLatency(sampleRate: graphSampleRate)
            }
        }

        let spec = AudioRenderGraphSpec(
            sources: sourceOrder.compactMap { sources[$0] },
            clipStrips: strips,
            trackBuses: buses,
            masterBus: masterBus,
            timebase: timebase
        )
        return Plan(
            spec: spec,
            activations: activations,
            sourceAssetIds: plainAssetIds,
            derivedClipIds: derivedClipIds,
            speedAdjustedSources: speedAdjustedSources,
            rampAdjustedSources: rampAdjustedSources
        )
    }

    // MARK: - Automation mappings

    /// Volume (linear) as one constant dB point, extended by ducking ramp
    /// points around every ducking range — the planner's attack/hold/release
    /// MATERIALIZED as ordinary gain automation in ABSOLUTE graph sample
    /// positions (spec §1.1: product ducking ranges are clip-local and are
    /// rebased by the clip's timeline start here).
    static func gainAutomation(
        for clip: Clip,
        clipTimelineStart: TimeInterval,
        samplePosition: (TimeInterval) -> Int64
    ) -> [AudioGraphAutomationPoint] {
        let baseDb = clip.volume > 0 ? 20 * log10(min(max(clip.volume, 0.0001), 2)) : silenceFloorDb
        var points = [AudioGraphAutomationPoint(samplePosition: 0, value: baseDb)]

        guard let duckingLevel = clip.duckingLevel,
              duckingLevel < 1,
              clip.duckingRanges.isEmpty == false else {
            return points
        }
        let duckedDb = baseDb + 20 * log10(max(duckingLevel, 0.0001))
        let attack = AudioDuckingPlanner.attackDuration
        let release = AudioDuckingPlanner.releaseDuration

        for range in AudioDuckingPlanner.mergeOverlapping(clip.duckingRanges) {
            // Clip-local bounds first; a range too short for both ramps
            // ducks nothing (the current product's behavior).
            let start = max(0, range.start)
            let end = min(range.end, clip.timelineRange.duration)
            guard end - start > attack + release else { continue }

            // Ramps INSIDE the range (spec §1.1 — the product's timing):
            // attack ramps down through [start, start+attack], hold, release
            // ramps back through [end−release, end].
            func absolute(_ local: TimeInterval) -> TimeInterval { clipTimelineStart + local }
            points.append(AudioGraphAutomationPoint(
                samplePosition: samplePosition(absolute(start)),
                value: baseDb
            ))
            points.append(AudioGraphAutomationPoint(
                samplePosition: samplePosition(absolute(start + attack)),
                value: duckedDb
            ))
            points.append(AudioGraphAutomationPoint(
                samplePosition: samplePosition(absolute(end - release)),
                value: duckedDb
            ))
            points.append(AudioGraphAutomationPoint(
                samplePosition: samplePosition(absolute(end)),
                value: baseDb
            ))
        }
        return points.sorted { $0.samplePosition < $1.samplePosition }
    }

    /// Fade in/out as linear amplitude fades in sample coordinates — the
    /// same shape the audioMix path's setVolumeRamp applies.
    static func fadeAutomation(
        for clip: Clip,
        samplePosition: (TimeInterval) -> Int64
    ) -> [AudioGraphFade] {
        var fades: [AudioGraphFade] = []
        let start = clip.timelineRange.start
        if clip.fadeInDuration > 0 {
            fades.append(AudioGraphFade(
                startSample: samplePosition(start),
                endSample: samplePosition(start + clip.fadeInDuration),
                curve: .linear
            ))
        }
        if clip.fadeOutDuration > 0 {
            let end = start + clip.timelineRange.duration
            fades.append(AudioGraphFade(
                startSample: samplePosition(end - clip.fadeOutDuration),
                endSample: samplePosition(end),
                curve: .linear,
                direction: .fadeOut
            ))
        }
        return fades
    }
}
