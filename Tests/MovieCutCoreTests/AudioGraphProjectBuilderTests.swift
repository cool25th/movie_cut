import CoreMedia
import Foundation
import Testing
@testable import MovieCutCore

/// G-25 product-path migration step 1 — the Project→graph builder: field
/// mapping (volume/fades/ducking/mute/solo), exact activation math, the
/// spec v1.1 semantics (§1.1 ducking materialization, §0 effective media,
/// §3.1 decode contract), and engine-renderability of the built plan.
@Suite("AudioGraphProjectBuilder (G-25 migration)")
struct AudioGraphProjectBuilderTests {
    private let asset = MediaAsset(originalURL: URL(filePath: "/tmp/tone.wav"), kind: .audio, duration: 4)

    private func project(
        clips: [(track: TrackKind, clip: Clip)],
        configure: (inout Project) -> Void = { _ in }
    ) -> Project {
        var project = Project(name: "builder")
        project.mediaLibrary.assets[asset.id] = asset
        // Rebuild tracks so clips land on the kinds requested.
        project.timeline.tracks = clips.enumerated().map { index, entry in
            var track = Track(kind: entry.track, name: "T\(index)", zIndex: index)
            track.clips = [entry.clip]
            return track
        }
        configure(&project)
        return project
    }

    private func clip(
        volume: Double = 1.0,
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0,
        timelineStart: TimeInterval = 0,
        duration: TimeInterval = 2,
        sourceStart: TimeInterval = 0
    ) -> Clip {
        Clip(
            assetId: asset.id,
            kind: .audio,
            sourceRange: TimeRange(start: sourceStart, duration: duration),
            timelineRange: TimeRange(start: timelineStart, duration: duration),
            volume: volume,
            fadeInDuration: fadeIn,
            fadeOutDuration: fadeOut
        )
    }

    private func duckedClip(
        rangeStart: TimeInterval,
        rangeDuration: TimeInterval,
        level: Double = 0.25,
        timelineStart: TimeInterval = 0,
        duration: TimeInterval = 4
    ) -> Clip {
        var clip = clip(timelineStart: timelineStart, duration: duration)
        clip.duckingRanges = [TimeRange(start: rangeStart, duration: rangeDuration)]
        clip.duckingLevel = level
        return clip
    }

    // MARK: - Gain mapping

    @Test("volume maps to a constant dB point; zero is the silence floor")
    func volumeToGain() {
        for (volume, expectedDb) in [(1.0, 0.0), (0.5, -6.0206), (2.0, 6.0206), (0.0, AudioGraphProjectBuilder.silenceFloorDb)] {
            let plan = AudioGraphProjectBuilder.build(
                project: project(clips: [(.audio, clip(volume: volume))])
            )
            let gain = plan.spec.clipStrips[0].gain
            #expect(gain.count == 1)
            #expect(abs(gain[0].value - expectedDb) < 0.01, "volume \(volume)")
            #expect(gain[0].samplePosition == 0)
        }
    }

