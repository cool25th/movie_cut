import CoreMedia
import Foundation

/// G-25 Inc 8 (Core half): the pure engine math shared by the preview and
/// export generators (docs/AUDIO_RENDER_GRAPH_SPEC_20260817.md §4·§9).
///
/// - `AudioGraphLatency` — the ONE global look-ahead compensation both
///   engines must compute from the same `declaredLatencies` (spec rule ②).
/// - `AudioGraphTimebase` conversions — exact Int64 sample-position math
///   (spec rule ①; the 60-minute mixed-rate drift gate is built on it).
/// - `AudioGraphOfflineRenderer` — sample-exact graph evaluation
///   (mapping → gain/fades → pan → bus summing/fader → master). The
///   App-side preview (AVAudioEngine) and export (encoder input) wiring on
///   top of this math, plus the E2E null test, are the Inc 8 App half.
public enum AudioGraphLatency {
    /// The single global compensation for a graph (spec §4): the pipeline is
    /// read advanced by `lookAheadSamples` (the maximum look-ahead any node
    /// declares) and the output is realigned by `outputDelaySamples` (the
    /// maximum total delay: reported latency + look-ahead). One global pair,
    /// never per-node compensation — both engines must call THIS function so
    /// preview and export always agree. Stage-1 graphs yield (0, 0).
    public static func globalCompensation(
        _ declaredLatencies: [AudioGraphNodeLatency]?
    ) -> (lookAheadSamples: Int64, outputDelaySamples: Int64) {
        guard let declaredLatencies, !declaredLatencies.isEmpty else { return (0, 0) }
        let lookAhead = declaredLatencies.map(\.lookAheadSamples).max() ?? 0
        let totalDelay = declaredLatencies.map { $0.reportedLatencySamples + $0.lookAheadSamples }.max() ?? 0
        return (lookAhead, totalDelay)
    }

    /// The absolute pipeline window both engines must render for a request of
    /// `frameCount` timeline frames starting at timeline sample 0: the final
    /// output for timeline frame f is pipeline frame f + outputDelaySamples
    /// (the maximum total delay). The two engine generators derive their
    /// window from THIS function — never from their own math — so preview and
    /// export compensate identically (spec rule ②). Stage-1 graphs yield
    /// 0..<frameCount (identity).
    public static func outputWindow(
        forFrameCount frameCount: Int,
        declaredLatencies: [AudioGraphNodeLatency]?
    ) -> Range<Int64> {
        let delay = globalCompensation(declaredLatencies).outputDelaySamples
        return delay ..< delay + Int64(frameCount)
    }
}

extension AudioGraphTimebase {
    /// Exact Int64 conversion: sample position = time.value * sampleRate /
    /// time.timescale, computed so the result is identical in both engines.
    /// Floor rounding — a sample position is the sample INDEX at/after the
    /// instant, never a fractional float.
    public func samplePosition(at time: CMTime) -> Int64 {
        guard time.timescale > 0, time.value != 0 else { return 0 }
        let rate = Int64(sampleRate)
        // value * rate first (exact while it fits Int64 — 60min@600 ≈ 1e13,
        // far from overflow), then divide with floor toward zero.
        return (time.value * rate) / Int64(time.timescale)
    }

    /// Inverse conversion — the CMTime a sample position corresponds to.
    /// Uses the sample rate itself as the timescale, so integer-rate
    /// timebases round-trip EXACTLY (position p ↔ CMTime(p / rate)).
    public func time(atSamplePosition position: Int64) -> CMTime {
        let rate = Int64(sampleRate)
        guard rate > 0, rate <= Int64(Int32.max) else { return .zero }
        return CMTime(value: position, timescale: Int32(rate))
    }
}

/// In-memory source audio for the offline renderer. Interleaved Float32
/// (`channels`-wide frames), any sample rate — the renderer resamples by
/// NEAREST FRAME ONLY for non-integer frame ratios and asserts nothing:
/// resampling policy belongs to the engine generators, which are told the
/// ratio via `playbackRate` below.
public struct AudioGraphSourceAudio: Sendable, Equatable {
    public var sampleRate: Double
    public var channels: Int
    public var interleaved: [Float]

    public init(sampleRate: Double, channels: Int, interleaved: [Float]) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.interleaved = interleaved
    }

    public var frameCount: Int { channels > 0 ? interleaved.count / channels : 0 }

    public func sample(frame: Int, channel: Int) -> Float {
        guard frame >= 0, frame < frameCount, channel >= 0, channel < channels else { return 0 }
        return interleaved[frame * channels + channel]
    }
}

/// When a strip is active in graph sample time, and which source frame its
/// first graph sample reads. Timing lives HERE (runtime plan data), not in
/// the serialized spec — the approved schema carries no timeline ranges.
public struct AudioGraphStripActivation: Sendable, Equatable {
    /// Active sample range in graph time [lowerBound, upperBound).
    public var sampleRange: Range<Int64>
    /// Source frame read at `sampleRange.lowerBound`.
    public var sourceFrameOffset: Int64
    /// Source playback rate (1 = native). Non-integer-ratio resampling is
    /// nearest-frame in stage 1; the engines may pre-resample instead.
    public var playbackRate: Double

