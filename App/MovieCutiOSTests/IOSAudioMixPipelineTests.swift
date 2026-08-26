import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// BUG-IOS-10: clip volume and fade durations must reach BOTH the preview
/// player and the exported file. The UI edited these fields but no
/// AVMutableAudioMix existed anywhere on iOS, so preview played the raw
/// source and export wrote it untouched. The render plan now carries an
/// audioMix (Mac PlaybackEngine.applyAudioVolumeAndFades parity).
@MainActor
@Suite("iOS audio mix pipeline (BUG-IOS-10)")
struct IOSAudioMixPipelineTests {
    private static let toneFixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/solid_red_tone_320x240_2s_30fps.mp4")

    /// Red + 440Hz tone clip with volume/fade edits applied.
    private func fadedProject(
        volume: Double = 0.5,
        fadeIn: Double = 0.4,
        fadeOut: Double = 0.4
    ) -> Project {
        let assetId = UUID()
        let asset = MediaAsset(originalURL: Self.toneFixtureURL, kind: .video, duration: 2)
        var clip = Clip(
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        clip.volume = volume
        clip.fadeInDuration = fadeIn
        clip.fadeOutDuration = fadeOut
        var project = Project(
            name: "faded",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
            ])
        )
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 320, customHeight: 240)
        return project
    }

    @Test("the plan's audioMix audibly shapes the composition audio (BUG-IOS-10)")
    func planCarriesAudioMix() async throws {
        let plan = try await IOSExportEngine().makeRenderPlan(for: fadedProject())
        let audioMix = try #require(
            plan.audioMix,
            "a clip with volume/fade edits must produce an audioMix"
        )

        // Read the composition's audio THROUGH the mix — exactly what the
        // preview player and export session consume.
        let windows = try await Self.decodedRMSWindows(
            of: plan.composition,
            audioMix: audioMix,
            windows: [(0.02, 0.22), (0.8, 1.2), (1.78, 1.98)]
        )
        let head = windows[0], body = windows[1], tail = windows[2]
        // The tone fixture's raw RMS is ~0.09; at volume 0.5 the plateau sits
        // near 0.044 — the absolute floor just guards against silence.
        #expect(body > 0.02, "the plateau must carry the tone, got \(body)")
        #expect(head < body * 0.4, "fade-in must attenuate the head: head=\(head) body=\(body)")
        #expect(tail < body * 0.4, "fade-out must attenuate the tail: tail=\(tail) body=\(body)")
    }

    /// Decodes an asset's audio (optionally THROUGH an audioMix, the path the
    /// player and export session use) and returns per-window RMS.
    private static func decodedRMSWindows(
        of asset: AVAsset,
        audioMix: AVMutableAudioMix?,
        windows: [(Double, Double)]
    ) async throws -> [Double] {
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
            ) == noErr else {
                continue
            }
            // Interleaved float settings → ONE buffer holds all channels per
            // frame. mDataByteSize/4 counts SAMPLES (frames × channels); a
            // stereo stream read that way doubles the timeline and interleaves
            // L/R as consecutive time — channel 0 at stride `channelCount`
            // keeps the mono-equivalent timeline (measurement bug that faked
            // the RENDER-02 "fade smearing": preset exports were 44.1kHz mono
            // so it stayed hidden until the writer produced 48kHz stereo).
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

        return windows.map { start, end in
            let from = max(0, Int(start * sampleRate))
            let to = min(samples.count, Int(end * sampleRate))
            guard to > from else { return 0 }
            var sum = 0.0
            for i in from..<to {
                sum += Double(samples[i]) * Double(samples[i])
            }
            return (sum / Double(to - from)).squareRoot()
        }
    }

    @Test("a project without audio edits keeps a nil audioMix")
    func noEditsKeepsMixNil() async throws {
        let plan = try await IOSExportEngine().makeRenderPlan(for: fadedProject(volume: 1, fadeIn: 0, fadeOut: 0))
        #expect(plan.audioMix == nil,
                "no audio edits → no mix; playback/export stay untouched")
    }

    @Test("the exported file audibly fades in and out (BUG-IOS-10)")
    func exportedAudioFades() async throws {
        let outputURL = try await IOSExportEngine().exportProject(fadedProject())
        let windows = try await Self.decodedRMSWindows(
            of: AVURLAsset(url: outputURL),
            audioMix: nil,  // the export already baked the mix into the file
            windows: [(0.02, 0.22), (0.8, 1.2), (1.78, 1.98)]
        )
        let head = windows[0], body = windows[1], tail = windows[2]

        // The tone fixture plays at constant amplitude — without ramps all
        // three windows measure alike. With the mix, head/tail sit well under
        // the plateau (AAC padding/encoder delay leaves generous margins).
        #expect(body > 0.02, "the plateau must carry the tone, got \(body)")
        #expect(head < body * 0.4, "fade-in must attenuate the head: head=\(head) body=\(body)")
        #expect(tail < body * 0.4, "fade-out must attenuate the tail: tail=\(tail) body=\(body)")
    }
}