    @Test("fades map to linear fades in sample coordinates")
    func fadesToSamples() {
        let plan = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, clip(fadeIn: 0.5, fadeOut: 0.25, duration: 2))])
        )
        let fades = plan.spec.clipStrips[0].fades
        #expect(fades.count == 2)
        #expect(fades[0] == AudioGraphFade(startSample: 0, endSample: 24_000, curve: .linear))
        #expect(fades[1] == AudioGraphFade(startSample: 84_000, endSample: 96_000, curve: .linear, direction: .fadeOut))
    }

    // MARK: - Ducking materialization (spec §1.1)

    @Test("ducking materializes with attack/hold/release INSIDE the range (spec §1.1)")
    func duckingToGainAutomation() {
        let plan = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, duckedClip(rangeStart: 1.0, rangeDuration: 1.0))])
        )
        let gain = plan.spec.clipStrips[0].gain
        // Constant + 4 ramp points: attack [1.0, 1.12], hold to 1.75,
        // release [1.75, 2.0] — ramps END inside the range (product timing).
        #expect(gain.count == 5)
        #expect(gain[0].samplePosition == 0)
        #expect(gain[1].samplePosition == 48_000)
        #expect(gain[2].samplePosition == Int64(1.12 * 48_000))
        #expect(gain[3].samplePosition == Int64(1.75 * 48_000))
        #expect(gain[4].samplePosition == 96_000)
        // −12.04 dB dip inside the range (0.25 × volume).
        #expect(abs(gain[2].value - (-12.0419)) < 0.01)
        #expect(abs(gain[1].value) < 0.01)
    }

    @Test("ducking ranges are rebased to ABSOLUTE graph time by the clip's timeline start (§1.1)")
    func duckingRebasedToAbsoluteTimeline() {
        let plan = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, duckedClip(rangeStart: 1.0, rangeDuration: 1.0, timelineStart: 0.5))])
        )
        let gain = plan.spec.clipStrips[0].gain
        #expect(gain.count == 5)
        // Clip-local [1.0, 2.0] on a clip starting at 0.5 s → absolute
        // [1.5, 2.5] — clip-local coordinates left as-is would land 0.5 s
        // early (the migration's first-found bug; this pins the rebase).
        #expect(gain[1].samplePosition == Int64(1.5 * 48_000))
        #expect(gain[2].samplePosition == Int64(1.62 * 48_000))
        #expect(gain[3].samplePosition == Int64(2.25 * 48_000))
        #expect(gain[4].samplePosition == Int64(2.5 * 48_000))
    }

    @Test("ranges too short for attack+release duck nothing; level ≥ 1 is a no-op")
    func duckingEdgeCases() {
        // 0.3 s < attack(0.12) + release(0.25) = 0.37 s → constant only.
        let short = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, duckedClip(rangeStart: 0.5, rangeDuration: 0.3))])
        )
        #expect(short.spec.clipStrips[0].gain.count == 1)

        let unity = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, duckedClip(rangeStart: 0.5, rangeDuration: 1.0, level: 1.0))])
        )
        #expect(unity.spec.clipStrips[0].gain.count == 1)
    }

    // MARK: - Effective media (spec §0 v1.1)

    @Test("EQ/NR-derived clips consume per-clip .derived sources (spec §0)")
    func derivedMediaMapping() {
        let plain = clip()
        let equalized = clip(timelineStart: 2)
        let plan = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, plain), (.audio, equalized)]),
            effectiveMediaFor: { clip in
                clip.id == equalized.id
                    ? AudioGraphProjectBuilder.EffectiveAudioMedia(
                        url: URL(filePath: "/tmp/MovieCutEQ.caf"),
                        algorithmVersion: "eq-five-band 1.0.0"
                    )
                    : nil
            }
        )
        // Two sources for one shared asset: the original plus the per-clip
        // derivation (EQ settings are per-clip).
        #expect(plan.spec.sources.count == 2)
        let derived = plan.spec.sources.first { $0.id == equalized.id }
        #expect(derived?.kind == .derived)
        #expect(derived?.derivedFrom == asset.id)
        #expect(derived?.algorithmVersion == "eq-five-band 1.0.0")
        // The plain clip still reads the original; the EQ strip reads the
        // derived source.
        #expect(plan.spec.clipStrips.first { $0.clipId == plain.id }?.sourceId == asset.id)
        #expect(plan.spec.clipStrips.first { $0.clipId == equalized.id }?.sourceId == equalized.id)
        // The caller decodes one original and DERIVES one clip.
        #expect(plan.sourceAssetIds == [asset.id])
        #expect(plan.derivedClipIds == [equalized.id])
    }

    // MARK: - Buses and sources

    @Test("track mute/solo map to the bus; images never become strips")
    func busMapping() {
        let imageAsset = MediaAsset(originalURL: URL(filePath: "/tmp/pic.png"), kind: .image, duration: 1)
        var p = project(clips: [(.audio, clip()), (.video, clip())])
        p.mediaLibrary.assets[imageAsset.id] = imageAsset
        p.timeline.tracks[0].isMuted = true
        p.timeline.tracks[1].isSolo = true
        var imageClip = clip()
        imageClip.assetId = imageAsset.id
        imageClip.kind = .video
        p.timeline.tracks[1].clips = [imageClip, clip()]

        let plan = AudioGraphProjectBuilder.build(project: p)
        #expect(plan.spec.trackBuses.count == 2)
        #expect(plan.spec.trackBuses[0].mute == true)
        #expect(plan.spec.trackBuses[0].solo == false)
        #expect(plan.spec.trackBuses[1].mute == false)
        #expect(plan.spec.trackBuses[1].solo == true)
        // The image clip contributes no strip; the video clip does.
        #expect(plan.spec.trackBuses[1].inputStripIds.count == 1)
        // The shared asset is ONE source (deduplicated).
        #expect(plan.sourceAssetIds == [asset.id])
        #expect(plan.spec.sources.count == 1)
    }

    // MARK: - Activation math (§3.1 decode contract)

    @Test("activations are exact sample ranges with source offsets and rates")
    func activationMath() {
        let plan = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, clip(timelineStart: 0.5, duration: 2, sourceStart: 0.25))]),
            decodedSampleRateFor: { _ in 44_100 },
            channelCountFor: { _ in 1 }
        )
        let strip = plan.spec.clipStrips[0]
        #expect(strip.channelMapping == .mono)
        #expect(strip.sourceId == asset.id)

        let activation = plan.activations[strip.clipId]!
        #expect(activation.sampleRange == 24_000..<120_000)
        #expect(activation.sourceFrameOffset == 11_025) // 0.25 s × 44.1 kHz
        #expect(abs(activation.playbackRate - 44_100.0 / 48_000.0) < 1e-12)
        #expect(plan.spec.sources[0].nativeSampleRate == 44_100)
    }

    @Test("speed-adjusted clips get a per-clip source and stretched activation math (§3.1)")
    func speedAdjustedMapping() {
        var sped = clip(timelineStart: 0.5, duration: 1, sourceStart: 0.25)
        // 2 s of source at 2× speed = 1 s on the timeline (scaleTimeRange).
        sped.sourceRange = TimeRange(start: 0.25, duration: 2)
        sped.playbackRate = 2
        let plan = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, sped)])
        )
        // The stretched source is per-clip (id = clip id), never shared
        // with speed-1 clips of the same asset.
        #expect(plan.spec.sources.count == 1)
        #expect(plan.spec.sources[0].id == sped.id)
        #expect(plan.spec.clipStrips[0].sourceId == sped.id)
        #expect(plan.sourceAssetIds.isEmpty)
        #expect(plan.speedAdjustedSources == [
            AudioGraphProjectBuilder.SpeedAdjustedSource(clipId: sped.id, assetId: asset.id, speed: 2)
        ])
        let activation = plan.activations[sped.id]!
        // Timeline 0.5 s → 1.5 s (source 2 s ÷ 2). Source time 0.25 s sits
        // at stretched offset 0.25/2 = 0.125 s; normalized rate → ratio 1.
        #expect(activation.sampleRange == 24_000..<72_000)
        #expect(activation.sourceFrameOffset == 6_000)
        #expect(activation.playbackRate == 1)
    }

    @Test("speed-1 clips keep sharing the asset source")
    func speedOneSharesAsset() {
        let plan = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, clip()), (.audio, clip(timelineStart: 2))])
        )
        #expect(plan.spec.sources.count == 1)
        #expect(plan.sourceAssetIds == [asset.id])
        #expect(plan.speedAdjustedSources.isEmpty)
        #expect(plan.rampAdjustedSources.isEmpty)
    }

    @Test("ramped clips get a per-clip source, a ramp request, and an offset-0 rate-1 activation (§3.1)")
    func rampAdjustedMapping() {
        var ramped = clip(timelineStart: 0.5, duration: 3)
        ramped.speedRampPoints = [
            SpeedRampPoint(time: 0, rate: 1),
            SpeedRampPoint(time: 1, rate: 2),
        ]
        // A ramp WINS over a constant playbackRate (legacy semantics).
        ramped.playbackRate = 2
        let plan = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, ramped)])
        )
        let strip = plan.spec.clipStrips[0]
        #expect(strip.sourceId == ramped.id)
        #expect(plan.rampAdjustedSources.map(\.clipId) == [ramped.id])
        #expect(plan.rampAdjustedSources[0].points == ramped.speedRampPoints)
        #expect(plan.speedAdjustedSources.isEmpty)
        #expect(plan.sourceAssetIds.isEmpty)

        // The pre-render IS the clip's warped source window — the
        // activation reads offset 0 at rate 1 over the timeline span.
        let activation = plan.activations[strip.clipId]!
        #expect(activation.sampleRange == 24_000..<Int64(3.5 * 48_000))
        #expect(activation.sourceFrameOffset == 0)
        #expect(activation.playbackRate == 1)
    }

    // MARK: - Engine renderability (the plan must actually render)

    @Test("a built plan renders null-identically through BOTH engines")
    func planRendersThroughBothEngines() throws {
        var ducked = clip(volume: 0.8, fadeIn: 0.25, timelineStart: 0, duration: 2)
        ducked.duckingRanges = [TimeRange(start: 0.5, duration: 0.5)]
        ducked.duckingLevel = 0.3
        let plan = AudioGraphProjectBuilder.build(
            project: project(clips: [(.audio, ducked)])
        )
        let frames = 96_000
        let source = AudioGraphSourceAudio(
            sampleRate: 48_000, channels: 2,
            interleaved: (0..<frames * 2).map { Float(sin(Double($0) * 0.05) * 0.7) }
        )
        let sources = [asset.id: source]
        let preview = try AudioGraphAVAudioEngineRenderer.render(
            spec: plan.spec, activations: plan.activations,
            sourceAudio: { sources[$0] }, frameCount: 48_000
        )
        let export = try AudioGraphEncoderInput.render(
            spec: plan.spec, activations: plan.activations,
            sourceAudio: { sources[$0] }, frameCount: 48_000
        )
        let result = AudioGraphNullTest.compare(
            reference: export.interleaved, candidate: preview.interleaved
        )
        #expect(result.passed && result.bestOffsetSamples == 0)
        // The ducking dip must be audible in the render (not silence).
        let measurement = AudioGraphLoudness.measure(export)
        #expect(measurement.integratedLufs != nil)
        #expect(measurement.samplePeakDbFs < 0)
    }
}