    public init(sampleRange: Range<Int64>, sourceFrameOffset: Int64 = 0, playbackRate: Double = 1) {
        self.sampleRange = sampleRange
        self.sourceFrameOffset = sourceFrameOffset
        self.playbackRate = playbackRate
    }
}

public enum AudioGraphRenderError: Error, Equatable, Sendable {
    /// The graph contains a node kind this engine does not implement —
    /// explicit rejection, never silent degradation (spec §5).
    case unsupportedNodeKind(AudioGraphNodeKind)
    /// A strip references a source or activation the renderer was not given.
    case missingInput(what: String, id: UUID)
}

/// Sample-exact offline evaluation of an audio render graph. PURE: same
/// inputs → bit-identical output every run and on every host — this is the
/// property the preview↔export null test (spec §9) leans on.
///
/// Stage-1 semantics (documented where the spec leaves the math open):
/// - Automation: piecewise LINEAR between adjacent points; constant before
///   the first / after the last point. Values are dB for gain/fader and
///   -1…1 for pan, evaluated at exact integer sample positions.
/// - Fades: multiply the strip signal; linear curve is a straight amplitude
///   ramp, exponential is the standard squared ramp (1-t)².
/// - Pan: no pan points bypass the node at unity; with points, equal-power
///   law, pan ∈ [-1, 1] → gains (cos θ, sin θ), θ = (pan + 1) · π/4
///   (center = -3 dB on each side).
/// - Channel mapping to the stereo bus: .mono → the mono channel feeds both
///   L and R; .stereo → L and R pass through; .dualMono → mono duplicated
///   to L and R (electrically identical to .mono, distinct as metadata).
/// - Buses: any soloed bus silences non-solo buses; mute silences the bus;
///   bus fader automation is gain in dB. Ducking (sidechain-timed) has no
///   input data in a pure render and is therefore identity here — the node
///   stays in the graph for the engines, which own the sidechain wiring.
public enum AudioGraphOfflineRenderer {
    /// - Parameter frameRange: absolute graph-sample range to evaluate into
    ///   the returned buffer (buffer frame 0 = `frameRange.lowerBound`).
    ///   nil = `0..<frameCount`. The ENGINE GENERATORS pass the latency
    ///   output window here; direct callers get the uncompensated origin.
    public static func render(
        spec: AudioRenderGraphSpec,
        activations: [UUID: AudioGraphStripActivation],
        sourceAudio: (UUID) -> AudioGraphSourceAudio?,
        frameCount: Int,
        frameRange: Range<Int64>? = nil
    ) throws -> AudioGraphSourceAudio {
        // Spec §5: a stage-1 engine must reject graphs that use nodes it
        // cannot implement. The limiter is the only placeholder node with a
        // serialized slot; presence means the master chain needs one.
        if let limiter = spec.masterBus.limiter {
            throw AudioGraphRenderError.unsupportedNodeKind(limiter.nodeKind)
        }

        let absoluteRange = frameRange ?? 0 ..< Int64(frameCount)
        var out = [Float](repeating: 0, count: frameCount * 2)
        let soloedBuses = spec.trackBuses.contains { $0.solo }

        for bus in spec.trackBuses {
            if bus.mute || (soloedBuses && !bus.solo) { continue }
            for stripId in bus.inputStripIds {
                guard let strip = spec.clipStrips.first(where: { $0.clipId == stripId }) else {
                    throw AudioGraphRenderError.missingInput(what: "clipStrip", id: stripId)
                }
                guard let activation = activations[stripId] else {
                    throw AudioGraphRenderError.missingInput(what: "activation", id: stripId)
                }
                guard let source = spec.sources.first(where: { $0.id == strip.sourceId }) else {
                    throw AudioGraphRenderError.missingInput(what: "source", id: strip.sourceId)
                }
                guard let audio = sourceAudio(source.id) else {
                    throw AudioGraphRenderError.missingInput(what: "sourceAudio", id: source.id)
                }

                let start = max(absoluteRange.lowerBound, activation.sampleRange.lowerBound)
                let end = min(absoluteRange.upperBound, activation.sampleRange.upperBound)
                guard end > start else { continue }

                for frame in start..<end {
                    let (left, right) = stripFrame(
                        strip: strip,
                        bus: bus,
                        anyBusSoloed: soloedBuses,
                        masterFader: spec.masterBus.fader,
                        audio: audio,
                        activation: activation,
                        at: frame
                    )
                    let l = Int(frame - absoluteRange.lowerBound) * 2
                    out[l] += left
                    out[l + 1] += right
                }
            }
        }

        return AudioGraphSourceAudio(sampleRate: spec.timebase.sampleRate, channels: 2, interleaved: out)
    }

