import CoreMedia
import Foundation
import Testing
@testable import MovieCutCore

/// G-25 Inc 8 (Core half) — latency compensation, exact timebase math, and
/// sample-exact offline rendering (spec §3·§4·§9 groundwork).
@Suite("AudioGraphRendering (G-25 Inc 8 Core)")
struct AudioGraphRenderingTests {
    // MARK: - Latency compensation (§4)

    @Test("stage-1 graphs have zero global compensation")
    func zeroLatencyForStage1() {
        #expect(AudioGraphLatency.globalCompensation(nil) == (0, 0))
        #expect(AudioGraphLatency.globalCompensation([]) == (0, 0))
    }

    @Test("global compensation is the single maximum, not a sum")
    func compensationTakesMaxima() {
        let declared: [AudioGraphNodeLatency] = [
            AudioGraphNodeLatency(nodeKind: .eq, algorithmVersion: "1.0.0", reportedLatencySamples: 32, lookAheadSamples: 0),
            AudioGraphNodeLatency(nodeKind: .compressor, algorithmVersion: "1.0.0", reportedLatencySamples: 5, lookAheadSamples: 64),
            AudioGraphNodeLatency(nodeKind: .limiter, algorithmVersion: "0.9.0", reportedLatencySamples: 8, lookAheadSamples: 16)
        ]
        let compensation = AudioGraphLatency.globalCompensation(declared)
        #expect(compensation.lookAheadSamples == 64)   // max look-ahead
        #expect(compensation.outputDelaySamples == 69) // max(reported + look-ahead)
    }

    // MARK: - Timebase conversions (§3, §9.4 drift gate)

    @Test("60 minutes converts to an exact sample position at 48 kHz")
    func sixtyMinutePositionIsExact() {
        let timebase = AudioGraphTimebase(sampleRate: 48_000, origin: .zero)
        let oneHour = CMTime(value: 3600, timescale: 1)
        #expect(timebase.samplePosition(at: oneHour) == 172_800_000)

        // The drift gate compares END positions across mixed rates; the
        // positions themselves are exact integers by construction.
        let cmos = AudioGraphTimebase(sampleRate: 44_100, origin: .zero)
        #expect(cmos.samplePosition(at: oneHour) == 158_760_000)
    }

    @Test("sample position and time round-trip without drift")
    func timebaseRoundTrip() {
        let timebase = AudioGraphTimebase(sampleRate: 48_000, origin: .zero)
        for value in [Int64(0), 1, 47_999, 48_000, 172_800_000] {
            let back = timebase.time(atSamplePosition: value)
            let again = timebase.samplePosition(at: back)
            #expect(abs(again - value) <= 1, "position \(value) drifted to \(again)")
        }
    }

    // MARK: - Offline rendering

    private func monoGraph(
        gain: [AudioGraphAutomationPoint] = [],
        fades: [AudioGraphFade] = [],
        pan: [AudioGraphAutomationPoint] = [],
        mapping: AudioGraphChannelMapping = .mono,
        bus configure: (inout AudioGraphTrackBus) -> Void = { _ in }
    ) -> (spec: AudioRenderGraphSpec, sourceId: UUID, stripId: UUID) {
        let sourceId = UUID()
        let stripId = UUID()
        var bus = AudioGraphTrackBus(trackId: UUID(), inputStripIds: [stripId])
        configure(&bus)
        let spec = AudioRenderGraphSpec(
            sources: [AudioGraphSource(id: sourceId, kind: .original, url: URL(filePath: "/tmp/a.wav"))],
            clipStrips: [AudioGraphClipStrip(
                clipId: stripId, sourceId: sourceId, channelMapping: mapping,
                gain: gain, fades: fades, pan: pan
            )],
            trackBuses: [bus]
        )
        return (spec, sourceId, stripId)
    }

