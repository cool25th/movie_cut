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

    /// G-26 inspector control. Picker events enqueue synchronously on MainActor
    /// so their order matches the user's order. A single worker drains the
    /// latest desired value and coalesces intermediate selections while an
    /// EditorSession dispatch is suspended.
    func setMasterAudioProcessing(_ processing: MasterAudioProcessing?) {
        desiredMasterAudioProcessing = processing
        masterAudioProcessingMutationGeneration &+= 1

        guard masterAudioProcessingMutationTask == nil else { return }
        masterAudioProcessingMutationTask = Task { @MainActor [weak self] in
            await self?.drainMasterAudioProcessingMutations()
        }
    }

    private func drainMasterAudioProcessingMutations() async {
        while !Task.isCancelled {
            let requestGeneration = masterAudioProcessingMutationGeneration
            let processing = desiredMasterAudioProcessing

            if currentProject.masterAudioProcessing != processing {
                await apply(SetMasterAudioProcessingCommand(processing: processing))
            }

            // A newer picker event or project/session replacement arrived while
            // dispatch/refresh was suspended. Loop once more using only the
            // newest desired state; never let an older request win last.
            guard requestGeneration == masterAudioProcessingMutationGeneration else {
                continue
            }

            masterAudioProcessingMutationTask = nil
            guard currentProject.masterAudioProcessing == processing else { return }

            switch processing {
            case .sns:
                lastStatusMessage = NSLocalizedString("Master audio processing set to the SNS preset.", comment: "")
            case nil:
                lastStatusMessage = NSLocalizedString("Master audio processing turned off.", comment: "")
            }
            return
        }

        masterAudioProcessingMutationTask = nil
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
        let measuredProject = currentProject
        let measuredRevision = masterLoudnessRevision
        let options = buildAudioProcessingOptions()
        defer { isMeasuringMasterLoudness = false }

        func isStillCurrent() -> Bool {
            measuredRevision == masterLoudnessRevision && measuredProject == currentProject
        }

        do {
            let mix = try await GraphMixRenderer.renderMix(
                project: measuredProject,
                eqPresetsByClipId: options.eqPresets
            )
            let measurement = AudioGraphLoudness.measure(mix)
            guard isStillCurrent() else { return }
            masterLoudness = measurement
        } catch GraphMixRenderer.RenderError.noAudio {
            guard isStillCurrent() else { return }
            masterLoudnessError = NSLocalizedString(
                "This project has no audio to measure.", comment: ""
            )
        } catch {
            guard isStillCurrent() else { return }
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
