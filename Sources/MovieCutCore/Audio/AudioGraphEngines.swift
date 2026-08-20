import AVFoundation
import Foundation
import os

/// G-25 Inc 8 (App half) — the TWO engine generators (spec §1·§4·§9): one
/// spec in, one graph per engine out, and NO other path may produce audio
/// samples. Both generators
///
/// - derive their render window from the SAME `AudioGraphLatency`
///   compensation call (rule ② — never their own math),
/// - evaluate each strip through the SAME shared strip-chain math
///   (`AudioGraphOfflineRenderer.stripFrame`), and
/// - reject placeholder node kinds exactly like the pure renderer (§5).
///
/// What deliberately DIFFERS is the plumbing each engine owns: the preview
/// generator streams strips through a real `AVAudioEngine` (source nodes →
/// per-bus mixers → main mixer, offline manual rendering), so scheduling,
/// format negotiation, render quantization, and summing are the engine's;
/// the export generator renders the encoder input directly. The preview↔
/// export null test (spec §9) therefore verifies the plumbing, not the
/// semantics — semantics are shared by construction.
public enum AudioGraphEncoderInput {
    /// The export engine's PCM at the ENCODER INPUT stage (spec §9.1b):
    /// the latency-compensated window evaluated by the pure renderer. This
    /// is the buffer handed to the output encoder.
    public static func render(
        spec: AudioRenderGraphSpec,
        activations: [UUID: AudioGraphStripActivation],
        sourceAudio: (UUID) -> AudioGraphSourceAudio?,
        frameCount: Int,
        frameRange: Range<Int64>? = nil
    ) throws -> AudioGraphSourceAudio {
        // Rule ②: the export engine compensates with the ONE global pair,
        // identical to the preview engine's call below.
        let window = frameRange ?? AudioGraphLatency.outputWindow(
            forFrameCount: frameCount,
            declaredLatencies: spec.rendering.declaredLatencies
        )
        return try AudioGraphOfflineRenderer.render(
            spec: spec,
            activations: activations,
            sourceAudio: sourceAudio,
            frameCount: frameCount,
            frameRange: window
        )
    }
}

public enum AudioGraphAVAudioEngineRenderer {
    /// Offline render quantum: how many frames each manual-rendering pull
    /// requests. Purely a plumbing constant — the strip math is per-sample
    /// and identical for any chunk size.
    private static let renderChunkFrames: AVAudioFrameCount = 4_096

