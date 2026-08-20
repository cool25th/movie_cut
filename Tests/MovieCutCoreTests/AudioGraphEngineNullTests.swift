import CoreMedia
import Foundation
import Testing
@testable import MovieCutCore

/// G-25 Inc 8 (App half) — the two ENGINE GENERATORS (spec §9): the preview
/// side renders through a real AVAudioEngine (offline manual rendering), the
/// export side is the encoder input. These swift-test checks verify the
/// plumbing agreement at ±1 sample / 1 LSB on deterministic synthetic graphs;
/// the MEASURED judgment on the real app path is the E2E gate
/// (`scripts/run_g25_nulltest.sh`, spec §9.5).
@Suite("AudioGraphEngines (G-25 Inc 8 App)")
struct AudioGraphEngineNullTests {
    // MARK: - Latency output window (rule ②)

    @Test("output window is identity for stage-1 graphs, shifted by the max total delay otherwise")
    func outputWindowMath() {
        #expect(AudioGraphLatency.outputWindow(forFrameCount: 100, declaredLatencies: nil) == 0..<100)
        #expect(AudioGraphLatency.outputWindow(forFrameCount: 100, declaredLatencies: []) == 0..<100)
        let declared = [
            AudioGraphNodeLatency(nodeKind: .eq, algorithmVersion: "1.0.0", reportedLatencySamples: 32),
            AudioGraphNodeLatency(nodeKind: .compressor, algorithmVersion: "1.0.0", reportedLatencySamples: 5, lookAheadSamples: 64)
        ]
        // max(reported + look-ahead) = 69, so timeline frame 0 is pipeline frame 69.
        #expect(AudioGraphLatency.outputWindow(forFrameCount: 100, declaredLatencies: declared) == 69..<169)
    }

    // MARK: - Shared fixtures

    private func twoBusGraph(
        busA configureA: (inout AudioGraphTrackBus, inout AudioGraphClipStrip) -> Void = { _, _ in },
        busB configureB: (inout AudioGraphTrackBus, inout AudioGraphClipStrip) -> Void = { _, _ in }
    ) -> (spec: AudioRenderGraphSpec, sourceA: UUID, stripA: UUID, sourceB: UUID, stripB: UUID) {
        let sourceA = UUID(), stripA = UUID(), sourceB = UUID(), stripB = UUID()
        var busA = AudioGraphTrackBus(trackId: UUID(), inputStripIds: [stripA])
        var stripAm = AudioGraphClipStrip(clipId: stripA, sourceId: sourceA, channelMapping: .mono)
        configureA(&busA, &stripAm)
        var busB = AudioGraphTrackBus(trackId: UUID(), inputStripIds: [stripB])
        var stripBm = AudioGraphClipStrip(clipId: stripB, sourceId: sourceB, channelMapping: .stereo)
        configureB(&busB, &stripBm)
        let spec = AudioRenderGraphSpec(
            sources: [
                AudioGraphSource(id: sourceA, kind: .original, url: URL(filePath: "/tmp/a.wav")),
                AudioGraphSource(id: sourceB, kind: .original, url: URL(filePath: "/tmp/b.wav"))
            ],
            clipStrips: [stripAm, stripBm],
            trackBuses: [busA, busB]
        )
        return (spec, sourceA, stripA, sourceB, stripB)
    }

    /// Deterministic non-trivial source: a mix of sines so channel flips,
    /// off-by-one reads, and gain errors all produce deviations ≫ 1 LSB.
    private func sineSource(
        frames: Int,
        channels: Int,
        sampleRate: Double,
        seed: Double
    ) -> AudioGraphSourceAudio {
        var samples = [Float]()
        samples.reserveCapacity(frames * channels)
        for frame in 0..<frames {
            let t = Double(frame)
            for channel in 0..<channels {
                let f = seed + Double(channel) * 110
                samples.append(Float(sin(t * f * 2 * .pi / sampleRate) * 0.8))
            }
        }
        return AudioGraphSourceAudio(sampleRate: sampleRate, channels: channels, interleaved: samples)
    }

