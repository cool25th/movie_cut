import Foundation
import MovieCutCore
#if canImport(AVFoundation)
import AVFoundation
#endif

// MARK: - Vocal separation wiring (requirement 9: F-21 → app UI)

// App-layer entry point for offline vocal separation. Mirrors the
// `NoiseReductionService` wiring pattern (offline render → produce a processed
// file → swap the clip's source to that file), with one deliberate departure:
// the import + clip source swap are issued as a SINGLE dispatch of
// `ImportAndSetClipSourceCommand`, so the operation is ONE undo unit
// (requirement 9.3). The editor session snapshots the whole project once per
// dispatch, so splitting import and swap into two dispatches (as the legacy
// noise-reduction path does) would be two undo steps and could leave a dangling
// imported asset if only the second were undone.
//
// The renderer is audio-only and produces a PCM `.caf`; it reads an
// `AVAudioFile`, so the source asset's URL must be a readable audio file. Video
// clips are rejected here with an explicit message (requirement 9.4): use the
// existing Extract Audio action to derive an audio clip first. Mono input is
// rejected explicitly inside the renderer (`monoInputUnsupported`), never as a
// silent passthrough.

extension EditorViewModel {

    /// Whether the current selection can have vocal separation applied.
    ///
    /// Mirrors `canApplyNoiseReductionToSelection` but restricts to audio clips:
    /// the renderer produces a processed audio file and swaps the clip's source
    /// to it, which is only meaningful for an audio clip whose URL is a readable
    /// audio file.
    var canApplyVocalSeparationToSelection: Bool {
        guard let clip = selectedClip, let asset = selectedClipSourceAsset else { return false }
        return clip.kind == .audio && asset.kind == .audio
    }

    /// Applies vocal separation to an audio clip in a single undo unit.
    ///
    /// - Parameters:
    ///   - clipId: The target audio clip.
    ///   - mode: `.removeVocals` (karaoke / instrumental) or `.isolateCenter`
    ///     (approximate vocal isolation).
    ///   - strength: Effect amount in `[0, 1]`; `0` is passthrough, `1` is full
    ///     cancellation/isolation. Clamped by the renderer.
    /// - Throws: `EditorCommandError.invalidCommand` for non-audio clips, or the
    ///   renderer's errors (e.g. `VocalSeparationRendererError.monoInputUnsupported`
    ///   for mono input — requirement 9.4).
    func applyVocalSeparation(
        for clipId: UUID,
        mode: VocalSeparationMode,
        strength: Float = 1
    ) async throws {
        let project = currentProject

        // Locate the clip + asset using the same lookup shape as
        // `sourceClipAndAsset`, which is private and thus not visible from this
        // extension file.
        guard let (clip, asset) = Self.locateAudioClipAndAsset(for: clipId, in: project) else {
            throw EditorCommandError.clipNotFound(clipId)
        }
        guard clip.kind == .audio, asset.kind == .audio else {
            throw EditorCommandError.invalidCommand(
                "Vocal separation applies to an audio clip. Extract audio from a video clip first."
            )
        }

        let renderer = VocalSeparationRenderer(mode: mode, wetMix: strength)
        let processedURL = try await renderer.render(inputURL: asset.originalURL)

        // Build a new asset for the processed file, preserving the source
        // duration so timeline width / playback rate stay consistent. Matches
        // the MediaAsset construction used by `applyNoiseReduction`.
        let processedAsset = MediaAsset(
            originalURL: processedURL,
            kind: .audio,
            duration: asset.duration,
            metadata: MediaMetadata(fileSize: Self.processedFileSize(for: processedURL))
        )

        // Single dispatch = single undo unit (import + swap are atomic).
        // `dispatchCommand` performs the dispatch and refreshes the view model
        // from the session snapshot.
        try await dispatchCommand(
            ImportAndSetClipSourceCommand(clipId: clipId, asset: processedAsset, kind: .audio)
        )

        // The clip id is unchanged but the source asset (and thus the audio
        // waveform) is new. Invalidate the stale waveform so the view re-decodes
        // the swapped-in asset. Mirrors the post-swap step in
        // `applyNoiseReduction`.
        if let updatedClip = currentProject.timeline.tracks
            .flatMap(\.clips)
            .first(where: { $0.id == clipId }) {
            invalidateWaveform(for: updatedClip)
        }

        selectedAssetId = processedAsset.id
    }

    /// Selection-level convenience that surfaces success/failure through the
    /// same status channel used by `applyNoiseReductionToSelection`.
    ///
    /// `reportQuickToolSuccess`/`reportQuickToolFailure` are private to
    /// `EditorViewModel.swift`, so this writes the same status/error fields
    /// directly to stay within the "no edits to EditorViewModel.swift" rule.
    func applyVocalSeparationToSelection(
        mode: VocalSeparationMode,
        strength: Float = 1
    ) async {
        guard let clipId = selectedClipId, canApplyVocalSeparationToSelection else {
            quickToolProgressMessage = nil
            lastStatusMessage = nil
            lastErrorMessage = "Select an audio clip for vocal separation."
            return
        }

        do {
            try await applyVocalSeparation(for: clipId, mode: mode, strength: strength)
            let label = mode == .removeVocals ? "Vocal removal" : "Center isolation"
            quickToolProgressMessage = nil
            lastErrorMessage = nil
            lastStatusMessage = "\(label) applied."
        } catch {
            quickToolProgressMessage = nil
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Local lookups

    /// Finds an audio-kind clip and its asset by id, mirroring the private
    /// `sourceClipAndAsset(for:in:)` shape but restricted to audio assets.
    private static func locateAudioClipAndAsset(
        for clipId: UUID,
        in project: Project
    ) -> (clip: Clip, asset: MediaAsset)? {
        for track in project.timeline.tracks {
            if let clip = track.clips.first(where: { $0.id == clipId }),
               let assetId = clip.assetId,
               let asset = project.mediaLibrary.assets[assetId],
               asset.kind == .audio {
                return (clip, asset)
            }
        }
        return nil
    }

    /// File size in bytes for a processed-asset URL, or nil if unreadable.
    /// Mirrors the private `fileSize(for:)` helper so the imported asset's
    /// metadata is populated. Distinct name avoids shadowing the private
    /// instance helper in `EditorViewModel.swift`.
    static func processedFileSize(for url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }
}
