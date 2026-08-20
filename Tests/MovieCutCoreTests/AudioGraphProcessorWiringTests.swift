import Foundation
import Testing
@testable import MovieCutCore

/// G-26 Inc 4 — the graph's placeholder nodeKinds (.compressor, .limiter)
/// now map to real DSP: a graph declaring them RENDERS (no rejection),
/// and the master bus's limiter latency declaration is honored.
@Suite("Audio Graph Processor Wiring (G-26)")
struct AudioGraphProcessorWiringTests {
    @Test("compressor and limiter are now stage-supported")
    func nodeKindSupport() {
        #expect(AudioGraphNodeKind.compressor.isStage1Supported)
        #expect(AudioGraphNodeKind.limiter.isStage1Supported)
        // Unimplemented nodes still reject.
        #expect(AudioGraphNodeKind.eq.isStage1Supported == false)
        #expect(AudioGraphNodeKind.creativeFX.isStage1Supported == false)
    }

    @Test("a graph with a limiter declaration renders through the offline renderer")
    func graphWithLimiterRenders() throws {
        // Build a minimal graph: one strip + master bus with a limiter.
        let source = AudioGraphSource(
            id: UUID(),
            kind: .original,
            url: URL(fileURLWithPath: "/tmp/test.wav")
        )
        let strip = AudioGraphClipStrip(
            clipId: UUID(),
            sourceId: source.id,
            channelMapping: .stereo,
            gain: [AudioGraphAutomationPoint(samplePosition: 0, value: 0)]
        )
        let bus = AudioGraphTrackBus(
            trackId: UUID(),
            inputStripIds: [strip.clipId]
        )
        let masterBus = AudioGraphMasterBus(
            fader: [],
            limiter: AudioGraphNodeLatency(
                nodeKind: .limiter,
                algorithmVersion: "1.0.0",
                reportedLatencySamples: 0,
                lookAheadSamples: 240  // 5ms @ 48k
            )
        )
        let spec = AudioRenderGraphSpec(
            sources: [source],
            clipStrips: [strip],
            trackBuses: [bus],
            masterBus: masterBus
        )
        let activation = AudioGraphStripActivation(
            sampleRange: 0..<48_000,
            sourceFrameOffset: 0,
            playbackRate: 1
        )
        let audio = AudioGraphSourceAudio(
            sampleRate: 48_000,
            channels: 2,
            interleaved: (0..<48_000 * 2).map { Float(sin(Double($0 / 2) * 0.05) * 0.5) }
        )

        // Before G-26 Inc 4: this threw unsupportedNodeKind(.limiter).
        // Now: it renders (the limiter is wired into the master chain).
        let rendered = try AudioGraphOfflineRenderer.render(
            spec: spec,
            activations: [strip.clipId: activation],
            sourceAudio: { _ in audio },
            frameCount: 1000
        )
        #expect(rendered.frameCount == 1000)
        #expect(rendered.interleaved.contains { $0 != 0 })
    }

    @Test("the SNS master chain measurably limits the true peak on real audio")
    func snsChainLimitsTruePeak() {
        // A loud signal near 0 dBFS.
        let frames = 48_000
        var interleaved = [Float]()
        for sample in 0..<(frames * 2) {
            let frame = sample / 2
            interleaved.append(Float(sin(Double(frame) * 2 * .pi * 440 / 48_000) * 0.95))
        }
        let input = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: interleaved)

        let effect = AudioGraphMasterChain.measureChainEffect(input, chain: .sns)

        // The limiter holds the true peak at ≈ −1 dBTP.
        #expect(effect.outputTruePeakDb <= -0.5,
                "SNS chain must limit true peak; got \(effect.outputTruePeakDb) dBTP")
    }
}
