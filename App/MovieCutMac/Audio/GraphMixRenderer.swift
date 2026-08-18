import CoreMedia
import Foundation
import MovieCutCore

/// G-25 switchover step 2B — the app-side GRAPH MIX renderer: one project
/// state in, the graph-rendered master mix out. The measurement paths (the
/// master-loudness meter, spec §7/§11④) consume this instead of rendering a
/// preview mix through `AVAssetExportSession` — no composition build, no
/// export session, none of the audio-mix path's deadlock exposure.
///
/// Pipeline (spec §0 v1.1 + §3.1):
/// 1. EQ clips get their effective media DERIVED first — the same offline
///    `AudioEqualizerService` render the export path uses, i.e. the same
///    five-band DSP the preview tap applies (spec §0: the graph consumes
///    the effective media; it never re-derives inside the graph).
/// 2. The builder maps the project to a graph.
/// 3. Every source the plan asks for is decoded through the §3.1 adapter
///    (video containers, resampling to the graph rate, speed pre-render).
/// 4. `AudioGraphEncoderInput` renders the encoder-input PCM.
///
/// NR is deliberately NOT applied here: the preview audio-mix path this
/// replaces never applied NR either (offline processing was tracked, not
/// rendered — PlaybackEngine's composition path), so this is at parity.
/// The export-encoding switchover decides NR's graph fate.
enum GraphMixRenderer {
    enum RenderError: Error, Equatable {
        /// The plan references an asset the project no longer carries.
        case assetMissing(UUID)
        /// The project has no audio-carrying clips — nothing to measure.
        case noAudio
    }

    /// Stage-1 identity of the five-band EQ DSP shared by the preview tap
    /// and the offline renderer (spec §6 — recorded on derived sources).
    static let eqAlgorithmVersion = "eq-five-band 1.0.0"

    /// - Parameter eqPresetsByClipId: each clip's resolved EQ preset (the
    ///   same resolution the preview/export paths use —
    ///   `buildAudioProcessingOptions().eqPresets`); absent = no EQ.
    static func renderMix(
        project: Project,
        graphSampleRate: Double = 48_000,
        eqPresetsByClipId: [UUID: EqualizerPreset]
    ) async throws -> AudioGraphSourceAudio {
        // 1. Derive EQ media per clip — the clip's EFFECTIVE media (§0).
        var derivedByClip: [UUID: URL] = [:]
        var temporaryURLs: [URL] = []
        defer { for url in temporaryURLs { try? FileManager.default.removeItem(at: url) } }
        for track in project.timeline.tracks {
            for clip in track.clips {
                guard let assetId = clip.assetId,
                      let asset = project.mediaLibrary.assets[assetId],
                      let preset = eqPresetsByClipId[clip.id] else { continue }
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MovieCutGraphMixEQ-\(clip.id.uuidString)-\(UUID().uuidString)")
                    .appendingPathExtension("caf")
                try await AudioEqualizerService().apply(
                    preset: preset, inputURL: asset.originalURL, outputURL: outputURL
                )
                derivedByClip[clip.id] = outputURL
                temporaryURLs.append(outputURL)
            }
        }

        // 2. Build the graph (derived media in, effectiveMediaFor wired).
        let plan = AudioGraphProjectBuilder.build(
            project: project,
            graphSampleRate: graphSampleRate,
            effectiveMediaFor: { clip in
                derivedByClip[clip.id].map {
                    AudioGraphProjectBuilder.EffectiveAudioMedia(
                        url: $0, algorithmVersion: eqAlgorithmVersion
                    )
                }
            }
        )
        guard plan.spec.clipStrips.isEmpty == false else {
            throw RenderError.noAudio
        }

        // 3. Decode every requested source at the graph rate (§3.1).
        var decoded: [UUID: AudioGraphSourceAudio] = [:]
        func decode(_ id: UUID, from url: URL, speed: Double) async throws {
            decoded[id] = try await AudioGraphSourceAdapter.normalizedAudio(
                fileAt: url, graphSampleRate: graphSampleRate, speed: speed
            )
        }
        for assetId in plan.sourceAssetIds {
            guard let asset = project.mediaLibrary.assets[assetId] else {
                throw RenderError.assetMissing(assetId)
            }
            try await decode(assetId, from: asset.originalURL, speed: 1)
        }
        for request in plan.speedAdjustedSources {
            // A sped clip with EQ derives FIRST, then stretches the derived
            // media (the builder's derived branch owns the clip-id source).
            let url = derivedByClip[request.clipId]
                ?? project.mediaLibrary.assets[request.assetId]?.originalURL
            guard let url else { throw RenderError.assetMissing(request.assetId) }
            try await decode(request.clipId, from: url, speed: request.speed)
        }
        for clipId in plan.derivedClipIds where decoded[clipId] == nil {
            guard let url = derivedByClip[clipId] else { continue }
            try await decode(clipId, from: url, speed: 1)
        }

        // 4. Render the encoder-input PCM over the whole timeline.
        let timebase = AudioGraphTimebase(sampleRate: graphSampleRate, origin: .zero)
        let frameCount = max(1, Int(timebase.samplePosition(
            at: CMTime(seconds: max(project.timeline.duration, 0), preferredTimescale: 600)
        )))
        return try AudioGraphEncoderInput.render(
            spec: plan.spec,
            activations: plan.activations,
            sourceAudio: { decoded[$0] },
            frameCount: frameCount
        )
    }
}
