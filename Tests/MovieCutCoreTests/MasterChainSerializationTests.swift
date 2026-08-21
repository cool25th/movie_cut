import Foundation
import Testing
@testable import MovieCutCore

/// G-26 parameter serialization (spec §6) — the master chain's parameters
/// travel WITH the graph (master bus) and the project (preset), and the
/// renderers consume the SERIALIZED values. The measured-consumption test
/// is the increment's core assertion: a modified serialized parameter must
/// change the rendered output (serialization nobody reads is the
/// code-review #8 defect class again).
@Suite("Master Chain Serialization (G-26 §6)")
struct MasterChainSerializationTests {
    private func loudSine() -> AudioGraphSourceAudio {
        let sampleRate = 48_000
        var interleaved = [Float]()
        for sample in 0..<(sampleRate * 2) {
            let frame = sample / 2
            interleaved.append(Float(sin(Double(frame) * 2 * .pi * 440 / Double(sampleRate)) * 0.95))
        }
        return AudioGraphSourceAudio(sampleRate: Double(sampleRate), channels: 2, interleaved: interleaved)
    }

    private func graph(masterBus: AudioGraphMasterBus) -> (spec: AudioRenderGraphSpec, stripClipId: UUID) {
        let source = AudioGraphSource(
            id: UUID(),
            kind: .original,
            url: URL(fileURLWithPath: "/tmp/g26_serialization.wav")
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
        let spec = AudioRenderGraphSpec(
            sources: [source],
            clipStrips: [strip],
            trackBuses: [bus],
            masterBus: masterBus
        )
        return (spec, strip.clipId)
    }

    private func renderedTruePeakDbTp(masterBus: AudioGraphMasterBus) throws -> Double {
        let (spec, stripClipId) = graph(masterBus: masterBus)
        let audio = loudSine()
        let rendered = try AudioGraphOfflineRenderer.render(
            spec: spec,
            activations: [stripClipId: AudioGraphStripActivation(
                sampleRange: 0..<48_000,
                sourceFrameOffset: 0,
                playbackRate: 1
            )],
            sourceAudio: { _ in audio },
            frameCount: 24_000
        )
        let measurement = AudioGraphLoudness.measure(rendered)
        return measurement.truePeakDbTp ?? 0
    }

    @Test("master bus round-trips the chain and the §6 preset version")
    func masterBusCodableRoundTrip() throws {
        var chain = AudioGraphMasterChain.Chain.sns
        chain.compressor?.thresholdDb = -30
        let bus = AudioGraphMasterBus(
            masterChain: chain,
            presetAlgorithmVersion: AudioGraphMasterChain.snsPresetAlgorithmVersion
        )
        let (spec, _) = graph(masterBus: bus)
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(AudioRenderGraphSpec.self, from: data)
        #expect(decoded.masterBus.masterChain == chain)
        #expect(decoded.masterBus.presetAlgorithmVersion == "1.0.0")
        #expect(decoded.masterBus.resolvedMasterChain() == chain)
    }

    @Test("resolvedMasterChain: serialized wins, legacy limiter falls back to SNS, neither is nil")
    func resolutionPrecedence() {
        // Serialized chain wins even without a limiter declaration.
        var chain = AudioGraphMasterChain.Chain.sns
        chain.limiter?.ceilingDb = -3
        let serialized = AudioGraphMasterBus(masterChain: chain)
        #expect(serialized.resolvedMasterChain() == chain)

        // Legacy graph: only a limiter latency declaration, no serialized
        // chain — the pre-serialization renderers hardcoded SNS, so the
        // fallback preserves their behavior.
        let legacy = AudioGraphMasterBus(
            limiter: AudioGraphMasterChain.snsLimiterLatency(sampleRate: 48_000)
        )
        #expect(legacy.resolvedMasterChain() == .sns)

        // Default bus: no processing.
        #expect(AudioGraphMasterBus().resolvedMasterChain() == nil)
    }

    @Test("the builder expands the project preset into the master bus")
    func builderExpandsPreset() {
        var project = Project(name: "g26")
        project.masterAudioProcessing = .sns
        let plan = AudioGraphProjectBuilder.build(project: project)
        #expect(plan.spec.masterBus.masterChain == .sns)
        #expect(plan.spec.masterBus.presetAlgorithmVersion == AudioGraphMasterChain.snsPresetAlgorithmVersion)
        #expect(plan.spec.masterBus.limiter?.nodeKind == .limiter)
        #expect(plan.spec.masterBus.limiter?.lookAheadSamples == 240)  // 5ms @ 48k
        // Nil preset: the default no-processing bus.
        let plain = AudioGraphProjectBuilder.build(project: Project(name: "plain"))
        #expect(plain.spec.masterBus.masterChain == nil)
        #expect(plain.spec.masterBus.limiter == nil)
    }

    @Test("the renderer consumes the SERIALIZED parameters — a modified ceiling changes the rendered true peak")
    func rendererConsumesSerializedParameters() throws {
        func peak(ceilingDb: Double) throws -> Double {
            var chain = AudioGraphMasterChain.Chain.sns
            chain.limiter?.ceilingDb = ceilingDb
            chain.compressor = nil
            chain.reverb = nil
            return try renderedTruePeakDbTp(masterBus: AudioGraphMasterBus(masterChain: chain))
        }
        let strict = try peak(ceilingDb: -6)
        let loose = try peak(ceilingDb: -1)
        // The serialized ceiling must reach the limiter: a −6 dBTP chain
        // renders measurably quieter than a −1 dBTP chain.
        #expect(strict < loose - 3.0, "strict=\(strict) loose=\(loose)")
        #expect(strict < -5.0, "the −6 dBTP ceiling must bind: \(strict)")
    }

    @Test("the set-preset command installs and clears the project preset")
    func commandAppliesPreset() throws {
        var project = Project(name: "g26-cmd")
        try SetMasterAudioProcessingCommand(preset: .sns).apply(to: &project)
        #expect(project.masterAudioProcessing == .sns)
        try SetMasterAudioProcessingCommand(preset: nil).apply(to: &project)
        #expect(project.masterAudioProcessing == nil)
    }

    @Test("the full product route renders the preset: project → builder bus → limited true peak")
    func projectRouteRendersPreset() throws {
        // A project with one loud audio clip, preset on vs off. The graph
        // BUILDER (the product path) expands the preset into the master
        // bus; the offline renderer consumes it. The measured difference
        // proves the UI toggle's route end to end.
        func renderTruePeakDbTp(preset: MasterAudioProcessing?) throws -> Double {
            var project = Project(name: "route")
            project.masterAudioProcessing = preset
            let assetId = UUID()
            project.mediaLibrary.assets[assetId] = MediaAsset(
                originalURL: URL(fileURLWithPath: "/tmp/route.wav"), kind: .audio, duration: 0.5
            )
            var track = Track(kind: .audio, name: "a", zIndex: 0)
            let clip = Clip(
                assetId: assetId,
                kind: .audio,
                sourceRange: TimeRange(start: 0, duration: 0.5),
                timelineRange: TimeRange(start: 0, duration: 0.5)
            )
            track.clips = [clip]
            project.timeline.tracks = [track]

            let plan = AudioGraphProjectBuilder.build(project: project)
            guard let strip = plan.spec.clipStrips.first else {
                throw NSError(domain: "test", code: 1)
            }
            let rendered = try AudioGraphOfflineRenderer.render(
                spec: plan.spec,
                activations: [strip.clipId: AudioGraphStripActivation(
                    sampleRange: 0..<24_000,
                    sourceFrameOffset: 0,
                    playbackRate: 1
                )],
                sourceAudio: { _ in loudSine() },
                frameCount: 24_000
            )
            return AudioGraphLoudness.measure(rendered).truePeakDbTp ?? 0
        }
        let bypassed = try renderTruePeakDbTp(preset: nil)
        let processed = try renderTruePeakDbTp(preset: .sns)
        #expect(bypassed > -0.5, "the raw mix must peak near 0 dBFS: \(bypassed)")
        #expect(processed <= -0.5, "the preset's limiter must bind: \(processed)")
    }

    @Test("project round-trips the master processing preset; nil omits the key")
    func projectCodableRoundTrip() throws {
        var project = Project(name: "g26")
        project.masterAudioProcessing = .sns
        let data = try JSONEncoder().encode(project)
        #expect(try JSONDecoder().decode(Project.self, from: data).masterAudioProcessing == .sns)

        project.masterAudioProcessing = nil
        let plainData = try JSONEncoder().encode(project)
        let plainJSON = String(data: plainData, encoding: .utf8) ?? ""
        #expect(!plainJSON.contains("masterAudioProcessing"))
        #expect(try JSONDecoder().decode(Project.self, from: plainData).masterAudioProcessing == nil)
    }
}