    private func dcSource(level: Float, frames: Int, channels: Int = 1, sampleRate: Double = 48_000) -> AudioGraphSourceAudio {
        AudioGraphSourceAudio(
            sampleRate: sampleRate,
            channels: channels,
            interleaved: [Float](repeating: level, count: frames * channels)
        )
    }

    @Test("mono DC source passes through to both channels at unity")
    func unityPassThrough() throws {
        let (spec, sourceId, stripId) = monoGraph()
        let rendered = try AudioGraphOfflineRenderer.render(
            spec: spec,
            activations: [stripId: AudioGraphStripActivation(sampleRange: 0..<8)],
            sourceAudio: { id in id == sourceId ? dcSource(level: 0.5, frames: 8) : nil },
            frameCount: 8
        )
        #expect(rendered.channels == 2)
        #expect(rendered.interleaved == [Float](repeating: 0.5, count: 16))
    }

    @Test("constant -6 dB gain automation halves the signal")
    func constantGain() throws {
        let (spec, sourceId, stripId) = monoGraph(
            gain: [AudioGraphAutomationPoint(samplePosition: 0, value: -6)]
        )
        let rendered = try AudioGraphOfflineRenderer.render(
            spec: spec,
            activations: [stripId: AudioGraphStripActivation(sampleRange: 0..<4)],
            sourceAudio: { id in id == sourceId ? dcSource(level: 1, frames: 4) : nil },
            frameCount: 4
        )
        let expected = Float(pow(10, -6.0 / 20))
        for sample in rendered.interleaved {
            #expect(abs(sample - expected) < 1e-6)
        }
    }

    @Test("linear fade ramps from silence to unity")
    func linearFade() throws {
        let (spec, sourceId, stripId) = monoGraph(fades: [AudioGraphFade(startSample: 0, endSample: 4)])
        let rendered = try AudioGraphOfflineRenderer.render(
            spec: spec,
            activations: [stripId: AudioGraphStripActivation(sampleRange: 0..<4)],
            sourceAudio: { id in id == sourceId ? dcSource(level: 1, frames: 4) : nil },
            frameCount: 4
        )
        let left = stride(from: 0, to: 8, by: 2).map { rendered.interleaved[$0] }
        #expect(abs(left[0] - 0.0) < 1e-6)
        #expect(abs(left[1] - 0.25) < 1e-6)
        #expect(abs(left[2] - 0.5) < 1e-6)
        #expect(abs(left[3] - 0.75) < 1e-6)
    }

    @Test("hard-left pan silences the right channel (equal power)")
    func hardLeftPan() throws {
        let (spec, sourceId, stripId) = monoGraph(
            pan: [AudioGraphAutomationPoint(samplePosition: 0, value: -1)]
        )
        let rendered = try AudioGraphOfflineRenderer.render(
            spec: spec,
            activations: [stripId: AudioGraphStripActivation(sampleRange: 0..<4)],
            sourceAudio: { id in id == sourceId ? dcSource(level: 1, frames: 4) : nil },
            frameCount: 4
        )
        for f in 0..<4 {
            #expect(rendered.interleaved[f * 2] > 0.99)
            #expect(rendered.interleaved[f * 2 + 1] < 0.01)
        }
    }

    @Test("center pan keeps both channels at -3 dB (equal power)")
    func centerPan() throws {
        // Explicit pan point at 0 — WITHOUT points the pan node is bypassed
        // at unity, so the equal-power center must be requested.
        let (spec, sourceId, stripId) = monoGraph(
            pan: [AudioGraphAutomationPoint(samplePosition: 0, value: 0)]
        )
        let rendered = try AudioGraphOfflineRenderer.render(
            spec: spec,
            activations: [stripId: AudioGraphStripActivation(sampleRange: 0..<2)],
            sourceAudio: { id in id == sourceId ? dcSource(level: 1, frames: 2) : nil },
            frameCount: 2
        )
        // cos(π/4) = sin(π/4) = √2/2 ≈ 0.7071
        for sample in rendered.interleaved {
            #expect(abs(sample - 0.7071067811865476) < 1e-6)
        }
    }