    private func nullCompare(
        spec: AudioRenderGraphSpec,
        activations: [UUID: AudioGraphStripActivation],
        sources: [UUID: AudioGraphSourceAudio],
        frameCount: Int,
        frameRange: Range<Int64>? = nil
    ) throws {
        let preview = try AudioGraphAVAudioEngineRenderer.render(
            spec: spec, activations: activations,
            sourceAudio: { sources[$0] }, frameCount: frameCount, frameRange: frameRange
        )
        let export = try AudioGraphEncoderInput.render(
            spec: spec, activations: activations,
            sourceAudio: { sources[$0] }, frameCount: frameCount, frameRange: frameRange
        )
        let result = AudioGraphNullTest.compare(reference: export.interleaved, candidate: preview.interleaved)
        #expect(
            result.passed && result.bestOffsetSamples == 0,
            "engines disagree: offset=\(result.bestOffsetSamples) maxDev=\(result.maxAbsoluteDeviation) lsb=\(result.lsb16)"
        )
    }

    // MARK: - Null test: one graph, two engines (spec §9.1-9.3)

    @Test("unity mono + stereo summing agrees across the two engines")
    func unityAcrossEngines() throws {
        let (spec, sourceA, stripA, sourceB, stripB) = twoBusGraph()
        try nullCompare(
            spec: spec,
            activations: [
                stripA: AudioGraphStripActivation(sampleRange: 0..<5_000),
                stripB: AudioGraphStripActivation(sampleRange: 0..<5_000)
            ],
            sources: [
                sourceA: sineSource(frames: 5_000, channels: 1, sampleRate: 48_000, seed: 220),
                sourceB: sineSource(frames: 5_000, channels: 2, sampleRate: 48_000, seed: 330)
            ],
            frameCount: 5_000
        )
    }

    @Test("gain, fade, pan, and ramped bus faders agree across the two engines")
    func automationAcrossEngines() throws {
        let (spec, sourceA, stripA, sourceB, stripB) = twoBusGraph(busA: { bus, strip in
            bus.fader = [
                AudioGraphAutomationPoint(samplePosition: 0, value: -6),
                AudioGraphAutomationPoint(samplePosition: 4_800, value: 0)
            ]
            strip.gain = [AudioGraphAutomationPoint(samplePosition: 0, value: -3)]
            strip.fades = [AudioGraphFade(startSample: 0, endSample: 2_400, curve: .linear)]
            strip.pan = [AudioGraphAutomationPoint(samplePosition: 0, value: -0.5)]
        }, busB: { bus, strip in
            bus.mute = true
            strip.gain = [AudioGraphAutomationPoint(samplePosition: 0, value: 2)]
        })
        try nullCompare(
            spec: spec,
            activations: [
                stripA: AudioGraphStripActivation(sampleRange: 0..<5_000),
                stripB: AudioGraphStripActivation(sampleRange: 0..<5_000)
            ],
            sources: [
                sourceA: sineSource(frames: 5_000, channels: 1, sampleRate: 48_000, seed: 220),
                sourceB: sineSource(frames: 5_000, channels: 2, sampleRate: 48_000, seed: 330)
            ],
            frameCount: 5_000
        )
    }

    @Test("solo suppresses non-solo buses identically in both engines")
    func soloAcrossEngines() throws {
        let (spec, sourceA, stripA, sourceB, stripB) = twoBusGraph(busA: { bus, _ in
            bus.solo = false
        }, busB: { bus, _ in
            bus.solo = true
        })
        try nullCompare(
            spec: spec,
            activations: [
                stripA: AudioGraphStripActivation(sampleRange: 0..<3_000),
                stripB: AudioGraphStripActivation(sampleRange: 0..<3_000)
            ],
            sources: [
                sourceA: sineSource(frames: 3_000, channels: 1, sampleRate: 48_000, seed: 220),
                sourceB: sineSource(frames: 3_000, channels: 2, sampleRate: 48_000, seed: 330)
            ],
            frameCount: 3_000
        )
    }

    @Test("a mixed-rate 44.1 kHz source in a 48 kHz graph agrees across the two engines")
    func mixedRateAcrossEngines() throws {
        // The graph rate is 48k; source B is native 44.1k, so the strip reads
        // it at the 44100/48000 frame ratio (nearest frame, spec §3).
        let (spec, sourceA, stripA, sourceB, stripB) = twoBusGraph()
        let specMixed = AudioRenderGraphSpec(
            version: spec.version,
            sources: [
                spec.sources[0],
                AudioGraphSource(
                    id: sourceB, kind: .original,
                    url: URL(filePath: "/tmp/b.wav"), nativeSampleRate: 44_100
                )
            ],
            clipStrips: spec.clipStrips,
            trackBuses: spec.trackBuses,
            masterBus: spec.masterBus,
            timebase: spec.timebase,
            rendering: spec.rendering
        )
        try nullCompare(
            spec: specMixed,
            activations: [
                stripA: AudioGraphStripActivation(sampleRange: 0..<4_800),
                stripB: AudioGraphStripActivation(
                    sampleRange: 0..<4_800, playbackRate: 44_100.0 / 48_000.0
                )
            ],
            sources: [
                sourceA: sineSource(frames: 4_800, channels: 1, sampleRate: 48_000, seed: 220),
                sourceB: sineSource(frames: 4_410, channels: 2, sampleRate: 44_100, seed: 330)
            ],
            frameCount: 4_800
        )
    }

    @Test("declared latencies shift BOTH engines' windows identically (rule ②)")
    func latencyWindowAcrossEngines() throws {
        let (spec, sourceA, stripA, sourceB, stripB) = twoBusGraph()
        // The declared latency moves the output window forward by 32 frames;
        // because BOTH generators derive the window from the same call, the
        // strips are read at the shifted positions in either engine.
        let specDelayed = AudioRenderGraphSpec(
            version: spec.version,
            sources: spec.sources,
            clipStrips: spec.clipStrips,
            trackBuses: spec.trackBuses,
            masterBus: spec.masterBus,
            timebase: spec.timebase,
            rendering: AudioGraphRenderRules(declaredLatencies: [
                AudioGraphNodeLatency(nodeKind: .eq, algorithmVersion: "1.0.0", reportedLatencySamples: 32)
            ])
        )
        try nullCompare(
            spec: specDelayed,
            activations: [
                stripA: AudioGraphStripActivation(sampleRange: 0..<4_096, sourceFrameOffset: 8),
                stripB: AudioGraphStripActivation(sampleRange: 0..<4_096, sourceFrameOffset: 8)
            ],
            sources: [
                sourceA: sineSource(frames: 4_200, channels: 1, sampleRate: 48_000, seed: 220),
                sourceB: sineSource(frames: 4_200, channels: 2, sampleRate: 48_000, seed: 330)
            ],
            frameCount: 4_096
        )
    }

    @Test("an explicit far tail frame range (drift measurement) agrees across the two engines")
    func tailFrameRangeAcrossEngines() throws {
        // The §9.4 drift measurement renders the 60-minute tail in both
        // engines with the same explicit window; alignment here is what the
        // E2E gate measures.
        let (spec, sourceA, stripA, sourceB, stripB) = twoBusGraph()
        let tailEnd: Int64 = 172_800_000
        let tailFrames: Int64 = 4_800
        let activation = AudioGraphStripActivation(
            sampleRange: (tailEnd - tailFrames - 4_096)..<tailEnd,
            sourceFrameOffset: tailEnd - tailFrames
        )
        try nullCompare(
            spec: spec,
            activations: [stripA: activation, stripB: activation],
            sources: [
                sourceA: sineSource(frames: Int(tailFrames), channels: 1, sampleRate: 48_000, seed: 220),
                sourceB: sineSource(frames: Int(tailFrames), channels: 2, sampleRate: 48_000, seed: 330)
            ],
            frameCount: Int(tailFrames),
            frameRange: (tailEnd - tailFrames)..<tailEnd
        )
    }

    // MARK: - Engine determinism and rejection parity

    @Test("the AVAudioEngine render is deterministic across repeated runs")
    func engineDeterminism() throws {
        let (spec, sourceA, stripA, sourceB, stripB) = twoBusGraph()
        let activations: [UUID: AudioGraphStripActivation] = [
            stripA: AudioGraphStripActivation(sampleRange: 0..<2_000),
            stripB: AudioGraphStripActivation(sampleRange: 0..<2_000)
        ]
        let sources: [UUID: AudioGraphSourceAudio] = [
            sourceA: sineSource(frames: 2_000, channels: 1, sampleRate: 48_000, seed: 220),
            sourceB: sineSource(frames: 2_000, channels: 2, sampleRate: 48_000, seed: 330)
        ]
        let first = try AudioGraphAVAudioEngineRenderer.render(
            spec: spec, activations: activations, sourceAudio: { sources[$0] }, frameCount: 2_000
        )
        let second = try AudioGraphAVAudioEngineRenderer.render(
            spec: spec, activations: activations, sourceAudio: { sources[$0] }, frameCount: 2_000
        )
        #expect(first.interleaved == second.interleaved)
        #expect(first.interleaved.contains { $0 != 0 })
    }

    @Test("placeholder limiter graphs render (G-26: now supported by both engines)")
    func limiterRejectionParity() throws {
        let (spec, sourceA, stripA, sourceB, stripB) = twoBusGraph()
        let specLimited = AudioRenderGraphSpec(
            version: spec.version,
            sources: spec.sources,
            clipStrips: spec.clipStrips,
            trackBuses: spec.trackBuses,
            masterBus: AudioGraphMasterBus(
                limiter: AudioGraphNodeLatency(nodeKind: .limiter, algorithmVersion: "1.0.0", reportedLatencySamples: 16)
            ),
            timebase: spec.timebase,
            rendering: spec.rendering
        )
        let activations = [
            stripA: AudioGraphStripActivation(sampleRange: 0..<8),
            stripB: AudioGraphStripActivation(sampleRange: 0..<8),
        ]
        let sources = [
            sourceA: sineSource(frames: 8, channels: 1, sampleRate: 48_000, seed: 220),
            sourceB: sineSource(frames: 8, channels: 2, sampleRate: 48_000, seed: 330),
        ]
        // G-26 Inc 4: the limiter is now SUPPORTED — both engines render.
        let preview = try AudioGraphAVAudioEngineRenderer.render(
            spec: specLimited, activations: activations, sourceAudio: { sources[$0] }, frameCount: 8
        )
        let export = try AudioGraphEncoderInput.render(
            spec: specLimited, activations: activations, sourceAudio: { sources[$0] }, frameCount: 8
        )
        #expect(preview.frameCount == 8)
        #expect(export.frameCount == 8)
        // The two engines still null-compare (the limiter doesn't change
        // the strip math — it's applied in the master chain, after sum).
        let compare = AudioGraphNullTest.compare(reference: export.interleaved, candidate: preview.interleaved)
        #expect(compare.passed, "engines must remain null-identical with a limiter declared")
    }

    @Test("missing inputs are explicit errors in the engine generator too")
    func missingInputRejection() throws {
        let (spec, sourceA, _, _, _) = twoBusGraph()
        let sources = [sourceA: sineSource(frames: 8, channels: 1, sampleRate: 48_000, seed: 220)]
        // No activation for the strip: both the engine generator and the
        // pure renderer must fail identically (spec: never silent skip).
        #expect(throws: AudioGraphRenderError.self) {
            _ = try AudioGraphAVAudioEngineRenderer.render(
                spec: spec, activations: [:], sourceAudio: { sources[$0] }, frameCount: 8
            )
        }
    }
}