    // MARK: - Evaluation math (pure, shared semantics)

    /// ONE strip's stereo contribution to the master mix at an absolute graph
    /// sample position — the full per-strip chain (channel mapping →
    /// gain/fades → pan → bus fader/mute/solo → master fader) with the exact
    /// multiplication order both engine generators must reproduce. The
    /// offline renderer accumulates it directly; the AVAudioEngine generator
    /// precomputes each strip's window from it and lets the ENGINE own
    /// scheduling and summing — shared math is what makes the preview↔export
    /// null test (spec §9) a plumbing check rather than a semantics check.
    static func stripFrame(
        strip: AudioGraphClipStrip,
        bus: AudioGraphTrackBus,
        anyBusSoloed: Bool,
        masterFader: [AudioGraphAutomationPoint],
        audio: AudioGraphSourceAudio,
        activation: AudioGraphStripActivation,
        at frame: Int64
    ) -> (left: Float, right: Float) {
        if bus.mute || (anyBusSoloed && !bus.solo) { return (0, 0) }
        guard frame >= activation.sampleRange.lowerBound,
              frame < activation.sampleRange.upperBound else { return (0, 0) }

        let offset = frame - activation.sampleRange.lowerBound
        let sourceFrame = Int((Double(offset) * activation.playbackRate).rounded(.down))
            + Int(activation.sourceFrameOffset)
        let (left, right) = mappedChannels(strip: strip, audio: audio, frame: sourceFrame)

        let gain = linearGain(
            value: automationValue(strip.gain, at: frame),
            fallbackDb: 0
        )
        let fade = fadeFactor(strip.fades, at: frame)
        // No pan points → the pan node is bypassed (unity).
        // With points, the held/evaluated value maps through the
        // equal-power law (0 = center = -3 dB on both).
        let (panL, panR) = strip.pan.isEmpty
            ? (1.0, 1.0)
            : panGains(automationValue(strip.pan, at: frame))
        let busGain = linearGain(
            value: automationValue(bus.fader, at: frame),
            fallbackDb: 0
        )
        let masterGain = linearGain(
            value: automationValue(masterFader, at: frame),
            fallbackDb: 0
        )
        let total = Float(gain * fade * busGain * masterGain)
        return (left * total * Float(panL), right * total * Float(panR))
    }

    /// Piecewise-linear automation evaluation in dB (or pan) at an exact
    /// sample position; constant outside the point range.
    static func automationValue(_ points: [AudioGraphAutomationPoint], at position: Int64) -> Double {
        guard !points.isEmpty else { return 0 }
        let sorted = points.sorted { $0.samplePosition < $1.samplePosition }
        guard position > sorted.first!.samplePosition, position < sorted.last!.samplePosition else {
            // At/before the first point and at/after the last: hold.
            if position <= sorted.first!.samplePosition { return sorted.first!.value }
            return sorted.last!.value
        }
        var lower = sorted[0]
        var upper = sorted[sorted.count - 1]
        for window in zip(sorted, sorted.dropFirst()) {
            if window.0.samplePosition <= position, position <= window.1.samplePosition {
                lower = window.0
                upper = window.1
                break
            }
        }
        let span = upper.samplePosition - lower.samplePosition
        guard span > 0 else { return upper.value }
        let t = Double(position - lower.samplePosition) / Double(span)
        return lower.value + (upper.value - lower.value) * t
    }

    /// dB → linear amplitude.
    static func linearGain(value: Double, fallbackDb: Double) -> Double {
        let db = value.isFinite ? value : fallbackDb
        return pow(10, db / 20)
    }

    /// Equal-power pan gains (spec-silent choice, documented above).
    static func panGains(_ pan: Double) -> (left: Double, right: Double) {
        let clamped = min(max(pan, -1), 1)
        let theta = (clamped + 1) * .pi / 4
        return (cos(theta), sin(theta))
    }

    /// Product of every fade covering the position.
    static func fadeFactor(_ fades: [AudioGraphFade], at position: Int64) -> Double {
        var factor = 1.0
        for fade in fades {
            guard position >= fade.startSample, position <= fade.endSample else { continue }
            let span = fade.endSample - fade.startSample
            guard span > 0 else { continue }
            let t = Double(position - fade.startSample) / Double(span)
            switch fade.curve {
            case .linear:
                factor *= t
            case .exponential:
                factor *= (1 - t) * (1 - t)
            }
        }
        return factor
    }

    /// Source channels → stereo pair per the strip's channel mapping.
    static func mappedChannels(
        strip: AudioGraphClipStrip,
        audio: AudioGraphSourceAudio,
        frame: Int
    ) -> (left: Float, right: Float) {
        switch strip.channelMapping {
        case .mono, .dualMono:
            let mono = audio.sample(frame: frame, channel: 0)
            return (mono, mono)
        case .stereo:
            return (
                audio.sample(frame: frame, channel: 0),
                audio.sample(frame: min(audio.channels - 1, 1), channel: 1)
            )
        }
    }
}