    public static func render(
        spec: AudioRenderGraphSpec,
        activations: [UUID: AudioGraphStripActivation],
        sourceAudio: (UUID) -> AudioGraphSourceAudio?,
        frameCount: Int,
        frameRange: Range<Int64>? = nil
    ) throws -> AudioGraphSourceAudio {
        guard frameCount > 0 else {
            return AudioGraphSourceAudio(
                sampleRate: spec.timebase.sampleRate, channels: 2, interleaved: []
            )
        }
        // Rule ②: the preview engine compensates with the ONE global pair,
        // identical to the export engine's call above. An explicit frameRange
        // bypasses compensation for MEASUREMENT windows only (the §9.4 drift
        // tail) — both generators must then be given the same range.
        let window = frameRange ?? AudioGraphLatency.outputWindow(
            forFrameCount: frameCount,
            declaredLatencies: spec.rendering.declaredLatencies
        )

        // §5 rejection parity: a graph the pure renderer cannot honor must
        // fail here too, before any engine node is built.
        // G-26: the limiter is now supported (see AudioGraphRendering).

        let strips = try resolvedStrips(
            spec: spec, activations: activations, sourceAudio: sourceAudio
        )

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: spec.timebase.sampleRate, channels: 2
        ) else {
            throw NSError(
                domain: "MovieCutCore.AudioGraphEngines", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "cannot create render format at \(spec.timebase.sampleRate) Hz"]
            )
        }

        let engine = AVAudioEngine()
        let anySolo = spec.trackBuses.contains { $0.solo }

        // One mixer per track bus at UNITY: gain/pan/fader math lives in the
        // shared strip chain, so the engine's own job is scheduling and
        // summing — exactly the plumbing the null test exercises.
        var busMixers: [UUID: AVAudioMixerNode] = [:]
        for bus in spec.trackBuses {
            let mixer = AVAudioMixerNode()
            engine.attach(mixer)
            engine.connect(mixer, to: engine.mainMixerNode, format: format)
            busMixers[bus.trackId] = mixer
        }

        // Precompute each strip's stereo contribution over the window with
        // the shared math, then let a source node stream it into its bus.
        for item in strips {
            let interleaved = precomputedStripBuffer(
                item: item, window: window, anySolo: anySolo,
                masterFader: spec.masterBus.fader
            )
            let stream = StripStream(interleaved: interleaved)
            let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
                stream.fill(frameCount: frameCount, audioBufferList: audioBufferList)
            }
            engine.attach(source)
            engine.connect(source, to: busMixers[item.bus.trackId] ?? engine.mainMixerNode, format: format)
        }

        var out = [Float](repeating: 0, count: frameCount * 2)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: renderChunkFrames) else {
            throw NSError(
                domain: "MovieCutCore.AudioGraphEngines", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "cannot allocate render buffer"]
            )
        }

        // NOTE: no engine.prepare() here — with manual rendering the graph
        // is finalized by enableManualRenderingMode + start, and preparing
        // against the (absent) hardware output fails with -80801.
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: renderChunkFrames)
        try engine.start()
        defer { engine.stop() }

        var rendered = 0
        while rendered < frameCount {
            let chunk = min(Int(renderChunkFrames), frameCount - rendered)
            let status = try engine.renderOffline(AVAudioFrameCount(chunk), to: pcm)
            guard status == .success, let channels = pcm.floatChannelData else {
                throw NSError(
                    domain: "MovieCutCore.AudioGraphEngines", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "offline render failed (\(status.rawValue))"]
                )
            }
            for frame in 0..<chunk {
                let l = (rendered + frame) * 2
                out[l] = channels[0][frame]
                out[l + 1] = channels[1][frame]
            }
            rendered += chunk
        }

        return AudioGraphSourceAudio(
            sampleRate: spec.timebase.sampleRate, channels: 2, interleaved: out
        )
    }

    // MARK: - Graph preparation

    private struct ResolvedStrip {
        var strip: AudioGraphClipStrip
        var bus: AudioGraphTrackBus
        var audio: AudioGraphSourceAudio
        var activation: AudioGraphStripActivation
    }

    /// Resolves every bus→strip→source→audio edge with the SAME missing-input
    /// errors the pure renderer throws, before any engine state exists.
    private static func resolvedStrips(
        spec: AudioRenderGraphSpec,
        activations: [UUID: AudioGraphStripActivation],
        sourceAudio: (UUID) -> AudioGraphSourceAudio?
    ) throws -> [ResolvedStrip] {
        var resolved: [ResolvedStrip] = []
        for bus in spec.trackBuses {
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
                resolved.append(ResolvedStrip(strip: strip, bus: bus, audio: audio, activation: activation))
            }
        }
        return resolved
    }

    /// The strip's interleaved stereo contribution over the absolute window,
    /// silence outside its activation and for muted/non-soloed buses —
    /// exactly what the pure renderer accumulates frame by frame.
    private static func precomputedStripBuffer(
        item: ResolvedStrip,
        window: Range<Int64>,
        anySolo: Bool,
        masterFader: [AudioGraphAutomationPoint]
    ) -> [Float] {
        var buffer = [Float](repeating: 0, count: window.count * 2)
        for index in 0..<window.count {
            let (left, right) = AudioGraphOfflineRenderer.stripFrame(
                strip: item.strip,
                bus: item.bus,
                anyBusSoloed: anySolo,
                masterFader: masterFader,
                audio: item.audio,
                activation: item.activation,
                at: window.lowerBound + Int64(index)
            )
            buffer[index * 2] = left
            buffer[index * 2 + 1] = right
        }
        return buffer
    }

    // MARK: - Source streaming

    /// Streams a precomputed interleaved stereo buffer into the engine's
    /// render pulls. The buffer is immutable; only the cursor is mutable and
    /// every access is locked, so the class is safe to capture in the render
    /// block under complete concurrency checking.
    private final class StripStream: @unchecked Sendable {
        private let interleaved: [Float]
        private let cursor = OSAllocatedUnfairLock(initialState: 0)

        init(interleaved: [Float]) {
            self.interleaved = interleaved
        }

        func fill(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let start = cursor.withLock { $0 }
            cursor.withLock { $0 += Int(frameCount) }

            for (channel, buffer) in buffers.enumerated() {
                guard let data = buffer.mData else { continue }
                let output = data.bindMemory(to: Float.self, capacity: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                // Deinterleaved standard format: buffer 0 = L, 1 = R.
                for frame in 0..<Int(frameCount) {
                    let index = (start + frame) * 2 + min(channel, 1)
                    output[frame] = index >= 0 && index < interleaved.count ? interleaved[index] : 0
                }
            }
            return noErr
        }
    }
}
