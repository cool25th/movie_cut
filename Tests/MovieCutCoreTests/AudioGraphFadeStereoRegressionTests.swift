import Foundation
import Testing
@testable import MovieCutCore

/// Code-review regression: the fade direction and stereo channel bugs
/// that shipped in the switchover — pinned so they can never recur.
@Suite("Audio Graph Fade + Stereo Regression (code review)")
struct AudioGraphFadeStereoRegressionTests {
    // MARK: - Fade direction (bug #1)

    @Test("a fade-OUT ramps 1→0 (not 0→1)")
    func fadeOutDirection() {
        let fade = AudioGraphFade(
            startSample: 0, endSample: 100, curve: .linear, direction: .fadeOut
        )
        #expect(abs(AudioGraphOfflineRenderer.fadeFactor([fade], at: 0) - 1.0) < 0.001)
        #expect(abs(AudioGraphOfflineRenderer.fadeFactor([fade], at: 50) - 0.5) < 0.001)
        #expect(abs(AudioGraphOfflineRenderer.fadeFactor([fade], at: 100) - 0.0) < 0.001)
    }

    @Test("a fade-IN ramps 0→1")
    func fadeInDirection() {
        let fade = AudioGraphFade(
            startSample: 0, endSample: 100, curve: .linear, direction: .fadeIn
        )
        #expect(abs(AudioGraphOfflineRenderer.fadeFactor([fade], at: 0) - 0.0) < 0.001)
        #expect(abs(AudioGraphOfflineRenderer.fadeFactor([fade], at: 50) - 0.5) < 0.001)
        #expect(abs(AudioGraphOfflineRenderer.fadeFactor([fade], at: 100) - 1.0) < 0.001)
    }

    @Test("the builder's fadeOut gets direction .fadeOut")
    func builderFadeOutDirection() {
        var clip = Clip(
            assetId: UUID(),
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        clip.fadeOutDuration = 1.0
        let fades = AudioGraphProjectBuilder.fadeAutomation(
            for: clip,
            samplePosition: { seconds in Int64(seconds * 48_000) }
        )
        #expect(fades.count == 1)
        #expect(fades[0].direction == .fadeOut, "the builder must emit .fadeOut")
    }

    @Test("the builder's fadeIn gets direction .fadeIn (default)")
    func builderFadeInDirection() {
        var clip = Clip(
            assetId: UUID(),
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        clip.fadeInDuration = 1.0
        let fades = AudioGraphProjectBuilder.fadeAutomation(
            for: clip,
            samplePosition: { seconds in Int64(seconds * 48_000) }
        )
        #expect(fades.count == 1)
        #expect(fades[0].direction == .fadeIn)
    }

    @Test("end-to-end: a rendered fade-out actually diminishes")
    func renderedFadeOutDiminishes() throws {
        var project = Project(name: "fade")
        let asset = MediaAsset(originalURL: URL(fileURLWithPath: "/tmp/t.wav"), kind: .audio, duration: 2)
        project.mediaLibrary.assets[asset.id] = asset
        var clip = Clip(
            assetId: asset.id,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2),
            volume: 1.0
        )
        clip.fadeOutDuration = 1.0
        var track = Track(kind: .audio, name: "T", zIndex: 0)
        track.clips = [clip]
        project.timeline.tracks = [track]

        let plan = AudioGraphProjectBuilder.build(project: project)

        let frames = 96_000
        let source = AudioGraphSourceAudio(
            sampleRate: 48_000, channels: 2,
            interleaved: Array(repeating: Float(0.5), count: frames * 2)
        )
        let rendered = try AudioGraphOfflineRenderer.render(
            spec: plan.spec,
            activations: plan.activations,
            sourceAudio: { _ in source },
            frameCount: frames
        )

        let firstHalfRms = rms(rendered, 0, 24_000)
        let lastQuarterRms = rms(rendered, 72_000, 24_000)

        let nonZero = rendered.interleaved.filter { $0 != 0 }.count
        print("DEBUG: strips=\(plan.spec.clipStrips.count) fades=\(plan.spec.clipStrips.first?.fades.count ?? -1) nonzero=\(nonZero)/\(rendered.interleaved.count)")
        #expect(firstHalfRms > 0.3, "pre-fade must be at full level; got \(firstHalfRms)")
        #expect(lastQuarterRms < firstHalfRms * 0.3,
                "fade-out must diminish; pre=\(firstHalfRms) post=\(lastQuarterRms)")
    }

    // MARK: - Stereo channel (bug #2)

    @Test("stereo: left and right carry DIFFERENT per-frame content")
    func stereoChannelsAreDistinct() {
        let frames = 100
        var interleaved = [Float]()
        for frame in 0..<frames {
            interleaved.append(Float(frame) / Float(frames))  // left: ramp
            interleaved.append(0.5)                             // right: constant
        }
        let audio = AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: interleaved)
        let strip = AudioGraphClipStrip(
            clipId: UUID(), sourceId: UUID(), channelMapping: .stereo
        )

        let (left, right) = AudioGraphOfflineRenderer.mappedChannels(
            strip: strip, audio: audio, frame: 80
        )
        #expect(abs(Double(left) - 0.8) < 0.01, "left must follow the ramp; got \(left)")
        #expect(abs(Double(right) - 0.5) < 0.01, "right must be 0.5; got \(right)")

        let (left2, right2) = AudioGraphOfflineRenderer.mappedChannels(
            strip: strip, audio: audio, frame: 20
        )
        #expect(abs(Double(left2) - 0.2) < 0.01, "left at f20; got \(left2)")
        #expect(abs(Double(right2) - 0.5) < 0.01, "right must vary by frame; got \(right2)")
    }

    @Test("a mono source mapped as .stereo duplicates to both channels")
    func monoAsStereoDuplicates() {
        let audio = AudioGraphSourceAudio(
            sampleRate: 48_000, channels: 1,
            interleaved: (0..<100).map { Float($0) / 100 }
        )
        let strip = AudioGraphClipStrip(
            clipId: UUID(), sourceId: UUID(), channelMapping: .stereo
        )
        let (left, right) = AudioGraphOfflineRenderer.mappedChannels(
            strip: strip, audio: audio, frame: 50
        )
        #expect(left == right, "mono source must duplicate to both channels")
        #expect(abs(Double(left) - 0.5) < 0.01)
    }

    // MARK: - Helpers

    private func rms(_ audio: AudioGraphSourceAudio, _ start: Int, _ count: Int) -> Double {
        var sum: Double = 0
        var samples = 0
        for frame in start..<(start + count) {
            for channel in 0..<2 {
                let index = (frame * 2) + channel
                if index < audio.interleaved.count {
                    let value = Double(audio.interleaved[index])
                    sum += value * value
                    samples += 1
                }
            }
        }
        return samples > 0 ? (sum / Double(samples)).squareRoot() : 0
    }
}
