import Foundation
import MovieCutCore

// Audio boundary of the EditorViewModel decomposition (roadmap:
// timeline → selection → transport → inspector → media → effects* → AUDIO →
// export). Pure method moves — no behavior change. (*effects turned out to
// be fully blocked by private stored state — see session notes.)
//
// Deliberately NOT moved (pure-move rule — private members shared with
// non-audio features): autoDuckOtherAudio, extractAudio(from:), detectBeats
// (private sourceClipAndAsset, also used by motion tracking / auto-reframe /
// beat flow), extractAudioFromSelectedClip (private
// recordAnalysisResult / reportQuickTool*), addVoiceoverAudio (private
// ensureTrack / resolvedVoiceoverDuration), buildAudioProcessingOptions
// (private clipEQPresets). sourceClipAndAsset is the largest shared-private
// hub blocking further boundaries; promoting it requires the separately
// approved access-normalization increment.
extension EditorViewModel {
    func applyDucking(to clipId: UUID, duckLevel: Double = 0.3) async {
        await apply(AudioDuckingCommand(clipId: clipId, duckLevel: duckLevel))
    }

    /// G-26 inspector control: routes the project-level master preset through
    /// the command/session path so persistence, dirty-state tracking, undo and
    /// redo all behave like normal edits. Changing the chain invalidates the
    /// previous loudness measurement because it described a different mix.
    func setMasterAudioProcessing(_ processing: MasterAudioProcessing?) async {
        let previous = currentProject.masterAudioProcessing
        guard previous != processing else { return }

        await apply(SetMasterAudioProcessingCommand(processing: processing))
        guard currentProject.masterAudioProcessing == processing else { return }

        masterLoudness = nil
        masterLoudnessError = nil
        switch processing {
        case .sns:
            lastStatusMessage = "Master audio processing set to SNS 좋은 소리."
        case nil:
            lastStatusMessage = "Master audio processing turned off."
        }
    }

    /// G-25 switchover step 2B (spec §7·§11④): measures the project's REAL
    /// current mix through the GRAPH — `GraphMixRenderer` builds the graph
    /// from project state (volumes, fades, ducking, mute/solo, EQ as
    /// derived effective media) and renders the encoder-input PCM, which
    /// the shared Core meter (BS.1770-4 LUFS-I + 4× true peak) measures.
    /// No preview composition build and no AVAssetExportSession — the old
    /// meter path's deadlock exposure is structurally gone. 실측값 — never
    /// an estimate of the source files.
    func measureMasterLoudness() async {
        guard !isMeasuringMasterLoudness else { return }
        isMeasuringMasterLoudness = true
        masterLoudnessError = nil
        defer { isMeasuringMasterLoudness = false }
        do {
            let options = buildAudioProcessingOptions()
            let mix = try await GraphMixRenderer.renderMix(
                project: currentProject,
                eqPresetsByClipId: options.eqPresets
            )
            masterLoudness = AudioGraphLoudness.measure(mix)
        } catch GraphMixRenderer.RenderError.noAudio {
            masterLoudnessError = NSLocalizedString(
                "This project has no audio to measure.", comment: ""
            )
        } catch {
            masterLoudnessError = error.localizedDescription
        }
    }

    #if DEBUG || MOVIECUT_HARNESS
    /// Deterministic two-track ducking fixture used by the headless E2E harness.
    /// It builds the same project state a user would create, then applies
    /// `SetAudioDuckingCommand` so export/preview ramp wiring is exercised for real.
    func configureDuckingHarness(bgmURL: URL, voiceURL: URL, applyDucking: Bool) async {
        do {
            let bgmAsset = MediaAsset(originalURL: bgmURL, kind: .audio, duration: 4.0)
            let voiceAsset = MediaAsset(originalURL: voiceURL, kind: .audio, duration: 1.0)
            let bgmTrack = Track(kind: .audio, name: "UITest BGM", zIndex: 0)
            let voiceTrack = Track(kind: .audio, name: "UITest Voice", zIndex: 1)
            let bgmClip = Clip(
                assetId: bgmAsset.id,
                kind: .audio,
                sourceRange: TimeRange(start: 0, duration: 4.0),
                timelineRange: TimeRange(start: 0, duration: 4.0)
            )
            let voiceClip = Clip(
                assetId: voiceAsset.id,
                kind: .audio,
                sourceRange: TimeRange(start: 0, duration: 1.0),
                timelineRange: TimeRange(start: 1.0, duration: 1.0)
            )

            try await session.dispatch(ImportMediaCommand(asset: bgmAsset))
            try await session.dispatch(ImportMediaCommand(asset: voiceAsset))
            try await session.dispatch(CreateTrackCommand(track: bgmTrack))
            try await session.dispatch(CreateTrackCommand(track: voiceTrack))
            try await session.dispatch(AddClipCommand(trackId: bgmTrack.id, clip: bgmClip))
            try await session.dispatch(AddClipCommand(trackId: voiceTrack.id, clip: voiceClip))
            if applyDucking {
                let ranges = AudioDuckingPlanner.duckingRanges(
                    forTarget: bgmClip.timelineRange,
                    voiceIntervals: [voiceClip.timelineRange]
                )
                try await session.dispatch(SetAudioDuckingCommand(
                    duckingRangesByClip: [bgmClip.id: ranges],
                    level: AudioDuckingPlanner.defaultDuckingLevel
                ))
            }
            try await refreshFromSession()
            selectedAssetId = bgmAsset.id
            selectedClipId = bgmClip.id
            playheadTime = voiceClip.timelineRange.start
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "ducking harness failed: \(error.localizedDescription)"
        }
    }
    #endif

    /// Clears range-based ducking from the selected clip.
    func clearDuckingOnSelectedClip() async {
        guard let selectedClipId, let selectedClip, !selectedClip.duckingRanges.isEmpty else { return }
        await apply(SetAudioDuckingCommand(duckingRangesByClip: [selectedClipId: []], level: nil))
        lastStatusMessage = "Cleared audio ducking on the selected clip."
    }

    func extractAudioFromSelection() async {
        await extractAudioFromSelectedClip()
    }
}
