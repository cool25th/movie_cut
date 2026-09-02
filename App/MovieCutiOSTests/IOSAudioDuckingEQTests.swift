import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// capcut-surpass stage-4 increment 2: DUCKING and EQ reach the shared iOS
/// render plan. Ducking rides the plan's audioMix with the Mac contract
/// (attack 0.12 s / release 0.25 s, ducked level held, ramps clear of fades,
/// merged ranges) mapped onto the REAL placed span — a 2x clip ducks at half
/// its model times. EQ is derived effective media: the clip's audio runs
/// through the shared Core AudioEqualizerService (the same DSP the Mac graph
/// bakes in) into a temp file the composition inserts from — no live EQ tap.
@MainActor
@Suite("iOS ducking + EQ placed-span (stage-4 inc 2)")
struct IOSAudioDuckingEQTests {
    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
    private static let bgmURL: URL = repoRoot
        .appendingPathComponent("Tests/Fixtures/duck_bgm_220hz_4s_mono.wav")
    private static let eqURL: URL = repoRoot
        .appendingPathComponent("Tests/Fixtures/eq_low_high_2s_mono.wav")

    private func bgmProject(
        playbackRate: Double = 1,
        duckingRanges: [TimeRange] = [],
        duckingLevel: Double? = nil
    ) -> Project {
        let assetId = UUID()
        let asset = MediaAsset(originalURL: Self.bgmURL, kind: .audio, duration: 4)
        var clip = Clip(
            assetId: assetId,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        clip.playbackRate = playbackRate
        clip.duckingRanges = duckingRanges
        clip.duckingLevel = duckingLevel
        var project = Project(
            name: "ducking",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .audio, name: "BGM", zIndex: 0, clips: [clip])
            ])
        )
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 320, customHeight: 240)
        return project
    }

    private func eqProject(equalizer: ClipEqualizerSettings?) -> Project {
        let assetId = UUID()
        let asset = MediaAsset(originalURL: Self.eqURL, kind: .audio, duration: 2)
        var clip = Clip(
            assetId: assetId,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        clip.equalizer = equalizer
        var project = Project(
            name: "eq",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .audio, name: "A", zIndex: 0, clips: [clip])
            ])
        )
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 320, customHeight: 240)
        return project
    }

    /// Goertzel tone power in a time window (the Mac e2e ducking/EQ gates use
    /// the same single-bin discrimination).
    private static func tonePower(
        _ samples: [Float], sampleRate: Double, freq: Double, window: (Double, Double)
    ) -> Double {
        let from = max(0, Int(window.0 * sampleRate))
        let to = min(samples.count, Int(window.1 * sampleRate))
        guard to > from else { return 0 }
        let omega = 2.0 * Double.pi * freq / sampleRate
        var cosine = 0.0
        var sine = 0.0
        for (i, idx) in (from..<to).enumerated() {
            let value = Double(samples[idx])
            cosine += value * cos(omega * Double(i))
            sine += value * sin(omega * Double(i))
        }
        return (cosine * cosine + sine * sine) / Double(to - from)
    }

    /// Decodes the composition THROUGH the audioMix (the exact path the
    /// preview player and export session consume) as mono floats.
    private static func decodeThroughMix(
        of asset: AVAsset,
        audioMix: AVMutableAudioMix?
    ) async throws -> ([Float], Double) {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        let output = try #require(
            AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsNonInterleaved: false
                ]
            ),
            "reader mix output"
        )
        output.audioMix = audioMix
        reader.add(output)
        reader.startReading()

        var samples: [Float] = []
        var sampleRate = 44_100.0
        var channelCount = 1
        while let copy = output.copyNextSampleBuffer() {
            if samples.isEmpty,
               let format = CMSampleBufferGetFormatDescription(copy),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) {
                sampleRate = asbd.pointee.mSampleRate
                channelCount = max(1, Int(asbd.pointee.mChannelsPerFrame))
            }
            var list = AudioBufferList()
            var blockBuffer: CMBlockBuffer?
            guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                copy,
                bufferListSizeNeededOut: nil,
                bufferListOut: &list,
                bufferListSize: MemoryLayout<AudioBufferList>.size,
                blockBufferAllocator: nil,
                blockBufferMemoryAllocator: nil,
                flags: 0,
                blockBufferOut: &blockBuffer
            ) == noErr else { continue }
            let audioBuffer = UnsafeMutableAudioBufferListPointer(&list)[0]
            let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            if let data = audioBuffer.mData?.assumingMemoryBound(to: Float.self), sampleCount > 0 {
                let monoCount = sampleCount / channelCount
                var mono = [Float](repeating: 0, count: monoCount)
                for frame in 0..<monoCount {
                    mono[frame] = data[frame * channelCount]
                }
                samples.append(contentsOf: mono)
            }
        }
        return (samples, sampleRate)
    }

    /// Decodes an exported file as mono floats.
    private static func decodeFile(_ url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else { return ([], format.sampleRate) }
        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += channelData[channel][frame] }
            mono[frame] = sum / Float(channels)
        }
        return (mono, format.sampleRate)
    }

    // MARK: - Ducking

    @Test("ducking attenuates the BGM inside the ducked window (Mac contract thresholds)")
    func duckingAttenuates() async throws {
        let plan = try await IOSExportEngine().makeRenderPlan(
            for: bgmProject(
                duckingRanges: [TimeRange(start: 1, duration: 1)],
                duckingLevel: 0.25
            )
        )
        let (samples, rate) = try await Self.decodeThroughMix(of: plan.composition, audioMix: plan.audioMix)
        // Windows avoid the attack (0.12) and release (0.25) ramps.
        let ducked = Self.tonePower(samples, sampleRate: rate, freq: 220, window: (1.3, 1.7))
        let quietA = Self.tonePower(samples, sampleRate: rate, freq: 220, window: (0.25, 0.75))
        let quietB = Self.tonePower(samples, sampleRate: rate, freq: 220, window: (2.75, 3.25))
        let quiet = (quietA + quietB) / 2
        let reductionDb = 10 * log10(max(quiet, 1e-18) / max(ducked, 1e-18))
        let quietDeltaDb = 10 * log10(max(quietA, 1e-18) / max(quietB, 1e-18))
        #expect(reductionDb > 6.0,
                "ducking must attenuate ≥6 dB in the window (got \(reductionDb) dB)")
        #expect(abs(quietDeltaDb) < 3.0,
                "windows outside the duck must stay level (got Δ\(quietDeltaDb) dB)")
        #expect(ducked / max(quiet, 1e-18) < 0.35)
    }

    @Test("ducking windows map onto the PLACED span under speed (2x ducks at half the model times)")
    func duckingFollowsPlacedSpan() async throws {
        // 4s model clip at 2x → placed 2s. Model duck window [1,2] maps to
        // placed [0.5,1.0] (attack 0.06 / release 0.125). A raw-times bug
        // would duck placed [1,2] — the discriminators below catch both.
        let plan = try await IOSExportEngine().makeRenderPlan(
            for: bgmProject(
                playbackRate: 2,
                duckingRanges: [TimeRange(start: 1, duration: 1)],
                duckingLevel: 0.25
            )
        )
        let (samples, rate) = try await Self.decodeThroughMix(of: plan.composition, audioMix: plan.audioMix)
        let mappedDucked = Self.tonePower(samples, sampleRate: rate, freq: 220, window: (0.6, 0.9))
        let before = Self.tonePower(samples, sampleRate: rate, freq: 220, window: (0.1, 0.35))
        let after = Self.tonePower(samples, sampleRate: rate, freq: 220, window: (1.3, 1.7))
        let quiet = (before + after) / 2
        let reductionDb = 10 * log10(max(quiet, 1e-18) / max(mappedDucked, 1e-18))
        #expect(reductionDb > 6.0,
                "the duck must land at the MAPPED placed window (got \(reductionDb) dB)")
        let afterRatio = after / max(quiet, 1e-18)
        #expect(afterRatio > 0.5,
                "placed 1.3–1.7 is past the duck and must stay loud — a raw-times mapping would duck it (ratio \(afterRatio))")
    }

    @Test("no ducking metadata keeps a nil audioMix")
    func noDuckingKeepsNilMix() async throws {
        let plan = try await IOSExportEngine().makeRenderPlan(for: bgmProject())
        #expect(plan.audioMix == nil)
    }

    // MARK: - EQ derived effective media

    @Test("an EQ'd clip inserts from derived effective media (structure)")
    func eqPlanInsertsDerivedMedia() async throws {
        let plan = try await IOSExportEngine().makeRenderPlan(
            for: eqProject(equalizer: .settings(for: .bassBoost))
        )
        let sources = plan.composition
            .tracks(withMediaType: .audio)
            .flatMap(\.segments)
            .compactMap(\.sourceURL)
            .map(\.lastPathComponent)
        #expect(!sources.isEmpty)
        #expect(sources.allSatisfy { $0.contains("MovieCutiOS-EQ-") },
                "the EQ'd clip must insert from the derived temp file, got \(sources)")

        let flatPlan = try await IOSExportEngine().makeRenderPlan(for: eqProject(equalizer: nil))
        let flatSources = flatPlan.composition
            .tracks(withMediaType: .audio)
            .flatMap(\.segments)
            .compactMap(\.sourceURL)
            .map(\.lastPathComponent)
        #expect(flatSources.allSatisfy { !$0.contains("MovieCutiOS-EQ-") },
                "a flat/absent EQ must keep the original source path, got \(flatSources)")
    }

    @Test("bassBoost export measurably reshapes the spectrum (behavioral)")
    func eqExportReshapesSpectrum() async throws {
        let engine = IOSExportEngine()
        let bassExport = try await engine.exportProject(
            eqProject(equalizer: .settings(for: .bassBoost))
        )
        let baseExport = try await engine.exportProject(eqProject(equalizer: nil))
        defer {
            try? FileManager.default.removeItem(at: bassExport)
            try? FileManager.default.removeItem(at: baseExport)
        }

        let (bassSamples, bassRate) = try Self.decodeFile(bassExport)
        let (baseSamples, baseRate) = try Self.decodeFile(baseExport)

        func lowHighRatio(_ samples: [Float], _ rate: Double) -> Double {
            let low = Self.tonePower(samples, sampleRate: rate, freq: 110, window: (0.2, 1.8))
            let high = Self.tonePower(samples, sampleRate: rate, freq: 4000, window: (0.2, 1.8))
            return low / max(high, 1e-18)
        }
        let bassRatio = lowHighRatio(bassSamples, bassRate)
        let baseRatio = lowHighRatio(baseSamples, baseRate)
        #expect(bassRatio > baseRatio * 2.0,
                "bassBoost must raise the low/high energy ratio at least 2x vs the un-EQ'd export (bass=\(bassRatio) base=\(baseRatio))")
    }
}
