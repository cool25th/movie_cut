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
        var strips: [AudioGraphClipStrip] = []
        var activations: [UUID: AudioGraphStripActivation] = [:]
        var buses: [AudioGraphTrackBus] = []
        var derivedClipIds: [UUID] = []

        func samplePosition(_ seconds: TimeInterval) -> Int64 {
            timebase.samplePosition(at: CMTime(seconds: seconds, preferredTimescale: 600))
        }

        for track in renderTracks.sorted(by: { $0.zIndex < $1.zIndex }) {
            var trackStripIds: [UUID] = []
            for clip in track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                guard let assetId = clip.assetId,
                      let asset = project.mediaLibrary.assets[assetId] else { continue }
                // Audio tracks carry audio clips; video tracks contribute
                // their clips' embedded audio (images/text have none).
                let carriesAudio = track.kind == .audio ? (clip.kind == .audio || clip.kind == .video)
                    : (asset.kind == .audio || asset.kind == .video)
                guard carriesAudio, clip.timelineRange.duration > 0 else { continue }

                // Effective media (spec §0 v1.1): an EQ/NR derivation is the
                // clip's own source (per-clip, since EQ settings are
                // per-clip even on a shared asset); otherwise the original.
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
                    }
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

                let rangeStart = samplePosition(clip.timelineRange.start)
                let rangeEnd = samplePosition(clip.timelineRange.start + clip.timelineRange.duration)
                activations[stripId] = AudioGraphStripActivation(
                    sampleRange: rangeStart..<max(rangeStart + 1, rangeEnd),
                    sourceFrameOffset: Int64((clip.sourceRange.start * nativeRate).rounded(.down)),
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

        let spec = AudioRenderGraphSpec(
            sources: sourceOrder.compactMap { sources[$0] },
            clipStrips: strips,
            trackBuses: buses,
            timebase: timebase
        )
        return Plan(
            spec: spec,
            activations: activations,
            sourceAssetIds: sourceOrder.filter { sources[$0]?.kind == .original },
            derivedClipIds: derivedClipIds
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
                curve: .linear
            ))
        }
        return fades
    }
}