    @Test("mute silences the bus; solo routes around mute semantics")
    func muteAndSolo() throws {
        let muted = monoGraph(bus: { $0.mute = true })
        let mutedRender = try AudioGraphOfflineRenderer.render(
            spec: muted.spec,
            activations: [muted.stripId: AudioGraphStripActivation(sampleRange: 0..<2)],
            sourceAudio: { id in id == muted.sourceId ? dcSource(level: 1, frames: 2) : nil },
            frameCount: 2
        )
        #expect(mutedRender.interleaved == [Float](repeating: 0, count: 4))
    }

    @Test("a limiter in the master chain is rejected, not skipped (§5)")
    func limiterRejected() throws {
        let graph = monoGraph()
        var spec = graph.spec
        spec.masterBus.limiter = AudioGraphNodeLatency(
            nodeKind: .limiter, algorithmVersion: "0.9.0", reportedLatencySamples: 4
        )
        #expect(throws: AudioGraphRenderError.unsupportedNodeKind(.limiter)) {
            _ = try AudioGraphOfflineRenderer.render(
                spec: spec,
                activations: [graph.stripId: AudioGraphStripActivation(sampleRange: 0..<1)],
                sourceAudio: { _ in nil },
                frameCount: 1
            )
        }
    }

    @Test("missing activation for a bus input is an explicit error")
    func missingActivationThrows() throws {
        let graph = monoGraph()
        #expect(throws: AudioGraphRenderError.self) {
            _ = try AudioGraphOfflineRenderer.render(
                spec: graph.spec,
                activations: [:],
                sourceAudio: { _ in nil },
                frameCount: 1
            )
        }
    }

    @Test("rendering is deterministic: same graph, bit-identical PCM")
    func deterministicRender() throws {
        let graph = monoGraph(
            gain: [AudioGraphAutomationPoint(samplePosition: 0, value: -3),
                   AudioGraphAutomationPoint(samplePosition: 8, value: 0)],
            fades: [AudioGraphFade(startSample: 0, endSample: 4)],
            pan: [AudioGraphAutomationPoint(samplePosition: 0, value: 0.3)]
        )
        func run() throws -> [Float] {
            try AudioGraphOfflineRenderer.render(
                spec: graph.spec,
                activations: [graph.stripId: AudioGraphStripActivation(sampleRange: 0..<16)],
                sourceAudio: { id in id == graph.sourceId ? dcSource(level: 0.8, frames: 16) : nil },
                frameCount: 16
            ).interleaved
        }
        #expect(try run() == run())
    }

    @Test("stereo mapping keeps left and right distinct")
    func stereoMapping() throws {
        let sourceId = UUID()
        let stripId = UUID()
        let spec = AudioRenderGraphSpec(
            sources: [AudioGraphSource(id: sourceId, kind: .original, url: URL(filePath: "/tmp/s.wav"))],
            clipStrips: [AudioGraphClipStrip(clipId: stripId, sourceId: sourceId, channelMapping: .stereo)],
            trackBuses: [AudioGraphTrackBus(trackId: UUID(), inputStripIds: [stripId])]
        )
        // L = 0.2 constant, R = 0.6 constant.
        var interleaved = [Float]()
        for _ in 0..<4 { interleaved.append(contentsOf: [0.2, 0.6]) }
        let rendered = try AudioGraphOfflineRenderer.render(
            spec: spec,
            activations: [stripId: AudioGraphStripActivation(sampleRange: 0..<4)],
            sourceAudio: { id in
                id == sourceId ? AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: interleaved) : nil
            },
            frameCount: 4
        )
        for f in 0..<4 {
            #expect(abs(rendered.interleaved[f * 2] - 0.2) < 1e-6)
            #expect(abs(rendered.interleaved[f * 2 + 1] - 0.6) < 1e-6)
        }
    }
}
