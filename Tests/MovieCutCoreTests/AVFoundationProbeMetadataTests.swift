import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing

/// F-06 behavioral replacement: the static file asserted that
/// `AVFoundationProbe` *contains* probe helpers; these tests run them against
/// the committed fixtures and assert the metadata they actually produce —
/// dimensions, frame rate, codec, duration for video; dimensions for images;
/// duration/sample rate/channels for audio. The panel summary-format strings
/// the old file also checked are copy trivia and die with it.
@Suite("AVFoundationProbe metadata")
struct AVFoundationProbeMetadataTests {
    private func fixture(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return url.path
    }

    @Test("video probe fills dimensions, frame rate, codec, and duration")
    func videoProbeFillsCoreMetadata() async {
        let path = fixture("solid_red_tone_320x240_2s_30fps.mp4")
        var asset = MediaImporter.probe(url: URL(fileURLWithPath: path))
        let base = MediaMetadata(fileSize: asset.metadata.fileSize)

        let (duration, metadata) = await AVFoundationProbe.appMetadataProbe(
            for: URL(fileURLWithPath: path),
            kind: asset.kind,
            baseMetadata: base
        )
        asset.duration = duration ?? asset.duration
        asset.metadata = metadata

        #expect(asset.kind == .video)
        #expect(metadata.width == 320)
        #expect(metadata.height == 240)
        let frameRate = metadata.frameRate ?? 0
        #expect(frameRate > 29 && frameRate < 31, "expected ~30fps, got \(frameRate)")
        #expect(metadata.codec == "H.264")
        let seconds = duration ?? 0
        #expect(abs(seconds - 2.0) < 0.1, "expected ~2s, got \(seconds)")
    }

    @Test("image probe fills pixel dimensions")
    func imageProbeFillsDimensions() async {
        let path = fixture("swatch_blue_64x64.png")
        let asset = MediaImporter.probe(url: URL(fileURLWithPath: path))
        let metadata = AVFoundationProbe.imageMetadataProbe(
            for: URL(fileURLWithPath: path),
            baseMetadata: asset.metadata
        )
        #expect(asset.kind == .image)
        #expect(metadata.width == 64)
        #expect(metadata.height == 64)
    }

    @Test("audio probe fills duration, sample rate, and channel count")
    func audioProbeFillsAudioMetadata() async {
        let path = fixture("tone_440hz_2s_mono.wav")
        var asset = MediaImporter.probe(url: URL(fileURLWithPath: path))
        let base = MediaMetadata(fileSize: asset.metadata.fileSize)

        let (duration, metadata) = await AVFoundationProbe.appMetadataProbe(
            for: URL(fileURLWithPath: path),
            kind: asset.kind,
            baseMetadata: base
        )
        asset.duration = duration ?? asset.duration
        asset.metadata = metadata

        #expect(asset.kind == .audio)
        let audioSeconds = duration ?? 0
        #expect(abs(audioSeconds - 2.0) < 0.1, "expected ~2s, got \(audioSeconds)")
        #expect(metadata.sampleRate == 44100)
        #expect(metadata.channelCount == 1)
        #expect(metadata.codec == "PCM")
    }
}
