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
///   (mapping → gain/fades → pan → bus summing/fader → master).
public enum AudioGraphLatency {
    /// The single global compensation for a graph (spec §4): the pipeline is
    /// read advanced by `lookAheadSamples` and the output is realigned by
    /// `outputDelaySamples`. One global pair, never per-node compensation.
    public static func globalCompensation(
        _ declaredLatencies: [AudioGraphNodeLatency]?
    ) -> (lookAheadSamples: Int64, outputDelaySamples: Int64) {
        guard let declaredLatencies, !declaredLatencies.isEmpty else { return (0, 0) }
        let lookAhead = declaredLatencies.map(\.lookAheadSamples).max() ?? 0
        let totalDelay = declaredLatencies.map { $0.reportedLatencySamples + $0.lookAheadSamples }.max() ?? 0
        return (lookAhead, totalDelay)
    }

    /// The absolute pipeline window both engines render for a request of
    /// `frameCount` timeline frames starting at sample 0.
    public static func outputWindow(
        forFrameCount frameCount: Int,
        declaredLatencies: [AudioGraphNodeLatency]?
    ) -> Range<Int64> {
        let delay = globalCompensation(declaredLatencies).outputDelaySamples
        return delay ..< delay + Int64(frameCount)
    }
}

extension AudioGraphTimebase {
    /// Converts an absolute timeline instant to a graph-relative sample
    /// position. `origin` is the timeline instant represented by graph sample
    /// zero, so it MUST participate in both directions of the conversion.
    ///
    /// Integer division is mathematical floor for negative pre-origin times,
    /// keeping the sample index on the same side of the instant as positive
    /// times instead of Swift's default truncation-toward-zero asymmetry.
    public func samplePosition(at time: CMTime) -> Int64 {
        let rate = Int64(sampleRate)
        guard rate > 0,
              rate <= Int64(Int32.max),
              CMTIME_IS_NUMERIC(time),
              CMTIME_IS_NUMERIC(origin)
        else {
            return 0
        }

        let relative = CMTimeSubtract(time, origin)
        guard CMTIME_IS_NUMERIC(relative), relative.timescale > 0 else { return 0 }

        let (numerator, overflow) = relative.value.multipliedReportingOverflow(by: rate)
        guard !overflow else { return relative.value >= 0 ? Int64.max : Int64.min }
        let denominator = Int64(relative.timescale)
        let quotient = numerator / denominator
        let remainder = numerator % denominator
        if remainder != 0, numerator < 0 {
            return quotient - 1
        }
        return quotient
    }

    /// Inverse conversion — the absolute timeline instant a graph sample
    /// position corresponds to. The graph-relative sample time is offset by
    /// the serialized `origin`, making this the true inverse of
    /// `samplePosition(at:)` for exact sample instants.
    public func time(atSamplePosition position: Int64) -> CMTime {
        let rate = Int64(sampleRate)
        guard rate > 0,
              rate <= Int64(Int32.max),
              CMTIME_IS_NUMERIC(origin)
        else {
            return .zero
        }
        let relative = CMTime(value: position, timescale: Int32(rate))
        return CMTimeAdd(origin, relative)
    }
}

/// In-memory source audio for the offline renderer. Interleaved Float32
/// (`channels`-wide frames), any sample rate.
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
/// first graph sample reads. Timing lives here as runtime plan data.
public struct AudioGraphStripActivation: Sendable, Equatable {
    /// Active sample range in graph time [lowerBound, upperBound).
    public var sampleRange: Range<Int64>
    /// Source frame read at `sampleRange.lowerBound`.
    public var sourceFrameOffset: Int64
    /// Source playback rate (1 = native). Product sources are normalized by
    /// `AudioGraphSourceAdapter`; this remains useful for synthetic fixtures.
    public var playbackRate: Double

    public init(sampleRange: Range<Int64>, sourceFrameOffset: Int64 = 0, playbackRate: Double = 1) {
        self.sampleRange = sampleRange
        self.sourceFrameOffset = sourceFrameOffset
        self.playbackRate = playbackRate
    }
}

public enum AudioGraphRenderError: Error, Equatable, Sendable {
    case unsupportedNodeKind(AudioGraphNodeKind)
    case missingInput(what: String, id: UUID)
}

/// Sample-exact offline evaluation of an audio render graph. PURE: same
/// inputs → bit-identical output every run and on every host.
public enum AudioGraphOfflineRenderer {
    /// - Parameter frameRange: absolute graph-sample range to evaluate into
    ///   the returned buffer (buffer frame 0 = `frameRange.lowerBound`).
    ///   nil = `0..<frameCount`.
    public static func render(
        spec: AudioRenderGraphSpec,
        activations: [UUID: AudioGraphStripActivation],
        sourceAudio: (UUID) -> AudioGraphSourceAudio?,
        frameCount: Int,
        frameRange: Range<Int64>? = nil
    ) throws -> AudioGraphSourceAudio {
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
                    let outputIndex = Int(frame - absoluteRange.lowerBound) * 2
                    guard outputIndex >= 0, outputIndex + 1 < out.count else { continue }
                    out[outputIndex] += left
                    out[outputIndex + 1] += right
                }
            }
        }

        let mixed = AudioGraphSourceAudio(
            sampleRate: spec.timebase.sampleRate,
            channels: 2,
            interleaved: out
        )
        if let chain = spec.masterBus.resolvedMasterChain() {
            return AudioGraphMasterChain.apply(mixed, chain: chain)
        }
        return mixed
    }

    // MARK: - Evaluation math (pure, shared semantics)

    /// ONE strip's stereo contribution to the master mix at an absolute graph
    /// sample position.
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

    /// Piecewise-linear automation evaluation at an exact sample position;
    /// constant before the first and after the last point.
    static func automationValue(_ points: [AudioGraphAutomationPoint], at position: Int64) -> Double {
        guard !points.isEmpty else { return 0 }
        let sorted = points.sorted { $0.samplePosition < $1.samplePosition }
        guard position > sorted.first!.samplePosition, position < sorted.last!.samplePosition else {
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

    /// Equal-power pan gains.
    static func panGains(_ pan: Double) -> (left: Double, right: Double) {
        let clamped = min(max(pan, -1), 1)
        let theta = (clamped + 1) * .pi / 4
        return (cos(theta), sin(theta))
    }

    /// Product of every fade covering the position. A `.fadeIn` ramps
    /// 0→1, a `.fadeOut` ramps 1→0.
    static func fadeFactor(_ fades: [AudioGraphFade], at position: Int64) -> Double {
        var factor = 1.0
        for fade in fades {
            guard position >= fade.startSample, position <= fade.endSample else { continue }
            let span = fade.endSample - fade.startSample
            guard span > 0 else { continue }
            let t = Double(position - fade.startSample) / Double(span)
            let gain: Double
            switch (fade.curve, fade.direction) {
            case (.linear, .fadeIn):
                gain = t
            case (.linear, .fadeOut):
                gain = 1 - t
            case (.exponential, .fadeIn):
                gain = t * t
            case (.exponential, .fadeOut):
                gain = (1 - t) * (1 - t)
            }
            factor *= gain
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
                audio.sample(frame: frame, channel: min(1, audio.channels - 1))
            )
        }
    }
}
