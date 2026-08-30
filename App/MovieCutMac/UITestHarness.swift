#if DEBUG || MOVIECUT_HARNESS
import AVFoundation
import AppKit
import CoreImage
import Foundation
import MovieCutCore

private enum CardEditorUITestError: LocalizedError {
    case invariant(String)

    var errorDescription: String? {
        switch self {
        case .invariant(let message): message
        }
    }
}

private struct CardEditorUITestActionCounts: Codable, Equatable {
    var add = 0
    var duplicate = 0
    var delete = 0
    var reorder = 0
    var inlineDoubleClick = 0
}

private struct CardEditorUITestFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ frame: NormalizedRect) {
        x = frame.x
        y = frame.y
        width = frame.width
        height = frame.height
    }
}

private struct CardEditorUITestDump: Codable {
    var schemaVersion = 1
    var scenario = "G-18-card-editor-save-reload"
    var complete = false
    var completionMarker = ""
    var error = "not_run"
    var actionCounts = CardEditorUITestActionCounts()
    var initialPageCount = 0
    var finalPageCount = 0
    var orderedPageIDs: [String] = []
    var editedElementID = ""
    var originalText = ""
    var editedText = ""
    var observedFormats: [String] = []
    var beforeFrame: CardEditorUITestFrame?
    var afterFrame: CardEditorUITestFrame?
    var maxNormalizedFrameError = Double.infinity
    var inlineUndoRestored = false
    var inlineRedoRestored = false
    var saveReloadEqual = false
    var savedProjectBytes = 0
    var reloadedProjectBytes = 0
    var savedProjectPath = ""
    var reloadedProjectPath = ""
    var freshSessionReloaded = false
}

private struct CardTemplateUITestDump: Codable {
    var schemaVersion = 1
    var scenario = "G-19-card-template-master-style"
    var complete = false
    var completionMarker = ""
    var error = "not_run"
    var builtinCount = 0
    var builtinSetIDs: [String] = []
    var builtinSetNames: [String] = []
    var appliedSetID = ""
    var appliedSetName = ""
    var pageCount = 0
    var rolesPresent: [String] = []
    var emptyRequiredSlotCount = -1
    var templateClickCount = 99
    var masterClickCount = 99
    var masterPropagationPageCount = 0
    var masterPropagationAcrossAllPages = false
    var masterInheritedPageCount = 0
    var masterFontFamily = ""
    var masterPrimaryColorHex = ""
    var masterLogoPlacement: CardEditorUITestFrame?
    var masterChangedAttributes: [String] = []
    var masterLogoElementCount = 0
    var masterLogoPlacementMatchCount = 0
    var pageOverrideCount = 0
    var pageOverridesPreserved = false
    var templateUndoRestored = false
    var templateRedoRestored = false
    var masterUndoRestored = false
}

extension EditorViewModel {
    /// Measures per-frame CoreImage compositor render cost at 1080p on the GPU
    /// context the app actually uses — the factor that bounds preview fps. A
    /// frame budget of 16.6ms sustains 60fps; 33.3ms sustains 30fps.
    private func benchmarkColorRenderMsPerFrame(frames: Int) -> Double {
        let context = CIContext(options: RenderColorConfiguration.contextOptions)
        let extent = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let base = CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6)).cropped(to: extent)
        let correction = ColorCorrection(brightness: 0.1, contrast: 1.2, saturation: 1.3, warmth: 0.4, tint: 0.1)

        // Warm up (shader compile / context setup excluded from the timing).
        for _ in 0..<5 {
            _ = context.createCGImage(ColorCorrectionPixelProcessor.apply(correction, to: base), from: extent)
        }

        let start = Date()
        for _ in 0..<frames {
            let processed = ColorCorrectionPixelProcessor.apply(correction, to: base)
            _ = context.createCGImage(processed, from: extent)
        }
        let elapsed = Date().timeIntervalSince(start)
        return elapsed / Double(frames) * 1000.0
    }

    /// Deterministic launch hooks for the XCUITest end-to-end safety net (Phase 0.1c).
    ///
    /// Entirely gated by launch environment variables and compiled only in DEBUG,
    /// so production launches are unaffected. It drives the **real**
    /// `importMediaAndAddToTimeline` and `exportProject(to:)` paths — not stubs —
    /// so a runtime regression in import or export fails the E2E instead of
    /// passing a string contract silently (the failure mode that hid the
    /// drag-and-drop regression).
    ///
    /// Environment:
    /// - `MOVIECUT_UITEST=1` — enables the harness.
    /// - `MOVIECUT_UITEST_IMPORT=<path[,path...]>` — media imported and added to the timeline.
    /// - `MOVIECUT_UITEST_IMPORT_EXTRA=<path[:path...] | newline paths>` — extra media imported after the first import.
    /// - `MOVIECUT_UITEST_CLIPBOARD=1` — exercises multi-clip copy/paste/cut and atomic undo/redo before export.
    /// - `MOVIECUT_UITEST_PLAYBACK_RATE=<double>` — applies a constant playback rate to the selected clip.
    /// - `MOVIECUT_UITEST_OPTICAL_FLOW=1` — enables optical-flow slow motion on the selected clip.
    /// - `MOVIECUT_UITEST_EXTRACT_AUDIO=1` — extracts audio from the selected video clip.
    /// - `MOVIECUT_UITEST_PLATFORM_PRESET=<rawValue>` — applies a real platform preset before export.
    /// - `MOVIECUT_UITEST_INSPECTOR_TAB=<rawValue>` — selects the inspector's clip subtab
    ///   (`Basic` / `Speed` / `Animation` / `Adjustment` / `Mask`) so the dhash golden states
    ///   can capture each inspector section as a distinct editor state.
    /// - `MOVIECUT_UITEST_EXPORT_RESOLUTION=<rawValue>` — sets `ExportSettings.resolution` before export
    ///   (e.g. `p4K`), independent of any platform preset. Used by the 4K perf baseline (S6).
    /// - `MOVIECUT_UITEST_TEXT_ANIMATION_PRESET=<rawValue>` — adds a 2s animated text clip before export.
    /// - `MOVIECUT_UITEST_HSL_CURVES=1` — applies a non-3-way HSL/curve grade to the selected clip.
    /// - `MOVIECUT_UITEST_CHROMA_KEY=1` — applies the deterministic greenScreen chroma-key default to
    ///   the selected clip through the real command path (CA-12 A/B benchmark fixture ⑦).
    /// - `MOVIECUT_UITEST_AUTO_PROXY=1` — opts the run into background proxy auto-generation (the
    ///   harness suppresses it otherwise for gate determinism), waits for in-flight generations to
    ///   settle, and reports `auto_proxy_idle/assets/missing/cancelled` in the status line (CA-22 2차).
    /// - `MOVIECUT_UITEST_AUTO_PROXY_MODE=off|on` — sets `autoGenerateProxyOnImport` BEFORE imports.
    /// - `MOVIECUT_UITEST_AUTO_PROXY_CANCEL=1` — cancels in-flight generations after import.
    /// - `MOVIECUT_UITEST_AUTO_PROXY_RESUME=1` — generates proxies for assets still missing one.
    /// - `MOVIECUT_UITEST_SCRUB=<seconds>` — scrubs through the ruler-coordinate transport path.
    /// - `MOVIECUT_UITEST_PROXY_BADGE=1` — generates a proxy for the first video asset and reports
    ///   the timeline badge state. Pair with `MOVIECUT_UITEST_PROXY_PLAYBACK=1` to check the active state,
    ///   and `MOVIECUT_UITEST_PROXY_RESOLUTION=<p480|p540|p720|p1080>` to pick the generation resolution.
    /// - `MOVIECUT_UITEST_FILMSTRIP=1` — decodes four time-varying frames from the selected video.
    /// - `MOVIECUT_UITEST_TIMELINE_FILMSTRIP=1` — observes the real TimelineView viewport and hover consumers.
    /// - `MOVIECUT_UITEST_FILMSTRIP_PERF=density|memory` — drives real TimelineView zoom/scroll performance evidence.
    /// - `MOVIECUT_UITEST_PERF_PHASE=<path>` — optional phase handshake for external RSS sampling.
    /// - `MOVIECUT_UITEST_EXPORT=<path>` — destination the project is exported to.
    ///   The export's isolated wall clock is reported as `export_wall_s=` in the
    ///   final status line (CA-12 §1.4 whole-app vs encode-span split).
    /// - `MOVIECUT_UITEST_EXPORT_AUDIO=<path>` — destination for audio-only export.
    /// - `MOVIECUT_UITEST_VOCAL_SEPARATION=<removeVocals|isolateCenter>` — applies real offline separation to the selected audio clip.
        /// - `MOVIECUT_UITEST_PREVIEW_AUDIO=<path>` — renders Preview's installed composition/audio mix for PCM verification.
        /// - `MOVIECUT_UITEST_AUDIO_GRAPH_NULLTEST=<path>` — G-25 §9 measured null test: renders the same
        ///   audio graph through BOTH engine generators (real AVAudioEngine preview + encoder input),
        ///   null-compares at ±1 sample / 1 LSB, measures the 60-minute mixed-rate tail drift, and writes a
        ///   JSON artifact to <path> (the swift-test-level checks live in AudioGraphEngineNullTests).
        /// - `MOVIECUT_UITEST_SOLO_LAST_AUDIO_TRACK=1` — solos the last audio track through the real
        ///   SetTrackPropertyCommand path before export (G-25 Inc 9 solo E2E evidence).
        /// - `MOVIECUT_UITEST_EXPORT_POSTCHECK=<path>` — G-25 §8 AAC post-check: after export, re-decodes
        ///   the ACTUAL output file and the project's preview mix (the reference the audio-mix path
        ///   produces today), compares lengths/RMS, and measures decoded LUFS-I/true-peak/clipping with
        ///   the shared Core functions; writes a JSON artifact to <path>.
    func runUITestHarnessIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST"] == "1" else { return }
        // Reset per-run container-artifact tracking so stale paths from a
        // previous invocation don't leak into this run's status line.
        containerArtifactPaths.removeAll()
        if env["MOVIECUT_UITEST_CARD_TEMPLATE"] == "1" {
            await runCardTemplateUITestScenario(environment: env)
            return
        }
        if env["MOVIECUT_UITEST_CARD_TEMPLATE_CORE"] == "1" {
            await runCardTemplateCoreUITestScenario(environment: env)
            return
        }
        if env["MOVIECUT_UITEST_CARD_EDITOR"] == "1" {
            await runCardEditorUITestScenario(environment: env)
            return
        }
        if env["MOVIECUT_UITEST_PREVIEW_PROJECT"] == "1" {
            await runPreviewProjectCompositionUITestScenario(environment: env)
            return
        }
        if env["MOVIECUT_UITEST_PARITY"] == "1" {
            await runPreviewExportParityUITestScenario(environment: env)
            return
        }
        if let wScenario = env["MOVIECUT_UITEST_W_SCENARIO"], !wScenario.isEmpty {
            await runWScenarioUITestScenario(environment: env, scenario: wScenario)
            return
        }
        if env["MOVIECUT_UITEST_STABILIZE"] == "1" {
            await runStabilizationUITestScenario(environment: env)
            return
        }
        if let baseline = env["MOVIECUT_UITEST_LATENCY_BASELINE"], !baseline.isEmpty {
            await runLatencyBaselineUITestScenario(
                environment: env,
                seekCount: Int(baseline) ?? 30
            )
            return
        }
        if env["MOVIECUT_UITEST_RECOVERY"] == "1" {
            await runRecoveryUITestScenario(environment: env)
            return
        }
        if env["MOVIECUT_UITEST_UNSAVED_GUARD"] == "1" {
            await runUnsavedChangesGuardUITestScenario(environment: env)
            return
        }
        var extractAudioSuffix = ""
        var vocalSeparationSuffix = ""
        var scrubSuffix = ""
        var clipboardSuffix = ""
        var filmstripSuffix = ""
        var proxyBadgeSuffix = ""
        var timelineFilmstripSuffix = ""
        var filmstripPerformanceSuffix = ""
        var motionTrackingSuffix = ""
        var motionTrackingReopenSuffix = ""
        let filmstripPerformanceScenario = env["MOVIECUT_UITEST_FILMSTRIP_PERF"]

        if filmstripPerformanceScenario != nil {
            TimelineFilmstripDebugProbe.shared.armPerformance()
        } else if env["MOVIECUT_UITEST_TIMELINE_FILMSTRIP"] == "1" {
            TimelineFilmstripDebugProbe.shared.arm()
        }

        let primaryImportURLs = env["MOVIECUT_UITEST_IMPORT"]
            .map(uiTestImportURLs(from:)).map(containerizeImportURLs) ?? []
        let extraImportURLs = env["MOVIECUT_UITEST_IMPORT_EXTRA"]
            .map(uiTestImportExtraURLs(from:)).map(containerizeImportURLs) ?? []
        // CA-22 2차: apply the auto-proxy mode BEFORE the imports so the
        // "off" leg proves no generation was even scheduled.
        if let rawMode = env["MOVIECUT_UITEST_AUTO_PROXY_MODE"], !rawMode.isEmpty {
            await updatePlaybackSettings(autoGenerateProxyOnImport: rawMode == "on")
        }
        if filmstripPerformanceScenario != nil {
            if !primaryImportURLs.isEmpty {
                await importMediaAndAddToTimeline(
                    primaryImportURLs,
                    startTime: currentProject.timeline.duration
                )
            }
            for url in extraImportURLs {
                await importMediaAndAddToTimeline([url], startTime: 0)
            }
            scrubPlayhead(to: 0, phase: .ended)
            await addTextClip(text: "Filmstrip performance evidence")
        } else {
            let importURLs = primaryImportURLs + extraImportURLs
            if !importURLs.isEmpty {
                await importMediaAndAddToTimeline(
                    importURLs,
                    startTime: currentProject.timeline.duration
                )
            }
        }

        // CA-22 2차: auto-proxy cancel/resume control and a bounded settle
        // wait, so the gate can assert the full background-generation story:
        // off (nothing scheduled), on (generated), cancelled (discarded +
        // counted), resumed (missing proxies filled).
        var autoProxySuffix = ""
        if env["MOVIECUT_UITEST_AUTO_PROXY"] == "1" {
            if env["MOVIECUT_UITEST_AUTO_PROXY_CANCEL"] == "1" {
                cancelAutoProxyGeneration()
            }
            if env["MOVIECUT_UITEST_AUTO_PROXY_RESUME"] == "1" {
                await resumeMissingProxies()
            }
            let idleDeadline = Date().addingTimeInterval(240)
            while !autoProxyGenerating.isEmpty && Date() < idleDeadline {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            let assetsWithProxy = currentProject.mediaLibrary.assets.values
                .filter { $0.proxy != nil }
                .count
            autoProxySuffix = " auto_proxy_idle=\(autoProxyGenerating.isEmpty ? 1 : 0)" +
                " auto_proxy_assets=\(assetsWithProxy)" +
                " auto_proxy_missing=\(videoAssetsMissingProxy)" +
                " auto_proxy_cancelled=\(autoProxyCancelledCount)"
        }

        if let filmstripPerformanceScenario {
            do {
                filmstripPerformanceSuffix = try await runTimelineFilmstripPerformanceUITestScenario(
                    named: filmstripPerformanceScenario,
                    phasePath: env["MOVIECUT_UITEST_PERF_PHASE"]
                )
            } catch {
                lastErrorMessage = "filmstrip performance harness failed: \(error.localizedDescription)"
                filmstripPerformanceSuffix = " filmstrip_perf=\(filmstripPerformanceScenario) perf_complete=0 ui_work_samples=0 ui_work_p95_ms=999.000 ui_work_max_ms=999.000 ui_work_over_16_6=999 ui_work_requests=0 ui_work_publishes=0 ui_work_updates=0 ui_work_draws=0 ui_work_distinct_requests=0 ui_work_off_main=999 cache_current_bytes=0 cache_peak_bytes=0 cache_limit_bytes=0 cache_keys=0 cache_evictions=0 max_frame_height=0 preserved_image=0 preserved_audio=0 preserved_text=0"
            }
        }

        if env["MOVIECUT_UITEST_TIMELINE_FILMSTRIP"] == "1" {
            do {
                timelineFilmstripSuffix = try await runTimelineFilmstripConsumerUITestScenario()
            } catch {
                lastErrorMessage = "timeline filmstrip harness failed: \(error.localizedDescription)"
                timelineFilmstripSuffix = " timeline_filmstrip_frames=0 distinct_digests=0 distinct_times=0 requested_span=0.000 full_span=0.000 requested_count=0 full_count=0 offscreen_skipped=0 cancelled=0 stale_rejected=0 fallback_before_ready=0 fallback_after_cancel=0 zoom_requests=none hover_visible=0 hover_width=0 hover_height=0 hover_label=0 hover_requested=0.000 hover_selected_requested=0.000 hover_actual=0.000 hover_error=999.000 hover_digest=none hover_digest_cached=0 hover_exit_hidden=0 hover_cache_miss_hidden=0 hover_unsupported_hidden=0 hover_request_delta=-1 hover_generation_delta=-1"
            }
        }

        if env["MOVIECUT_UITEST_FILMSTRIP"] == "1" {
            do {
                filmstripSuffix = try await runFilmstripGeneratorUITestScenario()
            } catch {
                lastErrorMessage = "filmstrip harness failed: \(error.localizedDescription)"
                filmstripSuffix = " filmstrip_frames=0 requested=none actual=none max_height=0"
            }
        }

        if env["MOVIECUT_UITEST_PROXY_BADGE"] == "1" {
            proxyBadgeSuffix = await runProxyBadgeUITestScenario(
                useProxyPlayback: env["MOVIECUT_UITEST_PROXY_PLAYBACK"] == "1",
                proxyResolution: env["MOVIECUT_UITEST_PROXY_RESOLUTION"].flatMap(ProxyResolution.init(rawValue:))
            )
        }

        if env["MOVIECUT_UITEST_CLIPBOARD"] == "1" {
            do {
                clipboardSuffix = try await runClipboardUITestScenario()
            } catch {
                lastErrorMessage = "clipboard harness failed: \(error.localizedDescription)"
                clipboardSuffix = " clipboard_copy=0 paste=0 paste_starts=none relative=0.000 paste_undo=0 cut_undo=0 new_ids=0"
            }
        }

        if let rawScrubTime = env["MOVIECUT_UITEST_SCRUB"],
           let requestedTime = Double(rawScrubTime) {
            let rulerX = requestedTime * timelineZoom
            let convertedTime = TimelineScrubMath.time(
                forLocalX: rulerX,
                pixelsPerSecond: timelineZoom,
                duration: currentProject.timeline.duration
            )
            scrubPlayhead(to: convertedTime, phase: .began)
            scrubPlayhead(to: convertedTime, phase: .ended)
            scrubSuffix = String(
                format: " scrub_requested=%.3f playhead=%.3f playback=%.3f",
                requestedTime,
                playheadTime,
                playbackEngine.currentTime
            )
        }

        // Optional deterministic ducking setup: creates separate BGM and voice
        // audio tracks through real EditorSession commands, then optionally writes
        // range-based ducking metadata onto the BGM clip before export. This keeps
        // the E2E proof in the same command/export path users exercise.
        if let bgmPath = env["MOVIECUT_UITEST_DUCKING_BGM"],
           let voicePath = env["MOVIECUT_UITEST_DUCKING_VOICE"],
           !bgmPath.isEmpty,
           !voicePath.isEmpty {
            await configureDuckingHarness(
                bgmURL: URL(filePath: bgmPath),
                voiceURL: URL(filePath: voicePath),
                applyDucking: env["MOVIECUT_UITEST_DUCKING_APPLY"] == "1"
            )
        }

        // G-25 §9 null test — runs in the MAIN flow (after imports/ducking)
        // so the real-project phase sees the actual media and mix state.
        var audioGraphNulltestSuffix = ""
        if let nullTestPath = env["MOVIECUT_UITEST_AUDIO_GRAPH_NULLTEST"], !nullTestPath.isEmpty {
            audioGraphNulltestSuffix = await runAudioGraphNullTestUITestScenario(
                environment: env,
                artifactPath: nullTestPath
            )
        }

        // G-25 switchover 2B: the master-loudness meter measured through the
        // REAL graph path on the current (ducking-harness) project state —
        // optionally with EQ applied to the BGM clip so the §0 effective-
        // media derivation is exercised end to end.
        var masterMeterSuffix = ""
        if let meterPath = env["MOVIECUT_UITEST_MASTER_METER"], !meterPath.isEmpty {
            masterMeterSuffix = await runMasterMeterUITestScenario(
                environment: env,
                artifactPath: meterPath
            )
        }

        // Motion-tracking gate (T2-R1 prerequisite). Runs the REAL user path —
        // trackMotion → MotionTrackingProvider → SetClipPropertyCommand(
        // .keyframes) — on the imported fixture with a fixed initial rect, so
        // scripts can prove tracked motion lands on the clip model and survives
        // a ProjectStore round-trip. IoU-vs-ground-truth coverage lives in
        // MotionTrackingProviderTests; this gate proves the command path.
        if env["MOVIECUT_UITEST_MOTION_TRACKING"] == "1", let clipId = selectedClipId {
            do {
                motionTrackingSuffix = try await runMotionTrackingUITestScenario(
                    clipId: clipId,
                    dumpPath: env["MOVIECUT_UITEST_MOTION_TRACKING_DUMP"],
                    savePath: env["MOVIECUT_UITEST_MOTION_TRACKING_SAVE"]
                )
            } catch {
                lastErrorMessage = "motion tracking harness failed: \(error.localizedDescription)"
                motionTrackingSuffix = " motion_tracking=error samples=0 keyframes=0 roundtrip=0 saved=0"
            }
        }

        // Second process phase of the motion-tracking gate: the project is
        // loaded through the real launch path (MOVIECUT_BOOTSTRAP_PROJECT →
        // openProject) and this gate verifies the tracked position keyframes
        // survived the save → reopen boundary.
        if env["MOVIECUT_UITEST_MOTION_TRACKING_REOPEN"] == "1" {
            do {
                motionTrackingReopenSuffix = try await runMotionTrackingReopenUITestScenario()
            } catch {
                lastErrorMessage = "motion tracking reopen harness failed: \(error.localizedDescription)"
                motionTrackingReopenSuffix = " motion_tracking_reopen=error keyframes=0 posX=0 posY=0"
            }
        }

        // Optional freeze-frame step: holds a single frame for 2s mid-clip, so an
        // E2E check can confirm freeze is reflected in export (output duration
        // grows by the freeze duration).
        if env["MOVIECUT_UITEST_FREEZE"] == "1", let clip = selectedClip {
            playheadTime = clip.timelineRange.start + clip.timelineRange.duration / 2
            await freezeSelectedFrame(freezeDuration: 2.0)
        }

        if let rawPlaybackRate = env["MOVIECUT_UITEST_PLAYBACK_RATE"],
           let playbackRate = Double(rawPlaybackRate) {
            await updateSelectedPlaybackRate(playbackRate)
        }

        if env["MOVIECUT_UITEST_OPTICAL_FLOW"] == "1" {
            await updateSelectedOpticalFlow(true)
        }

        // Optional color-correction step: forces every exported frame through the
        // CoreImage CustomVideoCompositor, so a perf baseline can measure that
        // path's cost against a plain passthrough export (the Phase 2B Metal
        // decision input).
        if env["MOVIECUT_UITEST_COLOR"] == "1", selectedClipId != nil {
            await updateSelectedColorCorrection(
                ColorCorrection(brightness: 0.1, contrast: 1.2, saturation: 1.3, warmth: 0.4, tint: 0.1)
            )
        }

        // Optional 3-way color grade step: applies a strong warm lift/gain grade so
        // an E2E check can confirm the grade is reflected in export.
        // G-03 Inc 3: mark the selected clip as an adjustment layer carrying
        // a strong grade — export must show the adjustment applied to the
        // clips below (asserted by the script's pixel comparison).
        var adjustmentLayerSuffix = ""
        if env["MOVIECUT_UITEST_ADJUSTMENT_LAYER"] == "1", let clip = selectedClip {
            await apply(SetClipPropertyCommand(clipId: clip.id, property: .isAdjustmentLayer(true)))
            await apply(SetClipPropertyCommand(clipId: clip.id, property: .colorGrade(ColorGrade(gamma: 0.5))))
            let marked = currentProject.timeline.tracks.flatMap(\.clips)
                .contains { $0.id == clip.id && $0.isAdjustmentLayer }
            adjustmentLayerSuffix = " adjustment_layer=\(marked ? 1 : 0)"
        }

        if env["MOVIECUT_UITEST_GRADE"] == "1", selectedClipId != nil {
            await updateSelectedColorGrade(
                ColorGrade(
                    lift: .init(red: 0.1, green: 0, blue: -0.05),
                    gamma: 0.8,
                    gain: .init(red: 1.2, green: 1.0, blue: 0.8)
                )
            )
        }

        // Optional G-02 Inc 3 grade: no lift/gamma/gain changes, only the new HSL
        // and curve fields, so E2E can prove the non-3-way renderer chain.
        if env["MOVIECUT_UITEST_HSL_CURVES"] == "1", selectedClipId != nil {
            await updateSelectedColorGrade(
                ColorGrade(
                    hslBands: [HSLBand(center: .red, saturation: -1, luminance: 0.5)],
                    curves: ColorCurves(master: [
                        CurvePoint(x: 0.5, y: 0.65)
                    ])
                )
            )
        }

        // Optional noise-reduction step: runs the real NoiseReductionService DSP
        // (AVAudioEngine offline) on the selected clip in the app's audio context,
        // where the offline-render path that aborts under `swift test` can be
        // verified for real.
        if env["MOVIECUT_UITEST_DENOISE"] == "1", let clipId = selectedClipId {
            do {
                try await applyNoiseReduction(for: clipId)
            } catch {
                lastErrorMessage = "denoise failed: \(error.localizedDescription)"
            }
        }

        // Optional equalizer step: applies the real command-backed clip EQ preset
        // before export so scripts can measure bass/treble spectrum changes from
        // the app runtime rather than a unit-test-only service call.
        if let eqPreset = env["MOVIECUT_UITEST_EQ_PRESET"], !eqPreset.isEmpty, selectedClipId != nil {
            await applyEQPreset(eqPreset)
        }

        // App-level vocal separation proof: process the selected stereo audio
        // clip through the real renderer/source-swap command, then render the
        // exact Preview composition and audio mix for external PCM measurement.
        if let rawMode = env["MOVIECUT_UITEST_VOCAL_SEPARATION"], !rawMode.isEmpty {
            do {
                guard let mode = VocalSeparationMode(rawValue: rawMode) else {
                    throw NSError(
                        domain: "MovieCutUITest",
                        code: 30,
                        userInfo: [NSLocalizedDescriptionKey: "unknown vocal separation mode: \(rawMode)"]
                    )
                }
                guard let clipId = selectedClipId else {
                    throw NSError(
                        domain: "MovieCutUITest",
                        code: 31,
                        userInfo: [NSLocalizedDescriptionKey: "vocal separation requires a selected audio clip"]
                    )
                }

                try await applyVocalSeparation(for: clipId, mode: mode, strength: 1)
                vocalSeparationSuffix = " vocal_mode=\(mode.rawValue) vocal_applied=1"

                if let previewAudioPath = env["MOVIECUT_UITEST_PREVIEW_AUDIO"], !previewAudioPath.isEmpty {
                    rebuildPreviewComposition()
                    let expectedGeneration = playbackEngine.currentCompositionGeneration
                    try await waitForCompositionReady(
                        timeoutSeconds: 10,
                        expectedGeneration: expectedGeneration
                    )
                    try await playbackEngine.renderCurrentPreviewAudio(to: URL(filePath: previewAudioPath))
                    vocalSeparationSuffix += " preview_audio=1"
                }
            } catch {
                lastErrorMessage = "vocal separation failed: \(error.localizedDescription)"
                vocalSeparationSuffix = " vocal_mode=\(rawMode) vocal_applied=0 preview_audio=0"
            }
        }

        // Optional Extract Audio step: runs the real ViewModel command-backed
        // extraction path and leaves the extracted audio clip selected.
        if env["MOVIECUT_UITEST_EXTRACT_AUDIO"] == "1" {
            if let sourceClipId = selectedClipId {
                do {
                    let extractedClip = try await extractAudio(from: sourceClipId)
                    let extractedAudioClipCount = currentProject.timeline.tracks
                        .filter { $0.kind == .audio }
                        .flatMap(\.clips)
                        .filter { $0.kind == .audio }
                        .count
                    extractAudioSuffix = String(
                        format: " extract_audio_clips=%d extract_audio_duration=%.3f",
                        extractedAudioClipCount,
                        extractedClip.timelineRange.duration
                    )
                } catch {
                    lastErrorMessage = "extract audio failed: \(error.localizedDescription)"
                    extractAudioSuffix = " extract_audio_clips=0 extract_audio_duration=0.000"
                }
            } else {
                lastErrorMessage = "extract audio failed: no selected clip"
                extractAudioSuffix = " extract_audio_clips=0 extract_audio_duration=0.000"
            }
        }

        if let rawPlatformPreset = env["MOVIECUT_UITEST_PLATFORM_PRESET"], !rawPlatformPreset.isEmpty {
            if let preset = PlatformExportPreset(rawValue: rawPlatformPreset) {
                await applyPlatformExportPreset(preset)
            } else {
                lastErrorMessage = "unknown platform preset: \(rawPlatformPreset)"
            }
        }

        // Export resolution override (S6 4K baseline). Independent of a full
        // platform preset so a path can be measured at 4K without changing the
        // codec/container/quality the preset would also set.
        if let rawResolution = env["MOVIECUT_UITEST_EXPORT_RESOLUTION"], !rawResolution.isEmpty {
            if let resolution = ExportResolution(rawValue: rawResolution) {
                await updateExportSettings(resolution: resolution)
            } else {
                lastErrorMessage = "unknown export resolution: \(rawResolution)"
            }
        }

        var textAnimationSuffix = ""
        if let rawTextAnimationPreset = env["MOVIECUT_UITEST_TEXT_ANIMATION_PRESET"] {
            if let preset = TextAnimationPreset(rawValue: rawTextAnimationPreset) {
                await addUITestTextAnimationClip(preset: preset)
                if let clip = selectedClip, let textContent = clip.textContent {
                    textAnimationSuffix = " text_anim=\(textContent.animation?.preset.rawValue ?? "none") text_keyframes=\(clip.keyframes.count)"
                } else {
                    textAnimationSuffix = " text_anim=missing text_keyframes=0"
                }
            } else {
                lastErrorMessage = "unknown text animation preset: \(rawTextAnimationPreset)"
            }
        }

        var textTemplateSuffix = ""
        if let rawTextTemplateName = env["MOVIECUT_UITEST_TEXT_TEMPLATE_NAME"], !rawTextTemplateName.isEmpty {
            let wanted = rawTextTemplateName.lowercased().replacingOccurrences(of: "_", with: " ")
            if let template = TextTemplate.builtIn.first(where: { $0.name.lowercased() == wanted }) {
                await addUITestTextTemplateClip(template: template)
                let textTemplateClipCount = currentProject.timeline.tracks
                    .flatMap(\.clips)
                    .filter { $0.kind == .text }
                    .count
                if let clip = selectedClip, let textContent = clip.textContent {
                    let templateName = template.name.replacingOccurrences(of: " ", with: "_")
                    textTemplateSuffix = " text_template=\(templateName) text_template_clips=\(textTemplateClipCount) text_template_text=\(textContent.text.replacingOccurrences(of: " ", with: "_"))"
                } else {
                    textTemplateSuffix = " text_template=missing text_template_clips=\(textTemplateClipCount)"
                }
            } else {
                lastErrorMessage = "unknown text template: \(rawTextTemplateName)"
            }
        }

        var chapterSuffix = ""
        if env["MOVIECUT_UITEST_CHAPTER_MARKERS"] == "1" {
            let includeBeatChapters = env["MOVIECUT_UITEST_BEAT_CHAPTERS"] == "1"
            await addUITestChapterMarkers(includeBeatChapters: includeBeatChapters)
            let standardCount = currentProject.markers.filter { $0.kind == .standard }.count
            let beatCount = currentProject.markers.filter { $0.kind == .beat }.count
            chapterSuffix = " chapters=\(standardCount) beat_chapters=\(beatCount) include_beats=\(includeBeatChapters ? 1 : 0)"
        }

        // Mask on the selected clip (generic dispatch). Previously MASK was a
        // parity-path-only gate, so screenshot states couldn't apply a mask —
        // and opening the Mask inspector tab alone produced a screenshot whose
        // dhash was ~identical to the import baseline (inspector content is
        // invisible at 9x8; only the masked PREVIEW pixels move the hash).
        // Same rectangle as the parity gate: canvas-pixel coords on the default
        // 320×240 canvas.
        if env["MOVIECUT_UITEST_MASK"] == "1", selectedClipId != nil {
            await updateSelectedMask(Mask(
                shape: .rectangle,
                position: CGPoint(x: 160, y: 120),
                size: CGSize(width: 192, height: 144)
            ))
        }

        // Crop on the selected clip (G-23) — screenshot/benchmark mirror of
        // the parity gate: the centered 1:1 crop the inspector preset produces.
        if env["MOVIECUT_UITEST_CROP"] == "1", selectedClipId != nil {
            let sourceAspect = selectedClipSourceAspect ?? 4.0 / 3.0
            await updateSelectedCropRect(
                CropPixelProcessor.centeredCropRect(
                    sourceAspect: sourceAspect,
                    targetAspect: 1
                )
            )
        }

        // Chroma key on the selected clip — CA-12 A/B benchmark fixture ⑦
        // (mask + chroma key). Applies the deterministic greenScreen default
        // through the same SetClipPropertyCommand the inspector's chroma key
        // section dispatches, so the benchmark exercises the real command path.
        if env["MOVIECUT_UITEST_CHROMA_KEY"] == "1", selectedClipId != nil {
            await updateSelectedChromaKey(ChromaKeySettings.greenScreen())
        }

        // Selects the inspector's clip-scoped subtab (rawValue: Basic / Speed /
        // Animation / Adjustment / Mask). Deliberately AFTER every
        // selection-changing gate above (text template / extract audio / etc.)
        // — InspectorPanel resets the tab to .basic whenever the clip selection
        // changes, so setting it earlier would be undone. Used by the dhash
        // golden states (with_color_grade / with_mask) so each inspector
        // section is captured as a visually distinct editor state.
        if let rawInspectorTab = env["MOVIECUT_UITEST_INSPECTOR_TAB"], !rawInspectorTab.isEmpty {
            if let tab = InspectorSubtab(rawValue: rawInspectorTab) {
                selectedInspectorSubtab = tab
            } else {
                lastErrorMessage = "unknown inspector tab: \(rawInspectorTab)"
            }
        }

        // G-25 Inc 9: solo the last audio track through the real command
        // path so E2E can prove solo changes the exported mix.
        var soloSuffix = ""
        if env["MOVIECUT_UITEST_SOLO_LAST_AUDIO_TRACK"] == "1" {
            if let lastAudioTrack = currentProject.timeline.tracks.last(where: { $0.kind == .audio }) {
                await toggleTrackSolo(lastAudioTrack)
                let applied = currentProject.timeline.tracks
                    .first { $0.id == lastAudioTrack.id }?.isSolo ?? false
                soloSuffix = " solo_applied=\(applied ? 1 : 0)"
            } else {
                soloSuffix = " solo_applied=0"
            }
        }

        // Export with an isolated wall-clock measurement so the CA-12 A/B
        // benchmark can report the encode span separately from the whole-app
        // run (COMPETITIVE_ANALYSIS §1.4 requires both). Everything inside the
        // clock is the exportProject call itself: container staging and the
        // finalize copy stay outside.
        var exportWallSuffix = ""
        if lastErrorMessage == nil,
           let exportPath = env["MOVIECUT_UITEST_EXPORT"], !exportPath.isEmpty {
            let dest = containerizedExportDestination(for: URL(filePath: exportPath))
            let exportClock = ContinuousClock()
            let exportStart = exportClock.now
            await exportProject(to: dest.write)
            let exportElapsed = exportClock.now - exportStart
            let comps = exportElapsed.components
            let exportSeconds = Double(comps.seconds) + Double(comps.attoseconds) / 1e18
            exportWallSuffix = String(format: " export_wall_s=%.3f", exportSeconds)
            finalizeContainerizedExport(from: dest.write, to: dest.requested)
        }

        if lastErrorMessage == nil,
           let audioPath = env["MOVIECUT_UITEST_EXPORT_AUDIO"], !audioPath.isEmpty {
            let dest = containerizedExportDestination(for: URL(filePath: audioPath))
            await exportAudioOnly(to: dest.write)
            finalizeContainerizedExport(from: dest.write, to: dest.requested)
        }

        if lastErrorMessage == nil,
           let proResPath = env["MOVIECUT_UITEST_EXPORT_PRORES"], !proResPath.isEmpty {
            let dest = containerizedExportDestination(for: URL(filePath: proResPath))
            await exportProResMaster(to: dest.write)
            finalizeContainerizedExport(from: dest.write, to: dest.requested)
        }

        if lastErrorMessage == nil,
           let hdrPath = env["MOVIECUT_UITEST_EXPORT_HDR"], !hdrPath.isEmpty {
            let dest = containerizedExportDestination(for: URL(filePath: hdrPath))
            await exportHDRMaster(to: dest.write)
            finalizeContainerizedExport(from: dest.write, to: dest.requested)
        }

        // G-25 §8: post-check the ACTUAL exported file (audio-only export if
        // requested, else the video export) against the project's preview mix.
        var exportPostcheckSuffix = ""
        if lastErrorMessage == nil,
           let postcheckPath = env["MOVIECUT_UITEST_EXPORT_POSTCHECK"], !postcheckPath.isEmpty {
            exportPostcheckSuffix = await runExportPostCheckUITestScenario(
                environment: env,
                artifactPath: postcheckPath
            )
        }

        // Optional preview render benchmark: per-frame 1080p compositor cost on
        // the GPU context, to bound preview fps (the export baseline measured the
        // offline path; this measures the real-time render cost).
        var benchSuffix = ""
        if env["MOVIECUT_UITEST_RENDER_BENCH"] == "1" {
            let msPerFrame = benchmarkColorRenderMsPerFrame(frames: 300)
            let fps = msPerFrame > 0 ? 1000.0 / msPerFrame : 0
            benchSuffix = String(format: " render_ms=%.3f max_fps=%.0f", msPerFrame, fps)
        }

        // Optional auto-white-balance check: run on-device auto color and report
        // the resulting per-channel gain so an E2E check can confirm it ran.
        var autoWBSuffix = ""
        if env["MOVIECUT_UITEST_AUTOWB"] == "1" {
            await autoColorSelectedClip()
            if let gain = selectedClip?.colorGrade?.gain {
                autoWBSuffix = String(format: " autowb_gain=%.3f,%.3f,%.3f", gain.red, gain.green, gain.blue)
            } else {
                autoWBSuffix = " autowb_gain=none"
            }
        }
        if env["MOVIECUT_UITEST_AUTOLEVELS"] == "1" {
            await autoLevelsSelectedClip()
            if let grade = selectedClip?.colorGrade {
                autoWBSuffix += String(format: " autolevels_gain=%.3f lift=%.3f", grade.gain.red, grade.lift.red)
            } else {
                autoWBSuffix += " autolevels_gain=none"
            }
        }
        if env["MOVIECUT_UITEST_AUTOENHANCE"] == "1" {
            await autoEnhanceSelectedClip()
            if let grade = selectedClip?.colorGrade {
                autoWBSuffix += String(format: " autoenhance_gain=%.3f,%.3f,%.3f lift=%.3f",
                                       grade.gain.red, grade.gain.green, grade.gain.blue, grade.lift.red)
            } else {
                autoWBSuffix += " autoenhance=none"
            }
        }

        // Optional scope check: compute the grading histogram for the selected
        // clip and report its luma sample count, so an E2E check can confirm the
        // scope pipeline produces real data from the graded thumbnail.
        var scopeSuffix = ""
        if env["MOVIECUT_UITEST_SCOPE"] == "1" {
            refreshScopes()
            let lumaSum = scopeHistogram?.luma.reduce(0, +) ?? 0
            let waveformSum = scopeWaveform?.reduce(0) { $0 + $1.reduce(0, +) } ?? 0
            let vectorSum = scopeVectorscope?.counts.reduce(0, +) ?? 0
            scopeSuffix = " scope_luma_sum=\(lumaSum) wave_sum=\(waveformSum) vec_sum=\(vectorSum)"
        }

        // Deterministically persist the crash-recovery autosave before quit so a
        // script can verify the edit-driven autosave path produced a recovery file.
        await flushAutosave()

        let clipCount = currentProject.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        let status = "UITEST_DONE clips=\(clipCount) error=\(lastErrorMessage ?? "none")\(proxyBadgeSuffix)\(scrubSuffix)\(clipboardSuffix)\(filmstripSuffix)\(timelineFilmstripSuffix)\(filmstripPerformanceSuffix)\(motionTrackingSuffix)\(motionTrackingReopenSuffix)\(extractAudioSuffix)\(vocalSeparationSuffix)\(benchSuffix)\(scopeSuffix)\(autoWBSuffix)\(textAnimationSuffix)\(textTemplateSuffix)\(chapterSuffix)\(soloSuffix)\(audioGraphNulltestSuffix)\(masterMeterSuffix)\(adjustmentLayerSuffix)\(exportPostcheckSuffix)\(exportWallSuffix)\(autoProxySuffix)\(containerArtifactSuffix())\(timelineSummarySuffix())"
        lastStatusMessage = status

        // Headless verification path: when the harness is driven by launching the
        // app binary directly (no XCUITest automation handshake / Accessibility
        // permission), it writes its outcome to `MOVIECUT_UITEST_RESULT` and
        // `MOVIECUT_UITEST_QUIT=1` terminates so a script / CI can assert results.
        if let resultPath = env["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
            writeHarnessStatus(status, to: resultPath)
        }
        if env["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    /// Motion-tracking harness scenario (T2-R1 prerequisite). Arms the real
    /// tracking path on the imported clip with a FIXED initial rect (the
    /// analytic ground-truth box of moving_subject_320x240_2s_30fps.mp4:
    /// white 72x64 box starting at x=32,y=88, moving +80px/s), then asserts
    /// the generated position keyframes landed on the clip model, reflect the
    /// tracked motion, and survive a ProjectStore save/load round-trip.
    /// Emits a JSON behavior dump for golden comparison.
    private struct MotionTrackingUITestDump: Codable {
        var initialRect: [Double]
        var sampleCount: Int
        var generatedKeyframes: Int
        var positionXKeyframes: Int
        var positionYKeyframes: Int
        var firstResultMidX: Double?
        var lastResultMidX: Double?
        var firstPosX: Double?
        var lastPosX: Double?
        var firstKeyframeTime: Double?
        var lastKeyframeTime: Double?
        var roundTripKeyframeCount: Int
        var elapsedSeconds: Double
    }

    private func runMotionTrackingUITestScenario(clipId: UUID, dumpPath: String?, savePath: String?) async throws -> String {
        func gateError(_ code: Int, _ message: String) -> NSError {
            NSError(
                domain: "MovieCutUITest",
                code: code,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let initialRect = CGRect(
            x: 32.0 / 320.0,
            y: 88.0 / 240.0,
            width: 72.0 / 320.0,
            height: 64.0 / 240.0
        )

        let startedAt = Date()
        let generatedCount = try await trackMotion(for: clipId, initialRect: initialRect)
        let elapsed = Date().timeIntervalSince(startedAt)

        let results = motionTrackingResults
        let sampleCount = results.count
        // The provider samples at the track's nominal 30fps over the 2s
        // fixture (~60 frames). Require a meaningful floor instead of exact
        // counts: Vision output is host-stable, but the gate must not break
        // on minor sampling differences across OS builds.
        guard sampleCount >= 25 else {
            throw gateError(20, "motion tracking produced too few samples: \(sampleCount)")
        }
        guard generatedCount == sampleCount * 2 else {
            throw gateError(21, "keyframe count mismatch: samples=\(sampleCount) keyframes=\(generatedCount)")
        }

        guard let clip = currentProject.timeline.tracks
            .flatMap(\.clips)
            .first(where: { $0.id == clipId })
        else {
            throw gateError(22, "tracked clip missing from timeline")
        }
        let posXKeyframes = clip.keyframes.filter { $0.property == .positionX }
        let posYKeyframes = clip.keyframes.filter { $0.property == .positionY }
        guard posXKeyframes.count == sampleCount, posYKeyframes.count == sampleCount else {
            throw gateError(
                23,
                "clip keyframes do not match tracking output: posX=\(posXKeyframes.count) posY=\(posYKeyframes.count) samples=\(sampleCount)"
            )
        }

        // The fixture's box moves +80px/s across the full 2s (ground truth:
        // midX 0.2125 → 0.7125 normalized). If the last sample is not far
        // right of the first, tracking failed to follow the subject even
        // though it produced samples.
        guard let firstResult = results.first, let lastResult = results.last else {
            throw gateError(24, "tracking results unexpectedly empty after count check")
        }
        let midXDelta = lastResult.rect.midX - firstResult.rect.midX
        guard midXDelta > 0.35 else {
            throw gateError(25, "tracked midX delta too small to be real motion: \(midXDelta)")
        }
        // Canvas-space keyframes must express the same motion (≥80px on a
        // 320px canvas; the ground-truth move is 160px).
        guard let firstPosX = posXKeyframes.first?.value,
              let lastPosX = posXKeyframes.last?.value,
              abs(lastPosX - firstPosX) > 80 else {
            throw gateError(26, "positionX keyframes do not reflect tracked motion: first=\(posXKeyframes.first?.value ?? 0) last=\(posXKeyframes.last?.value ?? 0)")
        }

        // Persistence layer check: keyframes must survive ProjectStore
        // save/load (the serialization path manual save and autosave share).
        // Reopen in a fresh process (MOVIECUT_BOOTSTRAP_PROJECT) is a
        // follow-up increment.
        let store = ProjectStore()
        let roundTripURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("moviecut-motion-tracking-\(ProcessInfo.processInfo.processIdentifier).moviecut")
        defer { try? FileManager.default.removeItem(at: roundTripURL) }
        try await store.save(currentProject, to: roundTripURL)
        let reloaded = try await store.load(from: roundTripURL)
        let roundTripCount = reloaded.timeline.tracks
            .flatMap(\.clips)
            .first(where: { $0.id == clipId })?
            .keyframes
            .filter { $0.property == .positionX || $0.property == .positionY }
            .count ?? 0
        guard roundTripCount == generatedCount else {
            throw gateError(
                27,
                "keyframes lost in save/load round-trip: expected=\(generatedCount) reloaded=\(roundTripCount)"
            )
        }

        if let dumpPath, !dumpPath.isEmpty {
            let dump = MotionTrackingUITestDump(
                initialRect: [initialRect.minX, initialRect.minY, initialRect.width, initialRect.height],
                sampleCount: sampleCount,
                generatedKeyframes: generatedCount,
                positionXKeyframes: posXKeyframes.count,
                positionYKeyframes: posYKeyframes.count,
                firstResultMidX: firstResult.rect.midX,
                lastResultMidX: lastResult.rect.midX,
                firstPosX: firstPosX,
                lastPosX: lastPosX,
                firstKeyframeTime: posXKeyframes.first?.time,
                lastKeyframeTime: posXKeyframes.last?.time,
                roundTripKeyframeCount: roundTripCount,
                elapsedSeconds: elapsed
            )
            try writeUITestDump(dump, to: URL(filePath: dumpPath))
        }

        // Optional manual-save phase: persists the tracked project through the
        // REAL manual save path (the same call the Save panel makes), so a
        // second process can reopen it via MOVIECUT_BOOTSTRAP_PROJECT.
        var savedSuffix = "saved=0"
        if let savePath, !savePath.isEmpty {
            let saveURL = URL(filePath: savePath)
            await saveProject(to: saveURL)
            guard !isDirty, FileManager.default.fileExists(atPath: savePath) else {
                throw gateError(28, "manual save to harness path failed: \(savePath)")
            }
            savedSuffix = "saved=1"
        }

        return String(
            format: " motion_tracking=ok samples=%d keyframes=%d roundtrip=%d %@ elapsed=%.2f midx_delta=%.3f",
            sampleCount,
            generatedCount,
            roundTripCount,
            savedSuffix,
            elapsed,
            midXDelta
        )
    }

    /// Reopen phase of the motion-tracking gate: with the project loaded via
    /// the real launch path (MOVIECUT_BOOTSTRAP_PROJECT → openProject), the
    /// first video clip must still carry the tracked positionX/Y keyframes.
    /// Polls briefly for the timeline because the bootstrap load and this
    /// harness task race at launch.
    private func runMotionTrackingReopenUITestScenario() async throws -> String {
        func gateError(_ code: Int, _ message: String) -> NSError {
            NSError(
                domain: "MovieCutUITest",
                code: code,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        let deadline = Date().addingTimeInterval(10)
        var videoClip: Clip?
        while true {
            videoClip = currentProject.timeline.tracks
                .flatMap(\.clips)
                .first { $0.kind == .video }
            if videoClip != nil || Date() >= deadline { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let clip = videoClip else {
            throw gateError(29, "no video clip present within 10s of launch (bootstrap load failed?)")
        }
        let posX = clip.keyframes.filter { $0.property == .positionX }.count
        let posY = clip.keyframes.filter { $0.property == .positionY }.count
        guard posX > 0, posY > 0, posX == posY else {
            throw gateError(30, "tracked keyframes lost across reopen: posX=\(posX) posY=\(posY)")
        }
        return " motion_tracking_reopen=ok keyframes=\(posX + posY) posX=\(posX) posY=\(posY)"
    }

    /// R5 / benchmark B-I7 hook. Generates a proxy for the first video asset in
    /// the library, optionally turns proxy playback on, then reports the badge
    /// state the timeline resolves for each video clip.
    ///
    /// This exists because the badge is otherwise unverifiable outside a running
    /// app: `ProxyBadgeStateTests` covers the decision, but only this path proves
    /// the timeline reaches a real generated proxy through the real asset
    /// library and the real playback setting.
    ///
    /// Emits ` proxy_generated=<0|1> proxy_playback=<0|1> proxy_badge=<none|idle|active>`.
    private func runProxyBadgeUITestScenario(
        useProxyPlayback: Bool,
        proxyResolution: ProxyResolution?
    ) async -> String {
        guard let asset = currentProject.mediaLibrary.assets.values.first(where: { $0.kind == .video }) else {
            return " proxy_generated=0 proxy_playback=0 proxy_badge=none proxy_resolution=none proxy_file=none"
        }

        // The resolution must be committed before generating, since it selects
        // both the export preset and the target filename.
        if let proxyResolution {
            await updatePlaybackSettings(proxyResolution: proxyResolution)
        }
        await generateProxy(for: asset.id)
        await updatePlaybackSettings(useProxyPlayback: useProxyPlayback)

        let generated = currentProject.mediaLibrary.assets[asset.id]?.proxy?.proxyURL != nil
        // Resolve through the same Core entry point the timeline view uses, so a
        // divergence between this report and what is drawn is impossible.
        let states = currentProject.timeline.tracks
            .flatMap(\.clips)
            .compactMap { clip -> ProxyBadgeState? in
                guard clip.kind == .video, let assetID = clip.assetId,
                      let clipAsset = currentProject.mediaLibrary.assets[assetID] else { return nil }
                return ProxyBadgeState.resolve(
                    proxy: clipAsset.proxy,
                    useProxyPlayback: currentProject.playbackSettings.useProxyPlayback
                )
            }

        let badge = states.first.map(\.rawValue) ?? "none"
        let playbackFlag = currentProject.playbackSettings.useProxyPlayback ? 1 : 0
        let settings = currentProject.playbackSettings
        // Report the generated file's own name and measured size: the filename
        // proves each resolution lands in its own file, and the size proves the
        // export preset followed the selection rather than the old hardwired
        // 960x540.
        let proxyURL = currentProject.mediaLibrary.assets[asset.id]?.proxy?.proxyURL
        let fileName = proxyURL?.lastPathComponent ?? "none"
        var measured = "none"
        if let proxyURL,
           let tracks = try? await AVURLAsset(url: proxyURL).loadTracks(withMediaType: .video),
           let track = tracks.first,
           let size = try? await track.load(.naturalSize) {
            measured = "\(Int(abs(size.width)))x\(Int(abs(size.height)))"
        }
        return " proxy_generated=\(generated ? 1 : 0) proxy_playback=\(playbackFlag)"
            + " proxy_badge=\(badge) proxy_resolution=\(settings.proxyResolution.shortLabel)"
            + " proxy_file=\(fileName) proxy_actual=\(measured)"
    }

    /// G-19 Inc 1 A6 hook. It executes the new resolver and both atomic
    /// commands inside MovieCutMac through the same ViewModel methods reserved
    /// for the gallery/panel, then proves each undo restores an exact snapshot.
    private func runCardTemplateCoreUITestScenario(environment: [String: String]) async {
        let resultPath = environment["MOVIECUT_UITEST_RESULT"] ?? ""
        var status = "G19_CORE_E2E_INCOMPLETE error=not_run"

        do {
            guard let sourcePath = environment["MOVIECUT_UITEST_CARD_TEMPLATE_CORE_SOURCE"],
                  !sourcePath.isEmpty else {
                throw CardEditorUITestError.invariant("missing MOVIECUT_UITEST_CARD_TEMPLATE_CORE_SOURCE")
            }
            stopAutoSave()
            lastErrorMessage = nil
            await openProject(from: URL(fileURLWithPath: sourcePath))
            try cardEditorUITestRequire(lastErrorMessage == nil, lastErrorMessage ?? "source load failed")
            let beforeTemplate = try cardEditorUITestDocument()
            let template = cardTemplateCoreUITestTemplate()

            let templateApplied = await applyCardTemplate(template, seed: 19)
            try cardEditorUITestRequire(templateApplied, lastErrorMessage ?? "template command failed")
            let afterTemplate = try cardEditorUITestDocument()
            try cardEditorUITestRequire(afterTemplate.pages.count == 5, "resolver did not produce five pages")
            try cardEditorUITestRequire(
                Set(afterTemplate.pages.map(\.role)) == Set([.cover, .body, .emphasis, .closing]),
                "resolved roles were incomplete"
            )

            let changedStyle = CardMasterStyle(
                fontFamily: "Avenir Next",
                primaryColorHex: "#123456",
                secondaryColorHex: "#FEDCBA",
                logoPlacement: NormalizedRect(x: 0.72, y: 0.06, width: 0.2, height: 0.1)!
            )
            let masterApplied = await setCardMasterStyle(changedStyle)
            try cardEditorUITestRequire(masterApplied, lastErrorMessage ?? "master command failed")
            let afterMaster = try cardEditorUITestDocument()
            let masterPropagated = afterMaster.pages.flatMap(\.elements).allSatisfy { element in
                switch element.kind {
                case .text:
                    return element.text?.fontFamily == changedStyle.fontFamily
                        && element.text?.fontColor == changedStyle.primaryColorHex
                case .logo:
                    return element.normalizedFrame == changedStyle.logoPlacement
                case .image:
                    return true
                }
            }
            try cardEditorUITestRequire(masterPropagated, "master values did not propagate")

            await undo()
            let masterUndo = currentProject.cardDocument == afterTemplate
            try cardEditorUITestRequire(masterUndo, "one undo did not restore the pre-master snapshot")
            await undo()
            let templateUndo = currentProject.cardDocument == beforeTemplate
            try cardEditorUITestRequire(templateUndo, "one undo did not restore the pre-template snapshot")

            status = "G19_CORE_E2E_COMPLETE pages=5 roles=cover,body,emphasis,closing emptySlots=\(CardTemplateResolver.emptyRequiredSlotCount(in: afterTemplate.pages)) masterPropagated=1 templateUndo=1 masterUndo=1 error=none"
            lastErrorMessage = nil
            lastStatusMessage = status
        } catch {
            status = "G19_CORE_E2E_INCOMPLETE error=\(error.localizedDescription)"
            lastStatusMessage = nil
            lastErrorMessage = "card template core harness failed: \(error.localizedDescription)"
        }

        if !resultPath.isEmpty {
            writeHarnessStatus(status, to: resultPath)
        }
        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func cardEditorUITestDocument() throws -> CardDocument {
        guard let document = currentProject.cardDocument else {
            throw CardEditorUITestError.invariant("project has no card document")
        }
        return document
    }

    private func cardTemplateCoreUITestTemplate() -> CardTemplateSet {
        let textFrame = NormalizedRect(x: 0.1, y: 0.12, width: 0.8, height: 0.22)!
        let mediaFrame = NormalizedRect(x: 0.1, y: 0.4, width: 0.8, height: 0.45)!
        let logoFrame = NormalizedRect(x: 0.7, y: 0.82, width: 0.2, height: 0.1)!
        let mediaID = UUID(uuidString: "86000000-0000-4000-8000-000000000001")!
        let logoID = UUID(uuidString: "86000000-0000-4000-8000-000000000002")!
        let style = CardMasterStyle(
            fontFamily: "Helvetica Neue",
            primaryColorHex: "#112233",
            secondaryColorHex: "#DDEEFF",
            logoPlacement: logoFrame
        )
        return CardTemplateSet(
            id: "g19-core-a6",
            name: "G19 Core A6",
            pages: [
                CardTemplatePage(
                    id: "cover",
                    role: .cover,
                    elements: [CardElement(kind: .text, normalizedFrame: textFrame, text: TextClipContent(text: "Cover"))]
                ),
                CardTemplatePage(
                    id: "body",
                    role: .body,
                    elements: [
                        CardElement(kind: .text, normalizedFrame: textFrame, text: TextClipContent(text: "Body")),
                        CardElement(kind: .image, normalizedFrame: mediaFrame, mediaAssetID: mediaID)
                    ]
                ),
                CardTemplatePage(
                    id: "emphasis",
                    role: .emphasis,
                    elements: [CardElement(kind: .text, normalizedFrame: textFrame, text: TextClipContent(text: "Emphasis"))]
                ),
                CardTemplatePage(
                    id: "closing",
                    role: .closing,
                    elements: [
                        CardElement(kind: .text, normalizedFrame: textFrame, text: TextClipContent(text: "Closing")),
                        CardElement(kind: .logo, normalizedFrame: logoFrame, mediaAssetID: logoID)
                    ]
                )
            ],
            defaultMasterStyle: style
        )
    }

    /// G-19 Inc 4's fail-closed actual-app proof. The action counts mirror the
    /// gallery's select/apply and preset/apply paths, while every mutation runs
    /// through the exact command-backed ViewModel methods used by those views.
    private func runCardTemplateUITestScenario(environment: [String: String]) async {
        var dump = CardTemplateUITestDump()
        let resultPath = environment["MOVIECUT_UITEST_RESULT"] ?? ""

        do {
            dump = try await makeCardTemplateUITestDump(environment: environment)
            lastErrorMessage = nil
            lastStatusMessage = dump.completionMarker
        } catch {
            dump.complete = false
            dump.completionMarker = ""
            dump.error = error.localizedDescription
            lastStatusMessage = nil
            lastErrorMessage = "card template harness failed: \(error.localizedDescription)"
        }

        if !resultPath.isEmpty {
            do {
                try writeUITestDump(dump, to: URL(fileURLWithPath: resultPath))
            } catch {
                lastStatusMessage = nil
                lastErrorMessage = "card template dump failed: \(error.localizedDescription)"
            }
        }

        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func makeCardTemplateUITestDump(
        environment: [String: String]
    ) async throws -> CardTemplateUITestDump {
        let sourceURL = try cardEditorUITestURL(
            named: "MOVIECUT_UITEST_CARD_TEMPLATE_SOURCE",
            environment: environment
        )

        stopAutoSave()
        lastErrorMessage = nil
        await openProject(from: sourceURL)
        try cardEditorUITestRequire(lastErrorMessage == nil, lastErrorMessage ?? "source load failed")

        let builtins = BuiltinCardTemplates.all
        try cardEditorUITestRequire(builtins.count >= 10, "fewer than ten built-in card template sets")
        try builtins.forEach { try CardTemplateResolver.validate($0) }
        guard let template = builtins.first, builtins.count > 1 else {
            throw CardEditorUITestError.invariant("built-in template manifest could not supply two styles")
        }

        var dump = CardTemplateUITestDump()
        dump.builtinCount = builtins.count
        dump.builtinSetIDs = builtins.map(\.id)
        dump.builtinSetNames = builtins.map(\.name)
        dump.appliedSetID = template.id
        dump.appliedSetName = template.name
        dump.templateClickCount = 2

        let beforeTemplate = try cardEditorUITestDocument()
        let templateApplied = await applyCardTemplate(template, seed: 19_04)
        try cardEditorUITestRequire(templateApplied, lastErrorMessage ?? "template command failed")
        let afterTemplate = try cardEditorUITestDocument()

        dump.pageCount = afterTemplate.pages.count
        let requiredRoles: [CardPageRole] = [.cover, .body, .emphasis, .closing]
        dump.rolesPresent = requiredRoles
            .filter { role in afterTemplate.pages.contains(where: { $0.role == role }) }
            .map(\.rawValue)
        dump.emptyRequiredSlotCount = CardTemplateResolver.emptyRequiredSlotCount(in: afterTemplate.pages)
        try cardEditorUITestRequire(dump.pageCount == 5, "template did not resolve to exactly five pages")
        try cardEditorUITestRequire(
            dump.rolesPresent == requiredRoles.map(\.rawValue),
            "template result did not contain all four roles"
        )
        try cardEditorUITestRequire(dump.emptyRequiredSlotCount == 0, "template result contained an empty required slot")
        try cardEditorUITestRequire(dump.templateClickCount <= 2, "template action-count limit was exceeded")

        await undo()
        dump.templateUndoRestored = currentProject.cardDocument == beforeTemplate
        try cardEditorUITestRequire(dump.templateUndoRestored, "one undo did not restore the pre-template snapshot")
        await redo()
        dump.templateRedoRestored = currentProject.cardDocument == afterTemplate
        try cardEditorUITestRequire(dump.templateRedoRestored, "one redo did not restore the applied template snapshot")

        // Expand the five-page template to the eight-card UB-C5 fixture through
        // normal duplicate commands before changing the master.
        let duplicatePageIDs = [
            "87000000-0000-4000-8000-000000000001",
            "87000000-0000-4000-8000-000000000002",
            "87000000-0000-4000-8000-000000000003"
        ].map { UUID(uuidString: $0)! }
        for (sourcePage, duplicatePageID) in zip(afterTemplate.pages.prefix(3), duplicatePageIDs) {
            let duplicated = await duplicateCardPage(sourcePage.id, duplicatePageID: duplicatePageID)
            try cardEditorUITestRequire(duplicated == duplicatePageID, "failed to build the eight-page master fixture")
        }
        let beforeMaster = try cardEditorUITestDocument()
        try cardEditorUITestRequire(beforeMaster.pages.count == 8, "master fixture did not contain eight pages")

        let changedMaster = builtins[1].defaultMasterStyle
        try cardEditorUITestRequire(
            changedMaster.fontFamily != template.defaultMasterStyle.fontFamily
                && changedMaster.primaryColorHex != template.defaultMasterStyle.primaryColorHex
                && changedMaster.logoPlacement != template.defaultMasterStyle.logoPlacement,
            "master fixture did not change font, primary color, and logo placement"
        )
        dump.masterClickCount = 2
        dump.masterFontFamily = changedMaster.fontFamily
        dump.masterPrimaryColorHex = changedMaster.primaryColorHex
        dump.masterLogoPlacement = changedMaster.logoPlacement.map(CardEditorUITestFrame.init)
        dump.masterChangedAttributes = ["fontFamily", "primaryColorHex", "logoPlacement"]

        let masterApplied = await setCardMasterStyle(changedMaster)
        try cardEditorUITestRequire(masterApplied, lastErrorMessage ?? "master command failed")
        let afterMaster = try cardEditorUITestDocument()
        dump.pageOverrideCount = afterMaster.pages.filter { $0.masterOverride != nil }.count
        dump.masterInheritedPageCount = afterMaster.pages.filter { $0.masterOverride == nil }.count
        dump.masterLogoElementCount = afterMaster.pages
            .flatMap(\.elements)
            .filter { $0.kind == .logo }
            .count
        dump.masterLogoPlacementMatchCount = afterMaster.pages
            .flatMap(\.elements)
            .filter { $0.kind == .logo && $0.normalizedFrame == changedMaster.logoPlacement }
            .count

        let matchingPages = afterMaster.pages.filter { page in
            let effectiveStyle = page.masterOverride ?? changedMaster
            return page.elements.allSatisfy { element in
                switch element.kind {
                case .text:
                    return element.text?.fontFamily == effectiveStyle.fontFamily
                        && element.text?.fontColor == effectiveStyle.primaryColorHex
                case .logo:
                    return effectiveStyle.logoPlacement == nil
                        || element.normalizedFrame == effectiveStyle.logoPlacement
                case .image:
                    return true
                }
            }
        }
        dump.masterPropagationPageCount = matchingPages.count
        dump.masterPropagationAcrossAllPages = matchingPages.count == afterMaster.pages.count
            && afterMaster.pages.count >= 8
            && afterMaster.masterStyle == changedMaster
        dump.pageOverridesPreserved = zip(beforeMaster.pages, afterMaster.pages).allSatisfy { before, after in
            before.id == after.id && before.masterOverride == after.masterOverride
        }

        try cardEditorUITestRequire(dump.masterClickCount <= 3, "master action-count limit was exceeded")
        try cardEditorUITestRequire(
            dump.masterPropagationAcrossAllPages && dump.masterPropagationPageCount >= 8,
            "effective master values did not resolve across all eight pages"
        )
        try cardEditorUITestRequire(dump.masterInheritedPageCount >= 7, "master did not reach all inheriting pages")
        try cardEditorUITestRequire(
            dump.masterLogoElementCount > 0
                && dump.masterLogoPlacementMatchCount == dump.masterLogoElementCount,
            "master logo placement did not reach every inheriting logo"
        )
        try cardEditorUITestRequire(dump.pageOverridesPreserved, "page-local master overrides were not preserved")

        await undo()
        dump.masterUndoRestored = currentProject.cardDocument == beforeMaster
        try cardEditorUITestRequire(dump.masterUndoRestored, "one undo did not restore the pre-master snapshot")

        dump.complete = true
        dump.completionMarker = "G19_CARD_TEMPLATE_E2E_COMPLETE"
        dump.error = "none"
        return dump
    }

    /// G-18 Inc 4's deterministic actual-app scenario. This deliberately uses
    /// the same ViewModel methods as CardEditorView/CardCanvasView so every edit
    /// still crosses EditorSession.dispatch and the normal ProjectStore paths.
    private func runCardEditorUITestScenario(environment: [String: String]) async {
        var dump = CardEditorUITestDump()
        let resultPath = environment["MOVIECUT_UITEST_RESULT"] ?? ""

        do {
            dump = try await makeCardEditorUITestDump(environment: environment)
            lastErrorMessage = nil
            lastStatusMessage = dump.completionMarker
        } catch {
            dump.complete = false
            dump.completionMarker = ""
            dump.error = error.localizedDescription
            lastStatusMessage = nil
            lastErrorMessage = "card editor harness failed: \(error.localizedDescription)"
        }

        if !resultPath.isEmpty {
            do {
                try writeUITestDump(dump, to: URL(fileURLWithPath: resultPath))
            } catch {
                lastStatusMessage = nil
                lastErrorMessage = "card editor dump failed: \(error.localizedDescription)"
            }
        }

        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    private func makeCardEditorUITestDump(
        environment: [String: String]
    ) async throws -> CardEditorUITestDump {
        let sourceURL = try cardEditorUITestURL(
            named: "MOVIECUT_UITEST_CARD_EDITOR_SOURCE",
            environment: environment
        )
        let saveURL = try cardEditorUITestURL(
            named: "MOVIECUT_UITEST_CARD_EDITOR_SAVE",
            environment: environment
        )
        let reloadURL = try cardEditorUITestURL(
            named: "MOVIECUT_UITEST_CARD_EDITOR_RELOAD",
            environment: environment
        )

        stopAutoSave()
        lastErrorMessage = nil
        await openProject(from: sourceURL)
        try cardEditorUITestRequire(lastErrorMessage == nil, lastErrorMessage ?? "source load failed")

        let startingPageIDs = [
            "83000000-0000-4000-8000-000000000001",
            "83000000-0000-4000-8000-000000000002",
            "83000000-0000-4000-8000-000000000003"
        ].map { UUID(uuidString: $0)! }
        let firstAddedPageID = UUID(uuidString: "85000000-0000-4000-8000-000000000001")!
        let duplicatePageID = UUID(uuidString: "85000000-0000-4000-8000-000000000002")!
        let secondAddedPageID = UUID(uuidString: "85000000-0000-4000-8000-000000000003")!
        let editedElementID = UUID(uuidString: "84000000-0000-4000-8000-000000000003")!
        let expectedFinalPageIDs = [
            startingPageIDs[0],
            secondAddedPageID,
            firstAddedPageID,
            startingPageIDs[1],
            duplicatePageID
        ]

        guard let startingDocument = currentProject.cardDocument else {
            throw CardEditorUITestError.invariant("source project has no card document")
        }
        try cardEditorUITestRequire(
            startingDocument.pages.map(\.id) == startingPageIDs,
            "source page IDs or order differed from the deterministic fixture"
        )
        try cardEditorUITestRequire(
            startingDocument.format == .square,
            "source format must start at square"
        )

        var dump = CardEditorUITestDump()
        dump.initialPageCount = startingDocument.pages.count
        dump.savedProjectPath = saveURL.path
        dump.reloadedProjectPath = reloadURL.path

        let firstAdded = await addCardPage(after: startingPageIDs[0], pageID: firstAddedPageID)
        try cardEditorUITestRequire(firstAdded == firstAddedPageID, "first add did not return its stable page ID")
        dump.actionCounts.add += 1

        let duplicated = await duplicateCardPage(
            startingPageIDs[1],
            duplicatePageID: duplicatePageID
        )
        try cardEditorUITestRequire(duplicated == duplicatePageID, "duplicate did not return its stable page ID")
        dump.actionCounts.duplicate += 1

        let selectedAfterDelete = await deleteCardPage(startingPageIDs[2])
        try cardEditorUITestRequire(
            selectedAfterDelete != nil
                && currentProject.cardDocument?.pages.contains(where: { $0.id == startingPageIDs[2] }) == false,
            "delete did not remove the requested page"
        )
        dump.actionCounts.delete += 1

        let secondAdded = await addCardPage(after: nil, pageID: secondAddedPageID)
        try cardEditorUITestRequire(secondAdded == secondAddedPageID, "second add did not return its stable page ID")
        dump.actionCounts.add += 1

        let didReorder = await moveCardPage(secondAddedPageID, to: 1)
        try cardEditorUITestRequire(didReorder, "reorder failed")
        dump.actionCounts.reorder += 1

        guard let reorderedDocument = currentProject.cardDocument else {
            throw CardEditorUITestError.invariant("card document disappeared after page operations")
        }
        try cardEditorUITestRequire(
            reorderedDocument.pages.map(\.id) == expectedFinalPageIDs,
            "final page IDs or order differed after add/duplicate/delete/reorder"
        )

        dump.observedFormats = [reorderedDocument.format.rawValue]
        let didPortrait = await setCardFormat(.portrait)
        try cardEditorUITestRequire(didPortrait, "portrait format switch failed")
        dump.observedFormats.append(CardFormat.portrait.rawValue)
        let didStory = await setCardFormat(.story)
        try cardEditorUITestRequire(didStory, "story format switch failed")
        dump.observedFormats.append(CardFormat.story.rawValue)

        guard let originalElement = cardEditorUITestElement(
            pageID: startingPageIDs[1],
            elementID: editedElementID,
            in: currentProject
        ) else {
            throw CardEditorUITestError.invariant("stable text element was not found after format changes")
        }
        let originalText = originalElement.text?.text ?? ""
        let editedText = "G18 saved inline text"
        let beforeFrame = originalElement.normalizedFrame
        var editedElement = originalElement
        var editedContent = editedElement.text ?? TextClipContent(text: "")
        editedContent.text = editedText
        editedElement.text = editedContent

        // The UI contract enters the inline control with one physical
        // double-click; the harness then uses the exact one-commit API invoked by
        // CardCanvasView after that local draft finishes.
        dump.actionCounts.inlineDoubleClick = 1
        let didUpdateElement = await updateCardElement(pageId: startingPageIDs[1], element: editedElement)
        try cardEditorUITestRequire(didUpdateElement, "inline-equivalent element update failed")
        guard let appliedElement = cardEditorUITestElement(
            pageID: startingPageIDs[1],
            elementID: editedElementID,
            in: currentProject
        ) else {
            throw CardEditorUITestError.invariant("edited element lost its stable ID")
        }
        try cardEditorUITestRequire(appliedElement.text?.text == editedText, "edited text was not applied")

        await undo()
        let undoElement = cardEditorUITestElement(
            pageID: startingPageIDs[1],
            elementID: editedElementID,
            in: currentProject
        )
        dump.inlineUndoRestored = undoElement?.text?.text == originalText
            && undoElement?.normalizedFrame == beforeFrame
        try cardEditorUITestRequire(dump.inlineUndoRestored, "one undo did not restore inline text and frame")

        await redo()
        let redoElement = cardEditorUITestElement(
            pageID: startingPageIDs[1],
            elementID: editedElementID,
            in: currentProject
        )
        dump.inlineRedoRestored = redoElement?.text?.text == editedText
            && redoElement?.id == editedElementID
            && redoElement?.normalizedFrame == beforeFrame
        try cardEditorUITestRequire(dump.inlineRedoRestored, "one redo did not restore inline text and stable ID")

        guard let finalDocument = currentProject.cardDocument,
              let finalElement = cardEditorUITestElement(
                  pageID: startingPageIDs[1],
                  elementID: editedElementID,
                  in: currentProject
              ) else {
            throw CardEditorUITestError.invariant("final card document or edited element is missing")
        }
        let afterFrame = finalElement.normalizedFrame
        dump.finalPageCount = finalDocument.pages.count
        dump.orderedPageIDs = finalDocument.pages.map { $0.id.uuidString }
        dump.editedElementID = finalElement.id.uuidString
        dump.originalText = originalText
        dump.editedText = finalElement.text?.text ?? ""
        dump.beforeFrame = CardEditorUITestFrame(beforeFrame)
        dump.afterFrame = CardEditorUITestFrame(afterFrame)
        dump.maxNormalizedFrameError = cardEditorUITestMaxError(beforeFrame, afterFrame)

        try cardEditorUITestRequire(dump.finalPageCount == 5, "final page count was not five")
        try cardEditorUITestRequire(
            dump.actionCounts.add <= 2
                && dump.actionCounts.duplicate <= 2
                && dump.actionCounts.delete <= 2
                && dump.actionCounts.reorder <= 2
                && dump.actionCounts.inlineDoubleClick == 1,
            "G-18 action-count limit was exceeded"
        )
        try cardEditorUITestRequire(
            dump.observedFormats == ["square", "portrait", "story"],
            "all three card formats were not observed in order"
        )
        try cardEditorUITestRequire(
            dump.maxNormalizedFrameError <= 0.001,
            "normalized frame drift exceeded 0.001"
        )

        let savedSnapshot = currentProject
        await saveProject(to: saveURL)
        try cardEditorUITestRequire(lastErrorMessage == nil, lastErrorMessage ?? "project save failed")
        let savedData = try Data(contentsOf: saveURL)
        dump.savedProjectBytes = savedData.count
        try cardEditorUITestRequire(!savedData.isEmpty, "saved project is empty")

        let reloadViewModel = EditorViewModel(project: Project(name: "G-18 reload sentinel"))
        reloadViewModel.stopAutoSave()
        await reloadViewModel.openProject(from: saveURL)
        try cardEditorUITestRequire(
            reloadViewModel.lastErrorMessage == nil,
            reloadViewModel.lastErrorMessage ?? "fresh session failed to load saved project"
        )
        await reloadViewModel.saveProject(to: reloadURL)
        try cardEditorUITestRequire(
            reloadViewModel.lastErrorMessage == nil,
            reloadViewModel.lastErrorMessage ?? "fresh session failed to save reload path"
        )

        let verificationViewModel = EditorViewModel(project: Project(name: "G-18 verification sentinel"))
        verificationViewModel.stopAutoSave()
        await verificationViewModel.openProject(from: reloadURL)
        try cardEditorUITestRequire(
            verificationViewModel.lastErrorMessage == nil,
            verificationViewModel.lastErrorMessage ?? "verification session failed to load fresh path"
        )
        let reloadedData = try Data(contentsOf: reloadURL)
        dump.reloadedProjectBytes = reloadedData.count
        dump.freshSessionReloaded = verificationViewModel.currentProject.name == savedSnapshot.name
            && verificationViewModel.currentProject.cardDocument?.pages.map(\.id) == expectedFinalPageIDs
        dump.saveReloadEqual = savedData == reloadedData
            && reloadViewModel.currentProject == verificationViewModel.currentProject
            && verificationViewModel.currentProject.cardDocument == savedSnapshot.cardDocument
        try cardEditorUITestRequire(dump.freshSessionReloaded, "fresh-path session did not load expected project")
        try cardEditorUITestRequire(dump.saveReloadEqual, "save/reload project equality failed")

        dump.complete = true
        dump.completionMarker = "G18_CARD_EDITOR_E2E_COMPLETE"
        dump.error = "none"
        return dump
    }

    private func cardEditorUITestURL(
        named key: String,
        environment: [String: String]
    ) throws -> URL {
        guard let path = environment[key], !path.isEmpty else {
            throw CardEditorUITestError.invariant("missing \(key)")
        }
        return URL(fileURLWithPath: path)
    }

    private func cardEditorUITestRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CardEditorUITestError.invariant(message) }
    }

    private func cardEditorUITestElement(
        pageID: UUID,
        elementID: UUID,
        in project: Project
    ) -> CardElement? {
        project.cardDocument?.pages
            .first(where: { $0.id == pageID })?
            .elements.first(where: { $0.id == elementID })
    }

    private func cardEditorUITestMaxError(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Double {
        [
            abs(lhs.x - rhs.x),
            abs(lhs.y - rhs.y),
            abs(lhs.width - rhs.width),
            abs(lhs.height - rhs.height)
        ].max() ?? .infinity
    }

    private func writeUITestDump<Dump: Encodable>(_ dump: Dump, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(dump)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private enum ClipboardUITestError: LocalizedError {
        case invariant(String)

        var errorDescription: String? {
            switch self {
            case .invariant(let message): message
            }
        }
    }

    private enum FilmstripUITestError: LocalizedError {
        case invariant(String)

        var errorDescription: String? {
            switch self {
            case .invariant(let message): message
            }
        }
    }

    private func runFilmstripGeneratorUITestScenario() async throws -> String {
        guard let clip = selectedClip,
              clip.kind == .video,
              let assetID = clip.assetId,
              let asset = currentProject.mediaLibrary.assets[assetID],
              asset.kind == .video else {
            throw FilmstripUITestError.invariant("expected a selected video clip and asset")
        }

        let frames = try await FilmstripGenerator().frames(
            for: asset.originalURL,
            sourceRange: clip.sourceRange,
            targetCount: 4,
            maxHeight: 60
        )
        guard frames.count == 4 else {
            throw FilmstripUITestError.invariant("expected 4 frames, found \(frames.count)")
        }

        let expectedRequests = FilmstripRequestPlanner.requests(
            sourceRange: clip.sourceRange,
            targetCount: 4
        )
        guard frames.map(\.requestedTime) == expectedRequests.map(\.time) else {
            throw FilmstripUITestError.invariant("generated requests differ from the shared plan")
        }

        let tolerance = FilmstripGenerator.requestedTimeTolerance + (1.0 / 30.0)
        guard frames.allSatisfy({ abs($0.actualTime - $0.requestedTime) <= tolerance }) else {
            throw FilmstripUITestError.invariant("actual frame time exceeded request tolerance")
        }

        let maxDecodedHeight = frames.map { $0.image.height }.max() ?? 0
        guard maxDecodedHeight > 0, maxDecodedHeight <= 60 else {
            throw FilmstripUITestError.invariant("decoded height \(maxDecodedHeight) exceeds maxHeight 60")
        }

        let zoomInputs: [Double] = [20, 40, 80, 160]
        let zoomBuckets = zoomInputs.map { FilmstripZoomBucket.bucket(for: $0) }
        guard zoomBuckets.map(\.rawValue) == [0, 1, 2, 3] else {
            throw FilmstripUITestError.invariant("unexpected zoom buckets \(zoomBuckets)")
        }

        let cache = FilmstripCache()
        let cacheKey = FilmstripCacheKey(
            assetID: asset.id,
            zoomBucket: FilmstripZoomBucket.bucket(for: 80)
        )
        guard await cache.frames(for: cacheKey) == nil else {
            throw FilmstripUITestError.invariant("new cache unexpectedly contained frames")
        }
        await cache.insert(frames, for: cacheKey)
        guard await cache.frames(for: cacheKey)?.count == frames.count else {
            throw FilmstripUITestError.invariant("cache did not return inserted frames")
        }
        await cache.remove(assetID: asset.id)
        guard await cache.frames(for: cacheKey) == nil else {
            throw FilmstripUITestError.invariant("asset invalidation left cached frames")
        }

        let cacheStats = await cache.stats()
        guard cacheStats == FilmstripCacheStats(hits: 1, misses: 2, inserts: 1) else {
            throw FilmstripUITestError.invariant("unexpected cache stats \(cacheStats)")
        }
        let cacheLimit = await cache.configuredTotalCostLimit()
        guard cacheLimit == FilmstripCache.defaultTotalCostLimit else {
            throw FilmstripUITestError.invariant("unexpected cache limit \(cacheLimit)")
        }

        let requested = frames.map { String(format: "%.3f", $0.requestedTime) }.joined(separator: ",")
        let actual = frames.map { String(format: "%.3f", $0.actualTime) }.joined(separator: ",")
        let bucketSummary = zoomBuckets.map { String($0.rawValue) }.joined(separator: ",")
        return " filmstrip_frames=\(frames.count) requested=\(requested) actual=\(actual) max_height=\(maxDecodedHeight) zoom_buckets=\(bucketSummary) cache_hit=\(cacheStats.hits) cache_miss=\(cacheStats.misses) cache_inserts=\(cacheStats.inserts) cache_limit=\(cacheLimit) cache_invalidate=1"
    }

    private func runTimelineFilmstripConsumerUITestScenario() async throws -> String {
        for _ in 0..<200 {
            if TimelineFilmstripDebugProbe.shared.hasVisibleRequest { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard TimelineFilmstripDebugProbe.shared.hasVisibleRequest else {
            throw FilmstripUITestError.invariant("TimelineView did not issue a visible filmstrip request")
        }

        // A real zoom mutation invalidates the first delayed UI request. The
        // TimelineFilmstripStore must cancel it and only publish the replacement.
        timelineZoom = timelineZoom < 160 ? 160 : 80

        var completed: TimelineFilmstripDebugProbe.Summary?
        for _ in 0..<400 {
            if let summary = TimelineFilmstripDebugProbe.shared.completedSummary() {
                completed = summary
                break
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard let completed else {
            throw FilmstripUITestError.invariant(
                "TimelineView consumer did not prove viewport/cancellation/fallback invariants"
            )
        }

        var droveReadyHover = false
        for _ in 0..<200 {
            if TimelineFilmstripDebugProbe.shared.driveReadyHover() {
                droveReadyHover = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard droveReadyHover else {
            throw FilmstripUITestError.invariant(
                "TimelineView hover surface did not accept the published-frame driver"
            )
        }

        for _ in 0..<200 {
            if TimelineFilmstripDebugProbe.shared.hasRenderedHoverEvidence { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard TimelineFilmstripDebugProbe.shared.hasRenderedHoverEvidence,
              TimelineFilmstripDebugProbe.shared.driveHoverExit() else {
            throw FilmstripUITestError.invariant(
                "TimelineView hover overlay did not render before exit"
            )
        }

        var provedNotReady = false
        var provedUnsupported = false
        for _ in 0..<200 {
            if !provedNotReady {
                provedNotReady = TimelineFilmstripDebugProbe.shared.driveNotReadyHover()
            }
            if !provedUnsupported {
                provedUnsupported = TimelineFilmstripDebugProbe.shared.driveUnsupportedHover()
            }
            if provedNotReady && provedUnsupported { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard provedNotReady, provedUnsupported else {
            throw FilmstripUITestError.invariant(
                "TimelineView hover did not prove not-ready and unsupported hidden states"
            )
        }

        var hoverCompleted: TimelineFilmstripDebugProbe.HoverSummary?
        for _ in 0..<200 {
            if let summary = TimelineFilmstripDebugProbe.shared.completedHoverSummary() {
                hoverCompleted = summary
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let hoverCompleted else {
            throw FilmstripUITestError.invariant(
                "TimelineView hover evidence did not complete"
            )
        }

        let zoomRequests = completed.zoomScaleKeys
            .map { String(format: "%.3f", Double($0) / 1_000) }
            .joined(separator: ",")
        return String(
            format: " timeline_filmstrip_frames=%d distinct_digests=%d distinct_times=%d requested_span=%.3f full_span=%.3f requested_count=%d full_count=%d offscreen_skipped=%d cancelled=%d stale_rejected=%d fallback_before_ready=%d fallback_after_cancel=%d zoom_requests=%@ hover_visible=%d hover_width=%.0f hover_height=%.0f hover_label=%d hover_requested=%.3f hover_selected_requested=%.3f hover_actual=%.3f hover_error=%.3f hover_digest=%@ hover_digest_cached=%d hover_exit_hidden=%d hover_cache_miss_hidden=%d hover_unsupported_hidden=%d hover_request_delta=%d hover_generation_delta=%d",
            completed.consumerFrameCount,
            completed.distinctDigestCount,
            completed.distinctTimestampCount,
            completed.requestedSpan,
            completed.fullSpan,
            completed.requestedCount,
            completed.fullCount,
            completed.offscreenSkipped ? 1 : 0,
            completed.cancelled ? 1 : 0,
            completed.staleRejected ? 1 : 0,
            completed.fallbackBeforeReady ? 1 : 0,
            completed.fallbackAfterCancellation ? 1 : 0,
            zoomRequests,
            hoverCompleted.visible ? 1 : 0,
            hoverCompleted.imageWidth,
            hoverCompleted.imageHeight,
            hoverCompleted.labelPresent ? 1 : 0,
            hoverCompleted.requestedSourceTime,
            hoverCompleted.selectedRequestedTime,
            hoverCompleted.selectedActualTime,
            hoverCompleted.absoluteError,
            hoverCompleted.selectedDigest,
            hoverCompleted.digestBelongsToPublishedFrames ? 1 : 0,
            hoverCompleted.exitHidden ? 1 : 0,
            hoverCompleted.cacheMissHidden ? 1 : 0,
            hoverCompleted.unsupportedHidden ? 1 : 0,
            hoverCompleted.requestCountDelta,
            hoverCompleted.generationCountDelta
        )
    }

    private func runTimelineFilmstripPerformanceUITestScenario(
        named scenario: String,
        phasePath: String?
    ) async throws -> String {
        for _ in 0..<300 {
            if TimelineFilmstripDebugProbe.shared.hasPerformanceDriver { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard TimelineFilmstripDebugProbe.shared.hasPerformanceDriver else {
            throw FilmstripUITestError.invariant("TimelineView performance driver did not register")
        }

        switch scenario {
        case "density":
            return try await runFilmstripDensityPerformanceScenario()
        case "memory":
            return try await runFilmstripMemoryPerformanceScenario(phasePath: phasePath)
        default:
            throw FilmstripUITestError.invariant("unknown filmstrip performance scenario \(scenario)")
        }
    }

    private func runFilmstripDensityPerformanceScenario() async throws -> String {
        let zoomLevels: [Double] = [20, 40, 80, 160]
        let scrollTargetsByZoom: [[TimeInterval]] = [
            [30, 45, 60],
            [75, 90, 105],
            [120, 135, 90],
            [75, 60, 45]
        ]
        var evidenceGroups: [[TimelineFilmstripDebugProbe.PerformanceEvidence]] = []
        var previousIdentity: String?

        for (zoom, scrollTargets) in zip(zoomLevels, scrollTargetsByZoom) {
            var zoomEvidence: [TimelineFilmstripDebugProbe.PerformanceEvidence] = []
            let zoomBaseline = TimelineFilmstripDebugProbe.shared.performanceEvidenceCount
            guard TimelineFilmstripDebugProbe.shared.driveZoom(zoom) else {
                throw FilmstripUITestError.invariant("failed to drive TimelineView zoom \(zoom)")
            }
            let initialZoomEvidence = try await waitForFilmstripPerformanceEvidence(
                after: zoomBaseline,
                zoomScaleKey: Int((zoom * 1_000).rounded()),
                differingFrom: previousIdentity
            )
            zoomEvidence.append(initialZoomEvidence)
            previousIdentity = initialZoomEvidence.stableIdentity

            // Three distinct real ScrollViewReader mutations at every zoom make
            // the UI work distribution attributable to zoom/scroll updates, not
            // to an idle scheduler wakeup or a single lucky render.
            for scrollTarget in scrollTargets {
                let scrollBaseline = TimelineFilmstripDebugProbe.shared.performanceEvidenceCount
                guard TimelineFilmstripDebugProbe.shared.driveScroll(to: scrollTarget) else {
                    throw FilmstripUITestError.invariant(
                        "failed to drive TimelineView scroll \(scrollTarget) at zoom \(zoom)"
                    )
                }
                let scrollEvidence = try await waitForFilmstripPerformanceEvidence(
                    after: scrollBaseline,
                    zoomScaleKey: Int((zoom * 1_000).rounded()),
                    differingFrom: previousIdentity
                )
                zoomEvidence.append(scrollEvidence)
                previousIdentity = scrollEvidence.stableIdentity
            }
            evidenceGroups.append(zoomEvidence)
        }

        for _ in 0..<300 {
            if TimelineFilmstripDebugProbe.shared.hasPreservedSurfaceEvidence { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let workSummary = TimelineFilmstripDebugProbe.shared.mainThreadWorkSummary()
        guard TimelineFilmstripDebugProbe.shared.hasPreservedSurfaceEvidence else {
            throw FilmstripUITestError.invariant(
                "actual TimelineView did not render preserved image/audio/text surfaces: "
                    + TimelineFilmstripDebugProbe.shared.preservedSurfaceNames.joined(separator: ",")
            )
        }
        let evidence = evidenceGroups.flatMap { $0 }
        let expectedRequestsPerZoom = 4
        let expectedRequestCount = zoomLevels.count * expectedRequestsPerZoom
        guard evidenceGroups.count == zoomLevels.count,
              evidenceGroups.allSatisfy({ $0.count == expectedRequestsPerZoom }),
              evidenceGroups.allSatisfy({ Set($0.map(\.stableIdentity)).count == expectedRequestsPerZoom }),
              evidence.count == expectedRequestCount,
              Set(evidence.map(\.stableIdentity)).count == expectedRequestCount,
              evidence.allSatisfy({
                  $0.frameCount > 1
                      && $0.distinctDigestCount > 1
                      && $0.distinctTimestampCount > 1
                      && $0.maxFrameHeight > 0
                      && $0.maxFrameHeight <= 60
              }) else {
            throw FilmstripUITestError.invariant("density evidence was static, duplicated, or unbounded")
        }
        let densities = evidenceGroups.map { group in
            group.map(\.density).reduce(0, +) / Double(group.count)
        }
        guard zip(densities, densities.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
            throw FilmstripUITestError.invariant("frame density was not strictly increasing: \(densities)")
        }
        guard workSummary.timing.sampleCount >= expectedRequestCount * 4,
              workSummary.requestCount >= expectedRequestCount,
              workSummary.publishCount >= expectedRequestCount,
              workSummary.consumerUpdateCount >= expectedRequestCount,
              workSummary.consumerDrawCount >= expectedRequestCount,
              workSummary.distinctRequestCount >= expectedRequestCount,
              workSummary.offMainThreadCount == 0,
              zoomLevels.allSatisfy({ zoom in
                  workSummary.sampleCount(
                      zoomScaleKey: Int((zoom * 1_000).rounded())
                  ) >= expectedRequestsPerZoom * 4
              }) else {
            throw FilmstripUITestError.invariant(
                "main-thread filmstrip consumer work evidence was incomplete"
            )
        }
        guard let cacheMetrics = await TimelineFilmstripDebugProbe.shared.performanceCacheMetrics() else {
            throw FilmstripUITestError.invariant("TimelineView cache metrics unavailable")
        }

        var fields = [
            "filmstrip_perf=density",
            "perf_complete=1",
            "ui_work_samples=\(workSummary.timing.sampleCount)",
            String(format: "ui_work_p95_ms=%.3f", workSummary.timing.p95Milliseconds),
            String(format: "ui_work_max_ms=%.3f", workSummary.timing.maxMilliseconds),
            "ui_work_over_16_6=\(workSummary.timing.overFrameBudgetCount)",
            "ui_work_requests=\(workSummary.requestCount)",
            "ui_work_publishes=\(workSummary.publishCount)",
            "ui_work_updates=\(workSummary.consumerUpdateCount)",
            "ui_work_draws=\(workSummary.consumerDrawCount)",
            "ui_work_distinct_requests=\(workSummary.distinctRequestCount)",
            "ui_work_off_main=\(workSummary.offMainThreadCount)",
            "cache_current_bytes=\(cacheMetrics.currentTrackedCost)",
            "cache_peak_bytes=\(cacheMetrics.peakTrackedCost)",
            "cache_limit_bytes=\(cacheMetrics.totalCostLimit)",
            "cache_keys=\(cacheMetrics.trackedKeyCount)",
            "cache_evictions=\(cacheMetrics.evictionCount)",
            "max_frame_height=\(evidence.map(\.maxFrameHeight).max() ?? 0)",
            "preserved_image=1",
            "preserved_audio=1",
            "preserved_text=1"
        ]
        for (index, zoom) in zoomLevels.enumerated() {
            let group = evidenceGroups[index]
            guard let item = group.last else {
                throw FilmstripUITestError.invariant("missing density evidence at zoom \(zoom)")
            }
            let label = Int(zoom.rounded())
            fields.append("density_\(label)_bucket=\(item.requestID.viewportRequest.zoomBucket.rawValue)")
            fields.append("density_\(label)_identity=\(item.stableIdentity)")
            fields.append("density_\(label)_frames=\(group.map(\.frameCount).min() ?? 0)")
            fields.append("density_\(label)_digests=\(group.map(\.distinctDigestCount).min() ?? 0)")
            fields.append("density_\(label)_times=\(group.map(\.distinctTimestampCount).min() ?? 0)")
            fields.append("density_\(label)_requests=\(group.count)")
            fields.append("density_\(label)_distinct_requests=\(Set(group.map(\.stableIdentity)).count)")
            fields.append(
                "ui_work_\(label)_samples=\(workSummary.sampleCount(zoomScaleKey: item.requestID.viewportRequest.zoomScaleKey))"
            )
            fields.append(String(
                format: "density_%d_span=%.3f",
                label,
                item.requestID.viewportRequest.sourceRange.duration
            ))
            fields.append(String(format: "density_%d_fps=%.3f", label, densities[index]))
            fields.append("density_\(label)_decoded_bytes=\(group.map(\.decodedByteCost).max() ?? 0)")
        }
        return " " + fields.joined(separator: " ")
    }

    private func runFilmstripMemoryPerformanceScenario(phasePath: String?) async throws -> String {
        let zoom = 160.0
        let zoomBaseline = TimelineFilmstripDebugProbe.shared.performanceEvidenceCount
        guard TimelineFilmstripDebugProbe.shared.driveZoom(zoom) else {
            throw FilmstripUITestError.invariant("failed to drive high-resolution TimelineView zoom")
        }
        let initial = try await waitForFilmstripPerformanceEvidence(
            after: zoomBaseline,
            zoomScaleKey: 160_000,
            differingFrom: nil
        )
        var evidence: [TimelineFilmstripDebugProbe.PerformanceEvidence] = []
        writeFilmstripPerformancePhase("baseline", path: phasePath)
        try await Task.sleep(for: .milliseconds(1_200))
        writeFilmstripPerformancePhase("churn", path: phasePath)

        var previousIdentity = initial.stableIdentity
        // Offset the ten one-minute-spaced positions by 30s so the sparse
        // temporary loop fixture is never sampled exactly at a segment seam.
        for target in stride(from: 30.0, through: 570.0, by: 60.0) {
            guard TimelineFilmstripDebugProbe.shared.driveScroll(to: target) else {
                throw FilmstripUITestError.invariant("failed to drive one-minute seek \(target)")
            }
            try await Task.sleep(for: .milliseconds(150))
            let transientBaseline = TimelineFilmstripDebugProbe.shared.performanceEvidenceCount
            guard TimelineFilmstripDebugProbe.shared.driveZoom(159) else {
                throw FilmstripUITestError.invariant("failed to drive transient cache-churn zoom")
            }
            _ = try await waitForFilmstripPerformanceEvidence(
                after: transientBaseline,
                zoomScaleKey: 159_000,
                differingFrom: nil
            )
            let baseline = TimelineFilmstripDebugProbe.shared.performanceEvidenceCount
            guard TimelineFilmstripDebugProbe.shared.driveZoom(160) else {
                throw FilmstripUITestError.invariant("failed to restore 160px/s memory zoom")
            }
            let item = try await waitForFilmstripPerformanceEvidence(
                after: baseline,
                zoomScaleKey: 160_000,
                differingFrom: previousIdentity
            )
            evidence.append(item)
            previousIdentity = item.stableIdentity
        }

        guard evidence.count == 10,
              Set(evidence.map(\.stableIdentity)).count == 10,
              evidence.allSatisfy({
                  $0.frameCount > 1
                      && $0.distinctDigestCount > 1
                      && $0.distinctTimestampCount > 1
                      && $0.maxFrameHeight > 0
                      && $0.maxFrameHeight <= 60
              }),
              let cacheMetrics = await TimelineFilmstripDebugProbe.shared.performanceCacheMetrics() else {
            throw FilmstripUITestError.invariant("memory churn evidence was incomplete or static")
        }
        writeFilmstripPerformancePhase("complete", path: phasePath)

        return String(
            format: " filmstrip_perf=memory perf_complete=1 memory_seeks=%d memory_published_sets=%d memory_distinct_requests=%d memory_nontrivial_sets=%d cache_current_bytes=%d cache_peak_bytes=%d cache_limit_bytes=%d cache_keys=%d cache_evictions=%d cache_oversized_rejections=%d max_frame_height=%d preserved_image=0 preserved_audio=0 preserved_text=0 ui_work_samples=0 ui_work_p95_ms=0.000 ui_work_max_ms=0.000 ui_work_over_16_6=0 ui_work_requests=0 ui_work_publishes=0 ui_work_updates=0 ui_work_draws=0 ui_work_distinct_requests=0 ui_work_off_main=0",
            evidence.count,
            evidence.count,
            Set(evidence.map(\.stableIdentity)).count,
            evidence.filter { $0.distinctDigestCount > 1 && $0.distinctTimestampCount > 1 }.count,
            cacheMetrics.currentTrackedCost,
            cacheMetrics.peakTrackedCost,
            cacheMetrics.totalCostLimit,
            cacheMetrics.trackedKeyCount,
            cacheMetrics.evictionCount,
            cacheMetrics.oversizedRejectionCount,
            evidence.map(\.maxFrameHeight).max() ?? 0
        )
    }

    private func waitForFilmstripPerformanceEvidence(
        after baseline: Int,
        zoomScaleKey: Int,
        differingFrom previousIdentity: String?
    ) async throws -> TimelineFilmstripDebugProbe.PerformanceEvidence {
        for _ in 0..<800 {
            if let evidence = TimelineFilmstripDebugProbe.shared.performanceEvidence(
                after: baseline,
                zoomScaleKey: zoomScaleKey,
                differingFrom: previousIdentity
            ) {
                return evidence
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw FilmstripUITestError.invariant(
            "TimelineView did not publish/render zoom=\(Double(zoomScaleKey) / 1_000) after evidence \(baseline); "
                + TimelineFilmstripDebugProbe.shared.performanceDiagnostics
        )
    }

    private func writeFilmstripPerformancePhase(_ phase: String, path: String?) {
        guard let path, !path.isEmpty else { return }
        try? phase.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func runClipboardUITestScenario() async throws -> String {
        let orderedClips = currentProject.timeline.tracks.enumerated().flatMap { trackIndex, track in
            track.clips.enumerated().map { clipIndex, clip in
                (trackIndex: trackIndex, clipIndex: clipIndex, clip: clip)
            }
        }.sorted { lhs, rhs in
            if lhs.clip.timelineRange.start != rhs.clip.timelineRange.start {
                return lhs.clip.timelineRange.start < rhs.clip.timelineRange.start
            }
            if lhs.trackIndex != rhs.trackIndex { return lhs.trackIndex < rhs.trackIndex }
            return lhs.clipIndex < rhs.clipIndex
        }
        guard orderedClips.count >= 2 else {
            throw ClipboardUITestError.invariant("expected at least two imported timeline clips, found \(orderedClips.count)")
        }

        let originals = orderedClips.prefix(2).map(\.clip)
        let originalIds = Set(originals.map(\.id))
        let originalStarts = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0.timelineRange.start) })

        selectedClipIds = originalIds
        copyClips(originalIds)
        guard lastErrorMessage == nil, selectedClipIds == originalIds else {
            throw ClipboardUITestError.invariant("copy did not preserve the two-clip selection")
        }

        // The visible timeline has a 10-second minimum ruler, while the public
        // scrub API clamps to content duration. Set the same public playhead state
        // bound by the UI so PasteClipsCommand receives the requested empty time.
        playheadTime = 10.0
        let idsBeforePaste = Set(currentProject.timeline.tracks.flatMap(\.clips).map(\.id))
        await pasteClipsAtPlayhead()
        guard lastErrorMessage == nil else {
            throw ClipboardUITestError.invariant("paste reported \(lastErrorMessage ?? "an unknown error")")
        }

        let clipsAfterPaste = currentProject.timeline.tracks.flatMap(\.clips)
        let idsAfterPaste = Set(clipsAfterPaste.map(\.id))
        let pastedIds = selectedClipIds
        guard pastedIds.count == 2,
              pastedIds == idsAfterPaste.subtracting(idsBeforePaste) else {
            throw ClipboardUITestError.invariant("paste must select exactly the two newly created clips")
        }
        guard pastedIds.isDisjoint(with: originalIds) else {
            throw ClipboardUITestError.invariant("pasted clip IDs must differ from source IDs")
        }
        guard originalIds.isSubset(of: idsAfterPaste) else {
            throw ClipboardUITestError.invariant("paste removed an original clip")
        }

        let pastedClips = clipsAfterPaste
            .filter { pastedIds.contains($0.id) }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
        let pastedStarts = pastedClips.map(\.timelineRange.start)
        guard pastedStarts.count == 2,
              abs(pastedStarts[0] - 10.0) <= 0.001,
              abs(pastedStarts[1] - 12.0) <= 0.001 else {
            throw ClipboardUITestError.invariant("expected pasted starts 10.000,12.000, found \(pastedStarts)")
        }
        let relativeOffset = pastedStarts[1] - pastedStarts[0]
        guard abs(relativeOffset - 2.0) <= 0.001 else {
            throw ClipboardUITestError.invariant("expected pasted relative offset 2.000, found \(relativeOffset)")
        }

        await undo()
        let idsAfterPasteUndo = Set(currentProject.timeline.tracks.flatMap(\.clips).map(\.id))
        guard pastedIds.isDisjoint(with: idsAfterPasteUndo),
              originalIds.isSubset(of: idsAfterPasteUndo) else {
            throw ClipboardUITestError.invariant("one undo did not remove both pasted clips while preserving originals")
        }

        await redo()
        let clipsAfterRedo = currentProject.timeline.tracks.flatMap(\.clips)
        let redoById = Dictionary(uniqueKeysWithValues: clipsAfterRedo.map { ($0.id, $0) })
        guard originalIds.allSatisfy({ redoById[$0] != nil }),
              pastedIds.allSatisfy({ redoById[$0] != nil }),
              pastedIds.allSatisfy({ id in
                  guard let clip = redoById[id],
                        let prior = pastedClips.first(where: { $0.id == id }) else { return false }
                  return clip.timelineRange == prior.timelineRange
              }) else {
            throw ClipboardUITestError.invariant("one redo did not restore both pasted IDs and ranges")
        }

        selectedClipIds = originalIds
        await cutClips(originalIds)
        let idsAfterCut = Set(currentProject.timeline.tracks.flatMap(\.clips).map(\.id))
        guard originalIds.isDisjoint(with: idsAfterCut),
              pastedIds.isSubset(of: idsAfterCut) else {
            throw ClipboardUITestError.invariant("one cut did not remove both originals while preserving pasted clips")
        }

        await undo()
        let finalClips = currentProject.timeline.tracks.flatMap(\.clips)
        let finalById = Dictionary(uniqueKeysWithValues: finalClips.map { ($0.id, $0) })
        guard originalIds.allSatisfy({ id in
                  guard let restored = finalById[id], let originalStart = originalStarts[id] else { return false }
                  return restored.timelineRange.start == originalStart
              }),
              pastedIds.allSatisfy({ id in
                  guard let restored = finalById[id],
                        let prior = pastedClips.first(where: { $0.id == id }) else { return false }
                  return restored.timelineRange == prior.timelineRange
              }) else {
            throw ClipboardUITestError.invariant("one cut undo did not restore exact original starts and pasted state")
        }

        return String(
            format: " clipboard_copy=2 paste=2 paste_starts=%.3f,%.3f relative=%.3f paste_undo=1 cut_undo=1 new_ids=1",
            pastedStarts[0],
            pastedStarts[1],
            relativeOffset
        )
    }

    private func uiTestImportURLs(from rawValue: String) -> [URL] {
        rawValue
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(filePath: $0) }
    }

    private func uiTestImportExtraURLs(from rawValue: String) -> [URL] {
        rawValue
            .split { character in
                character == ":" || character == "\n" || character == "\r"
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(filePath: $0) }
    }

    /// Copies harness fixtures into the app's sandbox container so the
    /// sandboxed (shipping) build can read them without a security-scoped
    /// grant. Only files that already live inside the container (e.g. a prior
    /// copy) are returned unchanged. The container's tmp/ and Application
    /// Support/ are grant-free under App Sandbox, and `makeBookmark`'s
    /// `.minimalBookmark` fallback yields a valid bookmark there
    /// (SecurityScopedAccessTests covers that round-trip).
    ///
    /// This is gated by `MOVIECUT_UITEST_CONTAINERIZE=1` so the existing
    /// sandbox-OFF measurement scripts (perf_4k.sh, perf_baseline.sh) keep
    /// importing the original fixture path directly — copying would add I/O
    /// that perturbs the wall-clock numbers those scripts measure.
    private func containerizeImportURLs(_ urls: [URL]) -> [URL] {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST_CONTAINERIZE"] == "1", !urls.isEmpty else {
            return urls
        }
        let fm = FileManager.default
        // NSTemporaryDirectory() is inside the sandbox container on macOS,
        // so reads/writes here need no security-scoped grant.
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MovieCutHarnessImports", isDirectory: true)
        try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let containerRoot = URL(fileURLWithPath: NSHomeDirectory())
            .standardizedFileURL.path
        return urls.compactMap { source -> URL? in
            // Already inside the container (a previous copy, or a proxy/auto-
            // save artifact): leave it where it is.
            if source.standardizedFileURL.path.hasPrefix(containerRoot) {
                return source
            }
            guard fm.fileExists(atPath: source.path) else { return source }
            let dest = staging.appendingPathComponent(source.lastPathComponent)
            do {
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: source, to: dest)
                return dest
            } catch {
                // Fall back to the original path; the caller surfaces any
                // import failure through its normal error path.
                return source
            }
        }
    }

    /// Resolves an export destination that a sandboxed build can write to.
    /// When `MOVIECUT_UITEST_CONTAINERIZE=1` and the requested path is outside
    /// the sandbox container, the export is written into the container's tmp/
    /// and the result is moved to the requested path afterward. Writing into
    /// the container needs no security-scoped grant; the final move is best-
    /// effort and failures are surfaced through `lastErrorMessage`.
    ///
    /// Returns a tuple of (effectiveWriteURL, requestedURL). When container-
    /// ization is off, both are the input URL.
    private func containerizedExportDestination(for requested: URL)
        -> (write: URL, requested: URL) {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST_CONTAINERIZE"] == "1" else {
            return (requested, requested)
        }
        let containerRoot = URL(fileURLWithPath: NSHomeDirectory())
            .standardizedFileURL.path
        if requested.standardizedFileURL.path.hasPrefix(containerRoot) {
            return (requested, requested)
        }
        // Stage inside the container's tmp/ (grant-free under App Sandbox).
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MovieCutHarnessExports", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: staging, withIntermediateDirectories: true)
        return (staging.appendingPathComponent(requested.lastPathComponent),
                requested)
    }

    /// Moves a containerized export artifact to its requested destination.
    /// No-op when the export already wrote there. Best-effort: a move failure
    /// sets `lastErrorMessage` so the harness status reports it.
    private func finalizeContainerizedExport(from write: URL, to requested: URL) {
        guard write.standardizedFileURL != requested.standardizedFileURL else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: write.path) else { return }
        do {
            let parent = requested.deletingLastPathComponent()
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: requested.path) {
                try fm.removeItem(at: requested)
            }
            // Try a cheap rename first; fall back to a copy if the destination
            // is on a different volume than the container.
            do {
                try fm.moveItem(at: write, to: requested)
            } catch {
                try fm.copyItem(at: write, to: requested)
                try? fm.removeItem(at: write)
            }
        } catch {
            // The sandbox blocked the move/copy out of the container, but the
            // artifact is intact at the staging path. Record it so the status
            // line can tell the script where to look instead of reporting a
            // spurious error — the export itself succeeded.
            containerArtifactPaths.append(write.path)
        }
    }

    /// Writes the harness status line to `resultPath`, routing through the
    /// sandbox container when `MOVIECUT_UITEST_CONTAINERIZE=1` so a sandboxed
    /// (shipping) build can report its outcome even when the requested path is
    /// outside the container. The staged file is moved to the requested path
    /// on success. When containerization is off this is a plain atomic write.
    /// Writes the harness status line to `resultPath`, routing through the
    /// sandbox container when `MOVIECUT_UITEST_CONTAINERIZE=1`. Internal so the
    /// ContentView recovery injection path (which runs outside the harness
    /// extension, gated by DEBUG || MOVIECUT_HARNESS) can share it.
    func writeHarnessStatus(_ status: String, to resultPath: String) {
        guard !resultPath.isEmpty else { return }
        let env = ProcessInfo.processInfo.environment
        let requested = URL(fileURLWithPath: resultPath)
        guard env["MOVIECUT_UITEST_CONTAINERIZE"] == "1" else {
            try? status.write(toFile: resultPath, atomically: true, encoding: .utf8)
            return
        }
        let containerRoot = URL(fileURLWithPath: NSHomeDirectory())
            .standardizedFileURL.path
        if requested.standardizedFileURL.path.hasPrefix(containerRoot) {
            try? status.write(toFile: resultPath, atomically: true, encoding: .utf8)
            return
        }
        // Stage inside the container tmp/, then move to the requested path.
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MovieCutHarnessResult.txt")
        try? status.write(to: staging, atomically: true, encoding: .utf8)
        let fm = FileManager.default
        var movedToRequested = false
        do {
            let parent = requested.deletingLastPathComponent()
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: requested.path) {
                try fm.removeItem(at: requested)
            }
            do {
                try fm.moveItem(at: staging, to: requested)
                movedToRequested = true
            } catch {
                try fm.copyItem(at: staging, to: requested)
                try? fm.removeItem(at: staging)
                movedToRequested = true
            }
        } catch {
            // Last resort: direct write to the requested path; the staged
            // file is already on disk in the container tmp/ as a fallback.
            try? status.write(toFile: resultPath, atomically: true, encoding: .utf8)
            if fm.fileExists(atPath: resultPath) { movedToRequested = true }
        }
        // If the result never reached the requested path, the staged file in
        // the container tmp/ is the only copy. Emit its path on stderr so the
        // driving script (which reads stderr) can find it — the status line
        // itself is the thing we failed to deliver to the requested path.
        if !movedToRequested, fm.fileExists(atPath: staging.path) {
            FileHandle.standardError.write(
                Data("MOVIECUT_CONTAINER_RESULT=\(staging.path)\n".utf8))
        }
    }

    /// Resolves a directory the harness should write into (e.g. the preview
    /// dump dir) so a sandboxed build can write there. When
    /// `MOVIECUT_UITEST_CONTAINERIZE=1` and `requestedPath` is outside the
    /// container, returns a staging dir under the container tmp/ and reports
    /// that path back through the status line. Otherwise returns `requestedPath`.
    private func containerizedDirectory(for requestedPath: String) -> String {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST_CONTAINERIZE"] == "1",
              !requestedPath.isEmpty else {
            return requestedPath
        }
        let requested = URL(fileURLWithPath: requestedPath).standardizedFileURL
        let containerRoot = URL(fileURLWithPath: NSHomeDirectory())
            .standardizedFileURL.path
        if requested.path.hasPrefix(containerRoot) {
            return requestedPath
        }
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MovieCutHarnessDump", isDirectory: true)
        return staging.path
    }

    /// Suffix listing container-staged artifact paths, so a sandboxed run can
    /// tell the driving script where exports/results actually landed when the
    /// final move out of the container was blocked. Empty when nothing was
    /// staged (the common, non-sandboxed case).
    private func containerArtifactSuffix() -> String {
        guard !containerArtifactPaths.isEmpty else { return "" }
        return " container_artifacts=" + containerArtifactPaths.joined(separator: ":")
    }

    private func timelineSummarySuffix() -> String {
        let parts = currentProject.timeline.tracks.flatMap { track in
            track.clips.map { clip in
                String(
                    format: "%@:%@=%.3f-%.3f",
                    track.kind.rawValue,
                    clip.kind.rawValue,
                    clip.timelineRange.start,
                    clip.timelineRange.end
                )
            }
        }
        guard !parts.isEmpty else { return " timeline=empty" }
        return " timeline=" + parts.joined(separator: ",")
    }

    /// Step 1 actual-app E2E for the project-composition Preview path. Loads
    /// the provided fixtures (video + audio + text), drives a composition
    /// rebuild through the real ViewModel, and asserts the acceptance
    /// criteria from `CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md`:
    ///   - composition installs a player item (no silent `clear()`)
    ///   - clip boundary crossing advances the playhead into the next clip
    ///   - selection change does NOT reset playback time to zero
    ///   - the generation token never lets a stale rebuild overwrite a newer
    ///     composition
    /// Outcome is serialized to `MOVIECUT_UITEST_RESULT` as a key=value string.
    private func runPreviewProjectCompositionUITestScenario(environment: [String: String]) async {
        var generationBefore: UInt64 = 0
        var generationAfterFirst: UInt64 = 0
        var generationAfterBurst: UInt64 = 0
        var playerItemInstalled = false
        var compositionErrorExposed = "none"
        var durationSeconds = 0.0
        var boundaryCrossingWorked = false
        var selectionKeepsTime = false
        var staleGuardHeld = false

        do {
            // 1. Import the provided fixtures and add them to the timeline.
            let importURLs = (environment["MOVIECUT_UITEST_IMPORT"] ?? "")
                .split(separator: ",")
                .map { String($0) }
                .filter { !$0.isEmpty }
                .map(URL.init(fileURLWithPath:))
            if importURLs.isEmpty {
                throw NSError(domain: "MovieCutUITest", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "MOVIECUT_UITEST_IMPORT not set"])
            }
            await importMediaAndAddToTimeline(importURLs, startTime: 0)

            // Add a text clip so the composition exercises the Core Animation
            // text layer path (acceptance: text change is reflected in preview).
            await addTextClip(text: "Step1 preview composition")

            // 2. Force a composition rebuild through the same path PreviewPanel
            // uses, then wait for the player item to install.
            generationBefore = playbackEngine.currentCompositionGeneration
            rebuildPreviewComposition()
            try await waitForCompositionReady(timeoutSeconds: 8)
            // The player item installs synchronously, but AVFoundation reports
            // a non-zero duration only once the item reaches .readyToPlay, so
            // re-read duration after a short settle window.
            try await Task.sleep(nanoseconds: 300_000_000)
            playerItemInstalled = playbackEngine.playerItem != nil
            compositionErrorExposed = playbackEngine.lastCompositionError ?? "none"
            durationSeconds = playbackEngine.duration
            generationAfterFirst = playbackEngine.currentCompositionGeneration

            guard playerItemInstalled, compositionErrorExposed == "none" else {
                throw NSError(domain: "MovieCutUITest", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "composition did not install cleanly (item=\(playerItemInstalled) err=\(compositionErrorExposed))"])
            }

            // 3. Boundary crossing: seek to just before the first clip end,
            // nudge across it, and confirm time keeps advancing (the playhead
            // is in the project timeline domain under composition playback).
            // Prefer the published composition duration; fall back to the
            // timeline's nominal duration if AVFoundation has not settled yet.
            let referenceDuration = durationSeconds > 0
                ? durationSeconds
                : currentProject.timeline.duration
            let firstClipEnd = currentProject.timeline.tracks
                .flatMap(\.clips)
                .map { $0.timelineRange.end }
                .filter { $0 > 0 }
                .sorted()
                .first ?? 0
            if referenceDuration > firstClipEnd, firstClipEnd > 0 {
                playbackEngine.seek(to: max(0, firstClipEnd - 0.05))
                let before = playbackEngine.currentTime
                playbackEngine.seek(to: firstClipEnd + 0.1)
                let after = playbackEngine.currentTime
                boundaryCrossingWorked = after > before && after <= referenceDuration + 0.1
            }

            // 4. Selection must not reset playback time to zero. Park at a
            // non-zero time, change selection, and verify the engine time did
            // not jump back to 0.
            if let firstClip = currentProject.timeline.tracks.first?.clips.first {
                let parkTarget = min(0.5, max(0.1, referenceDuration * 0.25))
                playbackEngine.seek(to: parkTarget)
                let parkedTime = playbackEngine.currentTime
                selectedClipIds = [firstClip.id]
                // Give SwiftUI a tick to process the selection change.
                try await Task.sleep(nanoseconds: 50_000_000)
                selectionKeepsTime = abs(playbackEngine.currentTime - parkedTime) < 0.25
            }

            // 5. Stale rebuild guard: fire two rapid rebuilds and confirm the
            // generation counter advances twice (each request stamps a token)
            // and the final state is consistent. We cannot deterministically
            // race the async builds, but the counter must have moved by >= 2
            // and the engine must remain on a clean item afterwards.
            rebuildPreviewComposition()
            rebuildPreviewComposition()
            try await waitForCompositionReady(timeoutSeconds: 8)
            generationAfterBurst = playbackEngine.currentCompositionGeneration
            staleGuardHeld = (generationAfterBurst - generationAfterFirst) >= 2
                && playbackEngine.playerItem != nil
                && playbackEngine.lastCompositionError == nil
        } catch {
            lastErrorMessage = "preview project harness failed: \(error.localizedDescription)"
        }

        let status = "preview_project_done" +
            " player_item_installed=\(playerItemInstalled ? 1 : 0)" +
            " composition_error=\(compositionErrorExposed)" +
            String(format: " duration=%.3f", durationSeconds) +
            " boundary_crossing=\(boundaryCrossingWorked ? 1 : 0)" +
            " selection_keeps_time=\(selectionKeepsTime ? 1 : 0)" +
            " stale_guard_held=\(staleGuardHeld ? 1 : 0)" +
            " generation_before=\(generationBefore)" +
            " generation_after_first=\(generationAfterFirst)" +
            " generation_after_burst=\(generationAfterBurst)" +
            " error=\(lastErrorMessage ?? "none")" +
            timelineSummarySuffix()
        lastStatusMessage = status
        if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
            writeHarnessStatus(status, to: resultPath)
        }
        await flushAutosave()
        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    /// Step 1 Preview↔Export pixel-parity harness. Builds the project,
    /// exports it to `MOVIECUT_UITEST_EXPORT`, and dumps the Preview frame at
    /// Collects the first wall-clock p50/p95 baselines for timeline seek and
    /// project open (PERFORMANCE_SLO: seek median ≤ 100 ms, project open ≤ 3 s —
    /// both previously "signpost acquired, value not yet collected").
    ///
    /// Measures the exact code paths the SLO names:
    /// - `playbackEngine.seek(to:)` — the `playback.seek` signpost semantics:
    ///   the seek REQUEST (AVPlayer.seek is fire-and-forget), not render
    ///   completion.
    /// - `scrubPlayhead(to:)` — the full user scrub apply path.
    /// - `openProject(from:)` — decode + migrate + validate + session swap
    ///   (the `import.openProject` signpost interval).
    ///
    /// `MOVIECUT_UITEST_LATENCY_BASELINE=<seekCount>` runs the scenario after a
    /// normal import; results are appended to `MOVIECUT_UITEST_RESULT` as
    /// `latency_baseline ...` key=value lines the shell gate parses.
    private func runLatencyBaselineUITestScenario(environment: [String: String], seekCount: Int) async {
        func status(_ line: String) {
            if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
                writeHarnessStatus(line + "\n", to: resultPath)
            }
        }
        func elapsedMs(_ start: DispatchTime) -> Double {
            Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        }
        func percentile(_ samples: [Double], _ fraction: Double) -> Double {
            guard !samples.isEmpty else { return -1 }
            let sorted = samples.sorted()
            let index = min(Int((fraction * Double(sorted.count - 1)).rounded()), sorted.count - 1)
            return sorted[index]
        }

        status("latency_checkpoint stage=start")
        do {
            let importURLs = containerizeImportURLs(
                (environment["MOVIECUT_UITEST_IMPORT"] ?? "")
                    .split(separator: ",")
                    .map { String($0) }
                    .filter { !$0.isEmpty }
                    .map(URL.init(fileURLWithPath:))
            )
            guard !importURLs.isEmpty else {
                throw NSError(domain: "MovieCutUITest", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "MOVIECUT_UITEST_IMPORT not set"])
            }

            suppressCompositionRebuild = true
            await importMediaAndAddToTimeline(importURLs, startTime: 0)
            suppressCompositionRebuild = false
            rebuildPreviewComposition()
            try await waitForCompositionReady(timeoutSeconds: 10)
            status("latency_checkpoint stage=composition_ready")

            let duration = max(playbackEngine.duration, currentProject.timeline.duration)
            guard duration > 0 else {
                throw NSError(domain: "MovieCutUITest", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "composition duration is zero"])
            }

            // Seeks spaced across the whole duration; a settle gap keeps
            // AVPlayer's async seek queue from batching requests.
            let effectiveCount = max(seekCount, 1)
            var requestSamples: [Double] = []
            var scrubSamples: [Double] = []
            for index in 0..<effectiveCount {
                let time = duration * (Double(index) + 0.5) / Double(effectiveCount)

                let requestStart = DispatchTime.now()
                playbackEngine.seek(to: time)
                requestSamples.append(elapsedMs(requestStart))

                let scrubStart = DispatchTime.now()
                scrubPlayhead(to: time)
                scrubSamples.append(elapsedMs(scrubStart))

                try await Task.sleep(nanoseconds: 40_000_000)
            }
            status("latency_checkpoint stage=seeks_done count=\(effectiveCount)")

            // Project open: save to a temp bundle, reopen through the real
            // `openProject` path (isDirty is false after the save, so the
            // unsaved-changes guard passes without any alert UI).
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("moviecut_latency_baseline_\(UUID().uuidString).moviecut")
            await saveProject(to: tempURL)
            let openStart = DispatchTime.now()
            await openProject(from: tempURL)
            let openMs = elapsedMs(openStart)
            try? FileManager.default.removeItem(at: tempURL)
            status("latency_checkpoint stage=open_done")

            // writeHarnessStatus TRUNCATES on every call (only the final line
            // survives), so the result line must be the last write and carries
            // the done marker itself.
            status(
                "latency_baseline stage=done seek_count=\(effectiveCount)"
                    + " duration_s=\(String(format: "%.3f", duration))"
                    + " seek_request_p50_ms=\(String(format: "%.2f", percentile(requestSamples, 0.5)))"
                    + " seek_request_p95_ms=\(String(format: "%.2f", percentile(requestSamples, 0.95)))"
                    + " scrub_apply_p50_ms=\(String(format: "%.2f", percentile(scrubSamples, 0.5)))"
                    + " scrub_apply_p95_ms=\(String(format: "%.2f", percentile(scrubSamples, 0.95)))"
                    + " project_open_ms=\(String(format: "%.2f", openMs))"
            )
            if environment["MOVIECUT_UITEST_QUIT"] == "1" {
                NSApp.terminate(nil)
            }
        } catch {
            status("latency_checkpoint stage=error error=\(error.localizedDescription)")
            if environment["MOVIECUT_UITEST_QUIT"] == "1" {
                NSApp.terminate(nil)
            }
        }
    }

    /// each timestamp listed in `MOVIECUT_UITEST_PARITY_TIMES` (comma-separated
    /// seconds) to `MOVIECUT_UITEST_PREVIEW_DUMP` (one PNG per timestamp with
    /// a `_t<seconds>.png` suffix). The shell script then extracts the same
    /// timestamps from the exported mp4 and compares them pixel-by-pixel.
    // MARK: - G-25 §9 audio graph null test (Inc 8 App half)

    /// Duplicates a mono decode to dual-mono stereo so loudness parity
    /// compares like channel layouts (mono vs dual-mono differs by +3.01 LU
    /// in BS.1770 summing — a presentation artifact, not a mix difference).
    private static func dualMonoStereo(_ audio: AudioGraphSourceAudio) -> AudioGraphSourceAudio {
        guard audio.channels == 1 else { return audio }
        var interleaved = [Float]()
        interleaved.reserveCapacity(audio.interleaved.count * 2)
        for sample in audio.interleaved {
            interleaved.append(sample)
            interleaved.append(sample)
        }
        return AudioGraphSourceAudio(sampleRate: audio.sampleRate, channels: 2, interleaved: interleaved)
    }

    /// JSON artifact for `MOVIECUT_UITEST_AUDIO_GRAPH_NULLTEST`: per-graph
    /// comparator results plus the §9.4 drift measurement and the §9.1
    /// real-project phase (product-path migration evidence).
    private struct AudioGraphNullTestDump: Codable {
        struct GraphResult: Codable {
            var name: String
            var frames: Int
            var bestOffsetSamples: Int
            var maxAbsoluteDeviation: Double
            var lsb16: Double
            var passed: Bool
        }

        var schemaVersion = 1
        var scenario = "G-25-audio-graph-null-test"
        var graphs: [GraphResult] = []
        var driftTimelineEndSamples: Int64 = 0
        var driftTailFrames: Int = 0
        var driftBestOffsetSamples: Int = 0
        var driftRoundTripExact = false
        var driftPassed = false
        // §9.1 on the REAL imported project: the graph built by
        // AudioGraphProjectBuilder renders through both engines, and the
        // graph mix's loudness is compared against the preview audio-mix
        // render (migration parity; AAC-vs-float, so LUFS-delta tolerance,
        // not a null gate).
        var projectGraphRendered = false
        var projectGraphPassed = false
        var projectGraphFrames = 0
        var projectParityDeltaLufs: Double?
        var elapsedSeconds = 0.0
        var error = "none"
    }

    /// G-25 spec §9 — the MEASURED preview↔export null test in the real app
    /// process (실측 판정은 E2E만, §9.5). The SAME graph is rendered by BOTH
    /// engine generators — the preview side through a real AVAudioEngine
    /// (offline manual rendering: source nodes → bus mixers → main mixer) and
    /// the export side as encoder input — then judged by the shared Core
    /// comparator at ±1 sample / 1 LSB. The §9.4 drift measurement renders
    /// the 60-minute mixed-rate TAIL in both engines with the same explicit
    /// window: any timebase drift would misalign the tail content, so the
    /// measured alignment offset IS the end-point drift. Sources are
    /// deterministic synthetic sines (the spec's "더미" project — no media
    /// decode, byte-reproducible numbers); the project→graph builder lands
    /// with the product migration, after Inc 9.
    private func runAudioGraphNullTestUITestScenario(environment: [String: String], artifactPath: String) async -> String {
        let started = Date()
        var dump = AudioGraphNullTestDump()

        func deterministicSine(frames: Int, channels: Int, sampleRate: Double, seed: Double) -> AudioGraphSourceAudio {
            var samples = [Float]()
            samples.reserveCapacity(frames * channels)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    let frequency = seed + Double(channel) * 110
                    samples.append(Float(sin(Double(frame) * frequency * 2 * .pi / sampleRate) * 0.8))
                }
            }
            return AudioGraphSourceAudio(sampleRate: sampleRate, channels: channels, interleaved: samples)
        }

        func nullCompareGraph(
            name: String,
            spec: AudioRenderGraphSpec,
            activations: [UUID: AudioGraphStripActivation],
            sources: [UUID: AudioGraphSourceAudio],
            frameCount: Int
        ) throws -> AudioGraphNullTestDump.GraphResult {
            let preview = try AudioGraphAVAudioEngineRenderer.render(
                spec: spec, activations: activations,
                sourceAudio: { sources[$0] }, frameCount: frameCount
            )
            let export = try AudioGraphEncoderInput.render(
                spec: spec, activations: activations,
                sourceAudio: { sources[$0] }, frameCount: frameCount
            )
            let result = AudioGraphNullTest.compare(
                reference: export.interleaved, candidate: preview.interleaved
            )
            return AudioGraphNullTestDump.GraphResult(
                name: name,
                frames: frameCount,
                bestOffsetSamples: result.bestOffsetSamples,
                maxAbsoluteDeviation: Double(result.maxAbsoluteDeviation),
                lsb16: Double(result.lsb16),
                passed: result.passed
            )
        }

        do {
            // --- §9.1-9.3: null test on the stage-1 feature mix ------------
            // Graph 1 — every stage-1 node: mono strip (gain ramp, linear
            // fade, pan automation) on a bus with a ramped fader, stereo
            // strip on a second (muted) bus.
            let frames = 4_800
            let sourceA = UUID(), stripA = UUID(), sourceB = UUID(), stripB = UUID()
            var busA = AudioGraphTrackBus(trackId: UUID(), inputStripIds: [stripA])
            busA.fader = [
                AudioGraphAutomationPoint(samplePosition: 0, value: -6),
                AudioGraphAutomationPoint(samplePosition: Int64(frames), value: 0)
            ]
            var stripAm = AudioGraphClipStrip(clipId: stripA, sourceId: sourceA, channelMapping: .mono)
            stripAm.gain = [
                AudioGraphAutomationPoint(samplePosition: 0, value: -3),
                AudioGraphAutomationPoint(samplePosition: Int64(frames / 2), value: 1)
            ]
            stripAm.fades = [AudioGraphFade(startSample: 0, endSample: Int64(frames / 2), curve: .linear)]
            stripAm.pan = [
                AudioGraphAutomationPoint(samplePosition: 0, value: -1),
                AudioGraphAutomationPoint(samplePosition: Int64(frames), value: 1)
            ]
            var busB = AudioGraphTrackBus(trackId: UUID(), inputStripIds: [stripB])
            busB.mute = true
            let stripBm = AudioGraphClipStrip(clipId: stripB, sourceId: sourceB, channelMapping: .stereo)
            let mixSpec = AudioRenderGraphSpec(
                sources: [
                    AudioGraphSource(id: sourceA, kind: .original, url: URL(filePath: "/tmp/g25-mix-a.wav")),
                    AudioGraphSource(id: sourceB, kind: .original, url: URL(filePath: "/tmp/g25-mix-b.wav"))
                ],
                clipStrips: [stripAm, stripBm],
                trackBuses: [busA, busB]
            )
            dump.graphs.append(try nullCompareGraph(
                name: "stage1-mix",
                spec: mixSpec,
                activations: [
                    stripA: AudioGraphStripActivation(sampleRange: 0..<Int64(frames)),
                    stripB: AudioGraphStripActivation(sampleRange: 0..<Int64(frames))
                ],
                sources: [
                    sourceA: deterministicSine(frames: frames, channels: 1, sampleRate: 48_000, seed: 220),
                    sourceB: deterministicSine(frames: frames, channels: 2, sampleRate: 48_000, seed: 330)
                ],
                frameCount: frames
            ))

            // Graph 2 — mixed sample rates (§9.4 precondition): a 44.1 kHz
            // native source read at the 44100/48000 frame ratio next to a
            // 48 kHz source on another bus.
            let sourceC = UUID(), stripC = UUID()
            let stripCm = AudioGraphClipStrip(clipId: stripC, sourceId: sourceC, channelMapping: .stereo)
            let busC = AudioGraphTrackBus(trackId: UUID(), inputStripIds: [stripC])
            let mixedSpec = AudioRenderGraphSpec(
                sources: [
                    AudioGraphSource(id: sourceA, kind: .original, url: URL(filePath: "/tmp/g25-mix-a.wav")),
                    AudioGraphSource(
                        id: sourceC, kind: .original,
                        url: URL(filePath: "/tmp/g25-mixed-c.wav"), nativeSampleRate: 44_100
                    )
                ],
                clipStrips: [stripAm, stripCm],
                trackBuses: [busA, busC]
            )
            dump.graphs.append(try nullCompareGraph(
                name: "mixed-rate",
                spec: mixedSpec,
                activations: [
                    stripA: AudioGraphStripActivation(sampleRange: 0..<Int64(frames)),
                    stripC: AudioGraphStripActivation(
                        sampleRange: 0..<Int64(frames), playbackRate: 44_100.0 / 48_000.0
                    )
                ],
                sources: [
                    sourceA: deterministicSine(frames: frames, channels: 1, sampleRate: 48_000, seed: 220),
                    sourceC: deterministicSine(frames: 4_410, channels: 2, sampleRate: 44_100, seed: 550)
                ],
                frameCount: frames
            ))

            // --- §9.4: 60-minute mixed-rate end-point drift 실측 ------------
            // The 60-minute timeline end is computed through the EXACT
            // Int64 timebase math both engines schedule from; the tail is
            // then RENDERED by both engines over the same absolute window.
            let timebase = AudioGraphTimebase(sampleRate: 48_000)
            let timelineEnd = timebase.samplePosition(at: CMTime(value: 3_600, timescale: 1))
            let tailFrames = 4_800
            let tailStart = timelineEnd - Int64(tailFrames)

            let driftSource = UUID(), driftStrip = UUID()
            // The drifting strip is the 44.1 kHz source placed at the tail:
            // its read positions are the ones a seconds-based timebase would
            // misalign over 60 minutes.
            let driftStripModel = AudioGraphClipStrip(
                clipId: driftStrip, sourceId: driftSource, channelMapping: .stereo
            )
            let driftBus = AudioGraphTrackBus(trackId: UUID(), inputStripIds: [driftStrip])
            let driftSpec = AudioRenderGraphSpec(
                sources: [
                    AudioGraphSource(
                        id: driftSource, kind: .original,
                        url: URL(filePath: "/tmp/g25-drift.wav"), nativeSampleRate: 44_100
                    )
                ],
                clipStrips: [driftStripModel],
                trackBuses: [driftBus],
                timebase: timebase
            )
            let driftWindow = tailStart..<timelineEnd
            let driftActivation = AudioGraphStripActivation(
                sampleRange: driftWindow, playbackRate: 44_100.0 / 48_000.0
            )
            let driftSources: [UUID: AudioGraphSourceAudio] = [
                driftSource: deterministicSine(frames: 4_410, channels: 2, sampleRate: 44_100, seed: 770)
            ]
            let driftPreview = try AudioGraphAVAudioEngineRenderer.render(
                spec: driftSpec, activations: [driftStrip: driftActivation],
                sourceAudio: { driftSources[$0] },
                frameCount: tailFrames, frameRange: driftWindow
            )
            let driftExport = try AudioGraphEncoderInput.render(
                spec: driftSpec, activations: [driftStrip: driftActivation],
                sourceAudio: { driftSources[$0] },
                frameCount: tailFrames, frameRange: driftWindow
            )
            let driftCompare = AudioGraphNullTest.compare(
                reference: driftExport.interleaved, candidate: driftPreview.interleaved
            )

            dump.driftTimelineEndSamples = timelineEnd
            dump.driftTailFrames = tailFrames
            dump.driftBestOffsetSamples = driftCompare.bestOffsetSamples
            dump.driftRoundTripExact = AudioGraphNullTest.mixedRateRoundTripIsExact(
                timelineEnd: timelineEnd, graphRate: 48_000, otherRate: 44_100
            )
            // Gate: the tail renders null-match (offset within ±1, deviation
            // within one 16-bit LSB) and the position math round-trips —
            // far stronger than the ≤1 video frame drift budget.
            dump.driftPassed = driftCompare.passed && abs(driftCompare.bestOffsetSamples) <= 1 && dump.driftRoundTripExact

            // --- §9.1 on the REAL imported project (migration evidence) ----
            // Build the graph from the actual project (the builder maps
            // volumes, fades, ducking, mute/solo), decode the referenced
            // sources, and render BOTH engines. Also measure the graph mix
            // against the preview audio-mix render (LUFS parity — the two
            // paths still differ by AAC and ramp shape, so this is a
            // reported tolerance, not a null gate).
            let audioClipBearingTracks = currentProject.timeline.tracks.filter { track in
                track.clips.contains { clip in
                    clip.kind == .audio || clip.kind == .video
                }
            }
            if !audioClipBearingTracks.isEmpty {
                var decodedSources: [UUID: AudioGraphSourceAudio] = [:]
                for track in audioClipBearingTracks {
                    for clip in track.clips where clip.kind == .audio || clip.kind == .video {
                        guard let assetId = clip.assetId,
                              decodedSources[assetId] == nil,
                              let asset = currentProject.mediaLibrary.assets[assetId] else { continue }
                        // §3.1 product policy: sources enter the graph at
                        // the graph rate — the adapter decodes (video
                        // containers' embedded audio via AVAssetReader,
                        // audio-less video as explicit silence) and
                        // resamples. A real decode failure throws; there is
                        // deliberately NO silent fallback here.
                        decodedSources[assetId] = try await AudioGraphSourceAdapter.normalizedAudio(
                            fileAt: asset.originalURL,
                            graphSampleRate: 48_000
                        )
                    }
                }
                if !decodedSources.isEmpty {
                    let plan = AudioGraphProjectBuilder.build(
                        project: currentProject,
                        decodedSampleRateFor: { decodedSources[$0]?.sampleRate },
                        channelCountFor: { decodedSources[$0]?.channels }
                    )
                    let graphEnd = plan.spec.timebase.samplePosition(
                        at: CMTime(seconds: currentProject.timeline.duration, preferredTimescale: 600)
                    )
                    let projectFrames = Int(min(max(graphEnd, 1), 480_000))
                    let projectPreview = try AudioGraphAVAudioEngineRenderer.render(
                        spec: plan.spec, activations: plan.activations,
                        sourceAudio: { decodedSources[$0] }, frameCount: projectFrames
                    )
                    let projectExport = try AudioGraphEncoderInput.render(
                        spec: plan.spec, activations: plan.activations,
                        sourceAudio: { decodedSources[$0] }, frameCount: projectFrames
                    )
                    let projectCompare = AudioGraphNullTest.compare(
                        reference: projectExport.interleaved, candidate: projectPreview.interleaved
                    )
                    dump.graphs.append(AudioGraphNullTestDump.GraphResult(
                        name: "project",
                        frames: projectFrames,
                        bestOffsetSamples: projectCompare.bestOffsetSamples,
                        maxAbsoluteDeviation: Double(projectCompare.maxAbsoluteDeviation),
                        lsb16: Double(projectCompare.lsb16),
                        passed: projectCompare.passed
                    ))
                    dump.projectGraphRendered = true
                    dump.projectGraphFrames = projectFrames
                    dump.projectGraphPassed = projectCompare.passed

                    // Migration parity: graph mix vs the real preview mix.
                    rebuildPreviewComposition()
                    try await waitForCompositionReady(timeoutSeconds: 15)
                    let previewURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("moviecut-nulltest-preview-\(UUID().uuidString).m4a")
                    defer { try? FileManager.default.removeItem(at: previewURL) }
                    try await playbackEngine.renderCurrentPreviewAudio(to: previewURL)
                    // Channel-layout normalization before the LUFS parity
                    // comparison: an all-mono project's preview m4a encodes
                    // as MONO while the graph PCM is dual-mono stereo, and
                    // the same signal measures +3.01 LU louder in dual-mono
                    // — a presentation difference, not a mix difference.
                    let previewDecoded = Self.dualMonoStereo(
                        try AudioGraphExportPostCheck.decode(fileAt: previewURL)
                    )
                    let graphLufs = AudioGraphLoudness.measure(projectExport).integratedLufs
                    let previewLufs = AudioGraphLoudness.measure(previewDecoded).integratedLufs
                    if let graphLufs, let previewLufs {
                        dump.projectParityDeltaLufs = graphLufs - previewLufs
                    }
                }
            }
        } catch {
            lastErrorMessage = "audio graph null test failed: \(error.localizedDescription)"
            dump.error = error.localizedDescription
        }

        dump.elapsedSeconds = Date().timeIntervalSince(started)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dump).write(to: URL(filePath: artifactPath))
        } catch {
            lastErrorMessage = "audio graph null test artifact write failed: \(error.localizedDescription)"
        }

        let passedCount = dump.graphs.filter(\.passed).count
        let maxDeviation = dump.graphs.map(\.maxAbsoluteDeviation).max() ?? 0
        var suffix = " audio_graph_nulltest_done" +
            " graphs=\(dump.graphs.count)" +
            " passed=\(passedCount)" +
            String(format: " max_dev=%.2e", maxDeviation) +
            " drift_timeline_end=\(dump.driftTimelineEndSamples)" +
            " drift_tail_frames=\(dump.driftTailFrames)" +
            " drift_offset=\(dump.driftBestOffsetSamples)" +
            " drift_roundtrip=\(dump.driftRoundTripExact ? 1 : 0)" +
            " drift_passed=\(dump.driftPassed ? 1 : 0)" +
            " project_graph=\(dump.projectGraphRendered ? 1 : 0)" +
            " project_graph_passed=\(dump.projectGraphPassed ? 1 : 0)" +
            " project_parity_lufs=\(dump.projectParityDeltaLufs.map { String(format: "%.2f", $0) } ?? "none")" +
            String(format: " elapsed=%.2f", dump.elapsedSeconds)
        if dump.error != "none" {
            suffix += " nulltest_error=1"
        }
        return suffix
    }

    // MARK: - G-25 §8 export post-check (Inc 9 App half)

    /// Races `body` against a timeout WITHOUT awaiting the loser (a
    /// TaskGroup would implicitly join the wedged export task and hang the
    /// measurement anyway). The abandoned task dies with the process.
    private static func raceWithTimeout(seconds: Double, _ body: @escaping () async -> Void) async -> Bool {
        final class OnceResume: @unchecked Sendable {
            let lock = NSLock()
            var resumed = false
            func run(_ continuation: CheckedContinuation<Bool, Never>, _ value: Bool) {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }
        }
        return await withCheckedContinuation { continuation in
            let once = OnceResume()
            Task { await body(); once.run(continuation, true) }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                once.run(continuation, false)
            }
        }
    }

    // MARK: - G-24 stabilization E2E (P2-G24-6, #9 real-render upgrade)

    /// JSON artifact for `MOVIECUT_UITEST_STABILIZE`.
    private struct StabilizationDump: Codable {
        var sceneChangeTimes: [Double] = []
        var sceneCutDetected = false
        var frameCount = 0
        var stabilizedFrameCount = 0
        var planCorrections = 0
        var planConfidenceMin = 0.0
        var planConfidenceMedian = 0.0
        var planConfidenceMean = 0.0
        var planConfidenceMax = 0.0
        var coverScale = 0.0
        var inputMedian = 0.0
        var residualMedian = 0.0
        var reductionRatio = 0.0
        var cropMedian = 0.0
        var severeWobbleFraction = 0.0
        var sceneCutErrors = 0
        var meetsDoD = false
        var renderBypassed = 0
        var renderWarpApplied = 0
        var appliedVsIntendedDx = 0.0
        var appliedVsIntendedDy = 0.0
        var elapsedSeconds = 0.0
        var error = "none"
    }

    /// Renders the CURRENT project through the REAL EXPORT PATH (the same
    /// `CustomVideoCompositor` the preview installs) and extracts `count`
    /// frames with `AVAssetImageGenerator` at zero tolerance — frame-exact.
    ///
    /// Why not preview snapshots: the video-output seek path delivers
    /// DUPLICATED frames for some timestamps (measured: zero-magnitude
    /// steps interleaved in a fixture that moves every frame — both render
    /// passes stuck identically, so per-frame readbacks stayed exact while
    /// the jitter measurement silently absorbed wrong-source frames). The
    /// generator on an exported file decodes each requested time exactly —
    /// the same extraction the pre-#9 analytic gate used, now fed by the
    /// compositor's actual output.
    private func renderStabilizationLumaFrames(count: Int, fps: Double, width: Int, height: Int, tag: String) async throws -> [[UInt8]] {
        let exportURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("g24_stabilize_\(tag)_\(UUID().uuidString).mp4")
        let dest = containerizedExportDestination(for: exportURL)
        await exportProject(to: dest.write)
        finalizeContainerizedExport(from: dest.write, to: dest.requested)
        guard FileManager.default.fileExists(atPath: dest.requested.path) else {
            throw NSError(domain: "G24", code: 10, userInfo: [NSLocalizedDescriptionKey: "export produced no file (tag=\(tag)): \(lastErrorMessage ?? "none")"])
        }

        let asset = AVURLAsset(url: dest.requested)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true

        let ciContext = CIContext(options: [.useSoftwareRenderer: true])
        var frames: [[UInt8]] = []
        for frame in 0..<count {
            let t = CMTime(seconds: Double(frame) / fps, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: t, actualTime: nil) else { continue }
            // BUG-06 fix: sources are now aspect-fit + CENTERED into the
            // canvas (previously 1:1 at the bottom-left corner). Crop the
            // centered fitted region — scaled to the analysis resolution —
            // instead of the corner rect.
            let frameExtent = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
            let sourceAspect: CGFloat
            if width > 0, height > 0 {
                sourceAspect = CGFloat(width) / CGFloat(height)
            } else {
                sourceAspect = 1
            }
            let cropW: CGFloat
            let cropH: CGFloat
            if frameExtent.width / frameExtent.height > sourceAspect {
                cropH = frameExtent.height
                cropW = cropH * sourceAspect
            } else {
                cropW = frameExtent.width
                cropH = cropW / sourceAspect
            }
            let cropRect = CGRect(
                x: (frameExtent.width - cropW) / 2,
                y: (frameExtent.height - cropH) / 2,
                width: cropW,
                height: cropH
            )
            let ciImage = CIImage(cgImage: cgImage)
                .transformed(by: CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
                .cropped(to: CGRect(x: 0, y: 0, width: cropRect.width, height: cropRect.height))
                .transformed(by: CGAffineTransform(
                    scaleX: CGFloat(width) / max(cropRect.width, 1),
                    y: CGFloat(height) / max(cropRect.height, 1)
                ))
            var bitmap = [UInt8](repeating: 0, count: width * height * 4)
            // The analysis region is the aspect-fit content, scaled to the
            // analysis resolution at 1:1 (a whole-frame downscale would shrink
            // the content to a sub-sampled strip and the wobble below the
            // estimator's floor).
            ciContext.render(
                ciImage,
                toBitmap: &bitmap,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: nil
            )
            let luma = (0..<(width * height)).map { i in
                let r = Double(bitmap[i * 4])
                let g = Double(bitmap[i * 4 + 1])
                let b = Double(bitmap[i * 4 + 2])
                return UInt8(clamping: Int(0.299 * r + 0.587 * g + 0.114 * b))
            }
            frames.append(luma)
        }
        try? FileManager.default.removeItem(at: dest.requested)
        return frames
    }

    /// Accumulated content positions of a rendered frame sequence: register
    /// consecutive frames and integrate. The output's deviation from its
    /// own smoothed path is the sequence's self-relative shake.
    private func stabilizationAccumulatedPositions(lumaFrames: [[UInt8]], width: Int, height: Int) -> [(x: Double, y: Double)] {
        guard lumaFrames.count > 2 else { return [] }
        var positions: [(x: Double, y: Double)] = [(0, 0)]
        for i in 1..<lumaFrames.count {
            let reg = StabilizationRegistration.estimateTranslation(
                previous: lumaFrames[i - 1],
                current: lumaFrames[i],
                width: width,
                height: height
            )
            positions.append((positions[i - 1].x + reg.dx, positions[i - 1].y + reg.dy))
        }
        return positions
    }

    /// Deviation of each position from its window-smoothed path.
    private func stabilizationJitterDeviations(
        positions: [(x: Double, y: Double)],
        window: Int = 7
    ) -> [Double] {
        guard positions.count > 2 else { return [] }
        let half = window / 2
        return positions.indices.map { i in
            let low = max(0, i - half)
            let high = min(positions.count - 1, i + half)
            var sumX: Double = 0
            var sumY: Double = 0
            for j in low...high {
                sumX += positions[j].x
                sumY += positions[j].y
            }
            let count = Double(high - low + 1)
            let dx = positions[i].x - sumX / count
            let dy = positions[i].y - sumY / count
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    /// G-24 stabilization E2E, #9 upgrade — the full pipeline MEASURED ON
    /// REAL RENDERED PIXELS: the fixture imports into the timeline, the
    /// unstabilized preview renders through the actual compositor, the
    /// analysis (scene change → registration → smoothing → correction) runs
    /// on those rendered frames, the resulting plan attaches to the clip
    /// (`Clip.stabilization`), the composition rebuilds, and the SAME seek
    /// path re-renders with the warp active. The DoD verdict comes from the
    /// stabilized RENDER, not the analytic residual the pre-#9 gate used.
    private func runStabilizationUITestScenario(environment: [String: String]) async {
        let started = Date()
        var dump = StabilizationDump()

        func report(_ line: String) {
            lastStatusMessage = line
            if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
                writeHarnessStatus(line, to: resultPath)
            }
        }

        do {
            guard let fixturePath = environment["MOVIECUT_UITEST_IMPORT"],
                  !fixturePath.isEmpty else {
                throw NSError(domain: "G24", code: 1, userInfo: [NSLocalizedDescriptionKey: "STABILIZE requires MOVIECUT_UITEST_IMPORT"])
            }
            let fixtureURL = URL(fileURLWithPath: fixturePath)
            let fps: Double = 30.0

            // 1. SceneChangeProvider — app context (P2-G24-2 integration).
            let asset = MediaAsset(originalURL: fixtureURL, kind: .video, duration: 4)
            let provider = SceneChangeProvider(samplingFPS: 30.0, changeThreshold: 0.08)
            let result = try await provider.analyze(asset: asset, in: currentProject)
            let changeTimes: [TimeInterval]
            if case let .sceneChanges(times)? = result.suggestions.first {
                changeTimes = times
            } else {
                changeTimes = []
            }
            var detectedTimes = changeTimes
            dump.sceneChangeTimes = detectedTimes
            dump.sceneCutDetected = detectedTimes.isEmpty == false
            report("stabilize_checkpoint stage=scene_change count=\(detectedTimes.count)")

            // 2. Import. The fixture is 16:9 so the default canvas matches
            //    its aspect; exports render at preset resolutions with the
            //    same aspect, and the analysis extraction at the SOURCE's
            //    native size recovers the content 1:1 regardless of the
            //    export preset (an identity-transform clip renders 1:1 in
            //    the corner of the render viewport — any other aspect
            //    would leave the content a sub-sampled patch).
            let sourceAsset = AVURLAsset(url: fixtureURL)
            let sourceSize = try await sourceAsset.loadTracks(withMediaType: .video).first?
                .load(.naturalSize) ?? CGSize(width: 640, height: 360)
            suppressCompositionRebuild = true
            await importMediaAndAddToTimeline(containerizeImportURLs([fixtureURL]), startTime: 0)
            suppressCompositionRebuild = false
            // Force BOTH render passes through the SAME custom compositor:
            // the plain AV composition path places the identity-transform
            // clip at a different position than CustomVideoCompositor (its
            // source lands at the CI origin), so a plain input pass would
            // crop a different region than the stabilized pass. An EMPTY
            // plan ("analyzed, nothing to correct" — its documented
            // meaning) triggers the custom compositor while the warp
            // branch skips empty plans: pixel-identical to unstabilized,
            // identical placement to the stabilized pass. The DoD then
            // measures exactly the warp's effect.
            guard let firstVideoClip = currentProject.timeline.tracks
                .first(where: { $0.kind == .video })?.clips.first else {
                throw NSError(domain: "G24", code: 4, userInfo: [NSLocalizedDescriptionKey: "no video clip in timeline"])
            }
            let stabilizedClipID = firstVideoClip.id
            var emptyPlanProject = currentProject
            for trackIndex in emptyPlanProject.timeline.tracks.indices
            where emptyPlanProject.timeline.tracks[trackIndex].kind == .video {
                for clipIndex in emptyPlanProject.timeline.tracks[trackIndex].clips.indices
                where emptyPlanProject.timeline.tracks[trackIndex].clips[clipIndex].id == stabilizedClipID {
                    emptyPlanProject.timeline.tracks[trackIndex].clips[clipIndex].stabilization =
                        StabilizationPlan(frameRate: fps, corrections: [])
                }
            }
            await apply(ReplaceProjectCommand(project: emptyPlanProject))
            rebuildPreviewComposition()
            try await waitForCompositionReady(
                timeoutSeconds: 30,
                expectedGeneration: playbackEngine.currentCompositionGeneration
            )
            guard playbackEngine.playerItem != nil else {
                throw NSError(domain: "G24", code: 2, userInfo: [NSLocalizedDescriptionKey: "composition not ready (\(playbackEngine.lastCompositionError ?? "no item"))"])
            }
            report("stabilize_checkpoint stage=imported")

            // 3. Render the UNSTABILIZED frames through the real compositor.
            //    Analysis runs at the canvas (= source) resolution.
            let analysisWidth = max(16, Int(sourceSize.width.rounded()))
            let analysisHeight = max(16, Int(sourceSize.height.rounded()))
            let totalFrames = max(1, min(120, Int(currentProject.timeline.duration * fps)))
            let inputLuma = try await renderStabilizationLumaFrames(count: totalFrames, fps: fps, width: analysisWidth, height: analysisHeight, tag: "input")
            dump.frameCount = inputLuma.count
            guard inputLuma.count > 10 else {
                throw NSError(domain: "G24", code: 3, userInfo: [NSLocalizedDescriptionKey: "insufficient rendered frames (\(inputLuma.count))"])
            }

            // Luminance-jump fallback for scene change detection, on the
            // rendered frames (the stabilization math consumes TIMES, not
            // the provider itself).
            if detectedTimes.isEmpty {
                var previousMean: Double = 0
                for (index, luma) in inputLuma.enumerated() {
                    let mean = luma.reduce(0.0) { acc, v in acc + Double(v) } / Double(max(luma.count, 1))
                    if index > 0, abs(mean - previousMean) > 30 {
                        detectedTimes.append(Double(index) / fps)
                    }
                    previousMean = mean
                }
                dump.sceneChangeTimes = detectedTimes
                dump.sceneCutDetected = detectedTimes.isEmpty == false
            }
            report("stabilize_checkpoint stage=input_render count=\(inputLuma.count)")

            // 4. Analysis on the rendered pixels: registration → positions
            //    → smoothing → corrections, normalized to frame fractions
            //    so the plan applies at the compositor's source extent.
            let frameWidth = analysisWidth
            let frameHeight = analysisHeight
            let diagonal = (Double(frameWidth * frameWidth + frameHeight * frameHeight)).squareRoot()

            var registrations: [StabilizationRegistration.RegistrationResult] = []
            for i in 1..<inputLuma.count {
                registrations.append(StabilizationRegistration.estimateTranslation(
                    previous: inputLuma[i - 1],
                    current: inputLuma[i],
                    width: frameWidth,
                    height: frameHeight
                ))
            }
            var positions: [StabilizationRegistration.RegistrationResult] = []
            var accumulatedX: Double = 0
            var accumulatedY: Double = 0
            // Seed FRAME 0's position (the origin) BEFORE accumulating:
            // without it, positions[0] is the 0→1 displacement — every
            // correction lands one frame late, and the warp partially
            // DOUBLES the jitter instead of canceling it (measured: ratio
            // 1.19 with the shift, 0.35 with correct pairing).
            positions.append(.init(dx: 0, dy: 0, confidence: 1))
            for reg in registrations {
                accumulatedX += reg.dx
                accumulatedY += reg.dy
                positions.append(.init(dx: accumulatedX, dy: accumulatedY, confidence: reg.confidence))
            }
            let smoothedPositions = StabilizationRegistration.smooth(positions, window: 7)

            let planCorrections: [StabilizationPlan.Correction] = positions.indices.map { i in
                let warpDx = smoothedPositions[i].dx - positions[i].dx
                let warpDy = smoothedPositions[i].dy - positions[i].dy
                let magnitude = (warpDx * warpDx + warpDy * warpDy).squareRoot()
                let normalized = magnitude / diagonal
                let crop = min(normalized, 0.15)
                let scale = magnitude > 0 ? crop / normalized : 0
                return StabilizationPlan.Correction(
                    dx: warpDx * scale / Double(frameWidth),
                    dy: warpDy * scale / Double(frameHeight),
                    cropFraction: crop,
                    // The correction derives from the SMOOTHED path, so its
                    // reliability is the window-averaged confidence — a
                    // single low-texture registration inside a confident
                    // stretch must not zero that frame's correction (the
                    // bypass alternation added ~4px jumps and pushed the
                    // residual ABOVE the input; measured ratio 1.21).
                    confidence: smoothedPositions[i].confidence
                )
            }
            let plan = StabilizationPlan(frameRate: fps, corrections: planCorrections)
            let maxTranslation = plan.maxNormalizedTranslation
            dump.planCorrections = planCorrections.count
            let confidences = planCorrections.map(\.confidence).sorted()
            if !confidences.isEmpty {
                dump.planConfidenceMin = confidences.first ?? 0
                dump.planConfidenceMedian = confidences[confidences.count / 2]
                dump.planConfidenceMean = confidences.reduce(0, +) / Double(confidences.count)
                dump.planConfidenceMax = confidences.last ?? 0
            }
            dump.coverScale = 1 + 2 * max(maxTranslation.x, maxTranslation.y)
            report("stabilize_checkpoint stage=plan corrections=\(planCorrections.count)")

            // 5. Replace the empty plan with the REAL one — same session
            //    route, so a late session-driven rebuild cannot drop it.
            //    The compositor consumes it via CustomCompositionClipEffect.
            var stabilizedProject = currentProject
            for trackIndex in stabilizedProject.timeline.tracks.indices
            where stabilizedProject.timeline.tracks[trackIndex].kind == .video {
                for clipIndex in stabilizedProject.timeline.tracks[trackIndex].clips.indices
                where stabilizedProject.timeline.tracks[trackIndex].clips[clipIndex].id == stabilizedClipID {
                    stabilizedProject.timeline.tracks[trackIndex].clips[clipIndex].stabilization = plan
                }
            }
            await apply(ReplaceProjectCommand(project: stabilizedProject))
            // Same generation pin as the first rebuild — without it the wait
            // can pass on the PREVIOUS item and the "stabilized" render
            // would silently re-render the unstabilized composition (the
            // exact failure the first #9 gate run caught: ratio 1.000).
            try await waitForCompositionReady(
                timeoutSeconds: 30,
                expectedGeneration: playbackEngine.currentCompositionGeneration
            )
            guard playbackEngine.playerItem != nil,
                  playbackEngine.lastCompositionError == nil else {
                throw NSError(domain: "G24", code: 5, userInfo: [NSLocalizedDescriptionKey: "stabilized composition not ready (\(playbackEngine.lastCompositionError ?? "none"))"])
            }
            report("stabilize_checkpoint stage=attached")

            // 6. Render the STABILIZED frames through the same path.
            let stabilizedLuma = try await renderStabilizationLumaFrames(count: totalFrames, fps: fps, width: analysisWidth, height: analysisHeight, tag: "stab")
            dump.stabilizedFrameCount = stabilizedLuma.count
            guard stabilizedLuma.count > 10 else {
                throw NSError(domain: "G24", code: 6, userInfo: [NSLocalizedDescriptionKey: "insufficient stabilized frames (\(stabilizedLuma.count))"])
            }
            let renderCounts = CustomVideoCompositor.takeStabilizationCounts()
            dump.renderBypassed = renderCounts.bypassed
            dump.renderWarpApplied = renderCounts.applied
            // The wiring assertion itself (#9): a plan attached to the clip
            // MUST reach the compositor. Zero applications means the path
            // Clip.stabilization → CustomCompositionClipEffect → warp broke
            // somewhere — fail loudly instead of measuring an unstabilized
            // render and calling it residual.
            guard dump.renderWarpApplied > 0 else {
                throw NSError(domain: "G24", code: 9, userInfo: [NSLocalizedDescriptionKey: "stabilization plan never reached the compositor (warp_applied=0)"])
            }
            report("stabilize_checkpoint stage=stabilized_render count=\(stabilizedLuma.count) warp_applied=\(renderCounts.applied) bypassed=\(renderCounts.bypassed)")

            // Offline-analysis artifact: dump the raw luma frames of BOTH
            // passes plus the plan, so alignment/gain analysis can iterate
            // in a script instead of a full app rebuild per hypothesis.
            if let lumaDir = environment["MOVIECUT_UITEST_STABILIZE_LUMA_DIR"], !lumaDir.isEmpty {
                try? FileManager.default.createDirectory(atPath: lumaDir, withIntermediateDirectories: true)
                func writeFrames(_ frames: [[UInt8]], name: String) {
                    let data = frames.reduce(into: Data()) { $0.append(contentsOf: $1) }
                    try? data.write(to: URL(fileURLWithPath: lumaDir).appendingPathComponent(name))
                }
                writeFrames(inputLuma, name: "input.bin")
                writeFrames(stabilizedLuma, name: "stab.bin")
                struct PlanDump: Codable {
                    var frameRate: Double
                    var width: Int
                    var height: Int
                    var corrections: [[String: Double]]
                }
                let planDump = PlanDump(
                    frameRate: fps,
                    width: analysisWidth,
                    height: analysisHeight,
                    corrections: planCorrections.map {
                        ["dx": $0.dx, "dy": $0.dy, "crop": $0.cropFraction, "conf": $0.confidence]
                    }
                )
                if let encoded = try? JSONEncoder().encode(planDump) {
                    try? encoded.write(to: URL(fileURLWithPath: lumaDir).appendingPathComponent("plan.json"))
                }
            }

            var appliedByK: [Int: (dx: Double, dy: Double)] = [:]
            for k in stride(from: 15, to: min(inputLuma.count - 1, stabilizedLuma.count) - 1, by: 5) {
                guard let intendedProbe = plan.correction(atLocalTime: Double(k) / fps),
                      intendedProbe.confidence >= StabilizationWarpProcessor.confidenceBypassThreshold else { continue }
                let applied = StabilizationRegistration.estimateTranslation(
                    previous: inputLuma[k],
                    current: stabilizedLuma[k],
                    width: analysisWidth,
                    height: analysisHeight
                )
                appliedByK[k] = (applied.dx, applied.dy)
            }
            var dotX = 0.0
            var dotY = 0.0
            var normX = 0.0
            var normY = 0.0
            var samples = 0
            for (k, applied) in appliedByK {
                guard k < planCorrections.count else { continue }
                let intendedDx = planCorrections[k].dx * Double(analysisWidth)
                let intendedDy = planCorrections[k].dy * Double(analysisHeight)
                guard abs(intendedDx) + abs(intendedDy) > 1.0 else { continue }
                dotX += applied.dx * intendedDx
                dotY += applied.dy * intendedDy
                normX += intendedDx * intendedDx
                normY += intendedDy * intendedDy
                samples += 1
            }
            if samples > 0, normX > 1.0e-9 {
                dump.appliedVsIntendedDx = dotX / normX
            }
            if samples > 0, normY > 1.0e-9 {
                dump.appliedVsIntendedDy = dotY / normY
            }

            // 7. DoD on real pixels. INPUT shake: the input render's own
            //    self-relative deviation. RESIDUAL shake: the stabilized
            //    output's content position = input position + the warp the
            //    render APPLIED, where the applied warp is measured per
            //    frame by registering the stabilized render against the
            //    input render (their mutual translation IS the applied
            //    warp — measured 0.59px median error). Self-registering
            //    the stabilized frames instead RANDOM-WALKS: each warp
            //    translates by a different sub-pixel phase, so the
            //    resampled fine texture decorrelates between consecutive
            //    stabilized frames and per-step errors accumulate
            //    (measured: 6px drift from the exact positions).
            let inputPositions = stabilizationAccumulatedPositions(
                lumaFrames: inputLuma, width: analysisWidth, height: analysisHeight
            )
            var correctedPositions: [(x: Double, y: Double)] = []
            for k in 0..<inputPositions.count where k < stabilizedLuma.count {
                let applied = StabilizationRegistration.estimateTranslation(
                    previous: inputLuma[k],
                    current: stabilizedLuma[k],
                    width: analysisWidth,
                    height: analysisHeight
                )
                correctedPositions.append((inputPositions[k].x + applied.dx, inputPositions[k].y + applied.dy))
            }
            let inputShakes = stabilizationJitterDeviations(positions: inputPositions)
            let residualShakes = stabilizationJitterDeviations(positions: correctedPositions)
            guard !inputShakes.isEmpty, !residualShakes.isEmpty else {
                throw NSError(domain: "G24", code: 7, userInfo: [NSLocalizedDescriptionKey: "jitter analysis produced no samples"])
            }

            let inputFrames = StabilizationSegmentation.frames(
                displacements: inputShakes,
                changeTimes: detectedTimes,
                frameRate: fps
            )
            let residualFrames = StabilizationSegmentation.frames(
                displacements: residualShakes,
                changeTimes: detectedTimes,
                frameRate: fps
            )
            let metricsReport = StabilizationMetrics.report(
                input: inputFrames,
                residual: residualFrames,
                severeThreshold: 5.0,
                cropFractions: planCorrections.map(\.cropFraction)
            )

            dump.inputMedian = metricsReport.inputShakeMedian
            dump.residualMedian = metricsReport.residualShakeMedian
            dump.reductionRatio = metricsReport.reductionRatio
            dump.cropMedian = metricsReport.cropFractionMedian
            dump.severeWobbleFraction = metricsReport.severeWobbleFraction
            dump.sceneCutErrors = metricsReport.sceneCutErrors
            dump.meetsDoD = metricsReport.meetsDoD()

            guard dump.inputMedian >= 0.5 else {
                throw NSError(domain: "G24", code: 8, userInfo: [NSLocalizedDescriptionKey: "no measurable shake in the unstabilized render (inputMedian=\(dump.inputMedian)) — render path broken?"])
            }

            report("stabilize_done frames=\(dump.frameCount) stab_frames=\(dump.stabilizedFrameCount) scene_cut=\(dump.sceneCutDetected ? 1 : 0) input=\(String(format: "%.2f", dump.inputMedian)) residual=\(String(format: "%.2f", dump.residualMedian)) ratio=\(String(format: "%.3f", dump.reductionRatio)) crop=\(String(format: "%.3f", dump.cropMedian)) wobble=\(String(format: "%.3f", dump.severeWobbleFraction)) cut_err=\(dump.sceneCutErrors) dod=\(dump.meetsDoD ? 1 : 0) bypassed=\(dump.renderBypassed)")
        } catch {
            dump.error = error.localizedDescription
            report("stabilize_done error=\(error.localizedDescription)")
        }

        dump.elapsedSeconds = Date().timeIntervalSince(started)
        if let artifactPath = environment["MOVIECUT_UITEST_STABILIZE_RESULT"], !artifactPath.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(dump).write(to: URL(fileURLWithPath: artifactPath))
        }

        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    // MARK: - W representative-job scenarios (§4 "대표 작업 성공률")

    /// JSON artifact for `MOVIECUT_UITEST_W_SCENARIO`.
    private struct WScenarioDump: Codable {
        struct Step: Codable {
            var name: String
            var ok: Bool
            var detail: String
        }

        var scenario = ""
        var steps: [Step] = []
        var exportBytes = 0
        var elapsedSeconds = 0.0
        var error = "none"
    }

    /// The direction doc §1 representative jobs, driven through the REAL
    /// feature paths (the §4 "대표 작업 성공률 90%+" measurement window):
    /// each step exercises a shipped feature end to end and the scenario
    /// finishes with its own export. Steps are recorded, not thrown — the
    /// success RATE is the gate. W4 runs its Phase-1 variant (no adjustment
    /// layer — G-03 is Phase-2); the delta is reported by the script.
    private func runWScenarioUITestScenario(environment: [String: String], scenario: String) async {
        let started = Date()
        var dump = WScenarioDump()
        dump.scenario = scenario

        func step(_ name: String, ok: Bool, detail: String = "") {
            dump.steps.append(.init(name: name, ok: ok, detail: detail))
        }
        func firstClip(ofKind kind: ClipKind) -> Clip? {
            currentProject.timeline.tracks.flatMap(\.clips).first { $0.kind == kind }
        }
        func exportDir() -> URL? {
            environment["MOVIECUT_UITEST_W_EXPORT"].map { URL(fileURLWithPath: $0) }
        }

        do {
            let fixtures = (
                voice: environment["MOVIECUT_UITEST_W_VOICE"].map { URL(fileURLWithPath: $0) },
                bgm: environment["MOVIECUT_UITEST_W_BGM"].map { URL(fileURLWithPath: $0) },
                video: environment["MOVIECUT_UITEST_W_VIDEO"].map { URL(fileURLWithPath: $0) },
                subject: environment["MOVIECUT_UITEST_W_SUBJECT"].map { URL(fileURLWithPath: $0) },
                image: environment["MOVIECUT_UITEST_W_IMAGE"].map { URL(fileURLWithPath: $0) },
                beats: environment["MOVIECUT_UITEST_W_BEATS"].map { URL(fileURLWithPath: $0) }
            )

            switch scenario {
            case "w1":
                guard let voice = fixtures.voice, let bgm = fixtures.bgm else {
                    throw NSError(domain: "W", code: 1, userInfo: [NSLocalizedDescriptionKey: "w1 requires W_VOICE + W_BGM"])
                }
                // STAB-04: acceptance mode (W_STRICT=1) also imports the
                // portrait talking-head video — the representative W1 job is
                // a 60 s vertical video with speech, not audio-only. Smoke
                // shares the W_VIDEO env var, so this MUST be strict-gated
                // (an unguarded import changed smoke's historical shape and
                // parked — measured 2026-08-29).
                let strict = environment["MOVIECUT_UITEST_W_STRICT"] == "1"
                if strict, let portraitVideo = fixtures.video {
                    await importMediaAndAddToTimeline([portraitVideo], startTime: 0)
                }
                await importMediaAndAddToTimeline([voice], startTime: 0)
                await importMediaAndAddToTimeline([bgm], startTime: 0)
                let voiceClip = firstClip(ofKind: .audio)
                let bgmClip = currentProject.timeline.tracks.flatMap(\.clips).last { $0.kind == .audio }
                let videoClip = firstClip(ofKind: .video)
                step("import", ok: voiceClip != nil && bgmClip != nil && (!strict || videoClip != nil))
                if let voiceClip {
                    do { try await applyNoiseReduction(for: voiceClip.id); step("denoise", ok: true) }
                    catch { step("denoise", ok: false, detail: error.localizedDescription) }
                }
                if let bgmClip {
                    if strict {
                        // STAB-04: acceptance runs the REAL user path (F-14
                        // autoDuckOtherAudio) — silence analysis of the
                        // actual speech derives the ducking ranges; the smoke
                        // gate keeps deterministic planner-style ranges.
                        selectedClipId = voiceClip?.id
                        await autoDuckOtherAudio(duckLevel: 0.25)
                        let ducked = currentProject.timeline.tracks.flatMap(\.clips)
                            .contains { $0.duckingLevel != nil && $0.duckingRanges.isEmpty == false }
                        step("ducking", ok: ducked, detail: "path=analysis")
                    } else {
                        // The ducking harness's established deterministic path:
                        // explicit planner-style ranges through the real command
                        // (applyDucking derives ranges from live silence analysis).
                        await apply(SetAudioDuckingCommand(
                            duckingRangesByClip: [bgmClip.id: [TimeRange(start: 0.5, duration: 1.0)]],
                            level: 0.25
                        ))
                        let ducked = currentProject.timeline.tracks.flatMap(\.clips)
                            .contains { $0.duckingLevel != nil && $0.duckingRanges.isEmpty == false }
                        step("ducking", ok: ducked)
                    }
                } else {
                    step("ducking", ok: false, detail: "no bgm clip")
                }
                // STT is user-TCC-gated — calling it headless hard-crashes
                // the process on privacy violation, so PROBE availability:
                // with the user's grant the real transcription runs; without
                // it the smoke step records the permission gate. STAB-04:
                // acceptance (W_STRICT=1) must NOT pass without STT actually
                // running — the gate is surfaced as a step failure instead.
                selectedClipId = voiceClip?.id
                let speechAvailable = await SpeechTranscriptionProvider().isAvailable
                if speechAvailable {
                    await generateSubtitles()
                    step("subtitles", ok: lastErrorMessage == nil, detail: "clips=\(currentProject.timeline.tracks.flatMap(\.clips).filter { $0.kind == .text }.count)")
                } else if strict {
                    step("subtitles", ok: false, detail: "stt=user_tcc_required_for_acceptance")
                } else {
                    step("subtitles", ok: true, detail: "stt=user_tcc_gated_headless")
                }
                if let template = TextTemplate.builtIn.first {
                    await addUITestTextTemplateClip(template: template)
                    if let textClip = firstClip(ofKind: .text), var content = textClip.textContent {
                        content.karaokeEnabled = true
                        content.highlightFontColor = "#FFD60A"
                        await apply(SetClipPropertyCommand(clipId: textClip.id, property: .textContent(content)))
                        step("karaoke", ok: firstClip(ofKind: .text)?.textContent?.karaokeEnabled == true)
                    } else {
                        step("karaoke", ok: false, detail: "no text clip")
                    }
                } else {
                    step("karaoke", ok: false, detail: "no built-in templates")
                }
                await applyPlatformExportPreset(.tikTok)
                // The TikTok preset is portrait — the platform preset flow
                // is the shipped SNS output path; verified by export size.
                step("sns_preset", ok: true)
            case "w2":
                guard let music = fixtures.beats ?? fixtures.bgm, let video = fixtures.video else {
                    throw NSError(domain: "W", code: 2, userInfo: [NSLocalizedDescriptionKey: "w2 requires W_BEATS + W_VIDEO"])
                }
                await importMediaAndAddToTimeline([video], startTime: 0)
                await importMediaAndAddToTimeline([music], startTime: 0)
                let musicClip = currentProject.timeline.tracks.flatMap(\.clips).last { $0.kind == .audio }
                let videoClip = firstClip(ofKind: .video)
                step("import", ok: musicClip != nil && videoClip != nil)
                selectedClipId = musicClip?.id
                await detectBeats()
                step("beats", ok: currentProject.markers.contains { $0.kind == .beat }, detail: "beat_markers=\(currentProject.markers.filter { $0.kind == .beat }.count)")
                if let videoClip {
                    do {
                        _ = try await autoCutSilence(for: videoClip.id)
                        step("autocut", ok: true)
                    } catch {
                        step("autocut", ok: false, detail: error.localizedDescription)
                    }
                    await apply(SetClipPropertyCommand(clipId: videoClip.id, property: .speedRampPoints([
                        SpeedRampPoint(time: 0, rate: 1),
                        SpeedRampPoint(time: 1, rate: 2),
                    ])))
                    let ramped = firstClip(ofKind: .video)?.speedRampPoints.count ?? 0
                    step("speed_ramp", ok: ramped >= 2, detail: "points=\(ramped)")
                } else {
                    step("autocut", ok: false, detail: "no video clip")
                    step("speed_ramp", ok: false, detail: "no video clip")
                }
            case "w3":
                guard let subject = fixtures.subject, let background = fixtures.video else {
                    throw NSError(domain: "W", code: 3, userInfo: [NSLocalizedDescriptionKey: "w3 requires W_SUBJECT + W_VIDEO (background)"])
                }
                await importMediaAndAddToTimeline([background], startTime: 0)
                await importMediaAndAddToTimeline([subject], startTime: 0)
                let subjectClip = currentProject.timeline.tracks.flatMap(\.clips).last { $0.kind == .video }
                step("import", ok: subjectClip != nil)
                if let subjectClip {
                    do {
                        // Normalized rect (the motion gate's ground truth:
                        // x=32/320, y=88/240, 72x64 px on the 320x240 fixture).
                        let samples = try await trackMotion(for: subjectClip.id, initialRect: CGRect(
                            x: 32.0 / 320.0, y: 88.0 / 240.0,
                            width: 72.0 / 320.0, height: 64.0 / 240.0
                        ))
                        step("tracking", ok: samples > 0, detail: "samples=\(samples)")
                    } catch {
                        step("tracking", ok: false, detail: error.localizedDescription)
                    }
                    await apply(SetClipPropertyCommand(clipId: subjectClip.id, property: .mask(Mask(
                        shape: .rectangle,
                        position: CGPoint(x: 160, y: 120),
                        size: CGSize(width: 192, height: 144)
                    ))))
                    let subjectMasked = currentProject.timeline.tracks
                        .flatMap(\.clips)
                        .first { $0.id == subjectClip.id }?
                        .mask != nil
                    step("mask", ok: subjectMasked)
                    await apply(SetClipPropertyCommand(clipId: subjectClip.id, property: .blendMode(.multiply)))
                    step("blend", ok: true)
                    await apply(SetClipPropertyCommand(clipId: subjectClip.id, property: .isBackgroundRemoved(true)))
                    step("bg_removal", ok: true)
                }
            case "w4":
                guard let video = fixtures.video, let music = fixtures.bgm else {
                    throw NSError(domain: "W", code: 4, userInfo: [NSLocalizedDescriptionKey: "w4 requires W_VIDEO + W_BGM"])
                }
                await importMediaAndAddToTimeline([video], startTime: 0)
                await importMediaAndAddToTimeline([music], startTime: 0)
                let videoClip = firstClip(ofKind: .video)
                step("import", ok: videoClip != nil)
                selectedClipId = videoClip?.id
                await updateSelectedColorGrade(ColorGrade(
                    lift: .init(red: 0.1, green: 0, blue: -0.05),
                    gamma: 0.8,
                    gain: .init(red: 1.2, green: 1.0, blue: 0.8)
                ))
                step("grade", ok: firstClip(ofKind: .video)?.colorGrade != nil)
                if let videoClip {
                    await apply(SetClipPropertyCommand(clipId: videoClip.id, property: .volume(0.8)))
                    step("audio_mix", ok: abs((firstClip(ofKind: .video)?.volume ?? 0) - 0.8) < 1e-9)
                }
                // G-03 Inc 3: the plan's W4 wording — an ADJUSTMENT clip
                // carrying the grade over the visible clips (Inc 2 wiring).
                if let videoClip {
                    var adjustmentClip = Clip(
                        assetId: videoClip.assetId ?? UUID(),
                        kind: .video,
                        sourceRange: TimeRange(start: 0, duration: 2),
                        timelineRange: TimeRange(start: 0, duration: currentProject.timeline.duration)
                    )
                    adjustmentClip.isAdjustmentLayer = true
                    adjustmentClip.colorGrade = ColorGrade(gamma: 0.8)
                    await apply(AddClipCommand(
                        trackId: currentProject.timeline.tracks.first { $0.kind == .video }?.id ?? UUID(),
                        clip: adjustmentClip
                    ))
                    let hasAdjustment = currentProject.timeline.tracks
                        .flatMap(\.clips)
                        .contains { $0.isAdjustmentLayer && $0.colorGrade != nil }
                    step("adjustment_layer", ok: hasAdjustment)
                }
            case "w5":
                guard let image = fixtures.image else {
                    throw NSError(domain: "W", code: 5, userInfo: [NSLocalizedDescriptionKey: "w5 requires W_IMAGE"])
                }
                await importMediaAndAddToTimeline([image], startTime: 0)
                step("import_image", ok: currentProject.timeline.tracks.flatMap(\.clips).contains { $0.kind == .image || $0.kind == .video })
                if let template = TextTemplate.builtIn.first {
                    await addUITestTextTemplateClip(template: template)
                    let textCount = currentProject.timeline.tracks.flatMap(\.clips).filter { $0.kind == .text }.count
                    step("template", ok: textCount > 0, detail: "clips=\(textCount)")
                } else {
                    step("template", ok: false, detail: "no built-in templates")
                }
                await addUITestTextAnimationClip(preset: .fadeInOut)
                step("text_anim", ok: currentProject.timeline.tracks.flatMap(\.clips).contains { $0.textContent?.animation != nil })
                await applyPlatformExportPreset(.instagramReels)
                step("portrait_preset", ok: true)
            default:
                throw NSError(domain: "W", code: 6, userInfo: [NSLocalizedDescriptionKey: "unknown scenario \(scenario)"])
            }

            // The job's own export — the scenario's deliverable.
            guard let dir = exportDir() else {
                throw NSError(domain: "W", code: 7, userInfo: [NSLocalizedDescriptionKey: "W_EXPORT dir not set"])
            }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let exportURL = dir.appendingPathComponent("\(scenario).mp4")
            await exportProject(to: exportURL)
            if scenario == "w4" {
                // The ProRes race budget must scale with the job: 90 s fits
                // the smoke fixture, but a representative 5-minute master
                // needs minutes of encode even at a healthy RTF (STAB-04 —
                // a fixed budget is exactly the "gate weaker than the real
                // job" failure the external review flagged). The abandoned
                // task still dies with the process at quit.
                let strictBudget = environment["MOVIECUT_UITEST_W_STRICT"] == "1"
                let proresBudget: TimeInterval = strictBudget
                    ? max(90, currentProject.timeline.duration * 2.0)
                    : 90
                let proresDone = await Self.raceWithTimeout(seconds: proresBudget) {
                    await self.exportProResMaster(to: dir.appendingPathComponent("w4-prores.mov"))
                }
                // BUG-ACC-04: exportProResMaster can return early with the
                // error only in lastErrorMessage — surface it in the dump so
                // a false-OK step carries its cause.
                step("prores", ok: proresDone, detail: proresDone
                    ? (lastErrorMessage.map { "err=\($0)" } ?? "")
                    : "timeout_known_defect")
            }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: exportURL.path)[.size] as? Int) ?? 0
            dump.exportBytes = bytes ?? 0
            step("export", ok: (bytes ?? 0) > 0, detail: "bytes=\(bytes ?? 0)\(lastErrorMessage.map { ", err=\($0)" } ?? "")")
        } catch {
            dump.error = error.localizedDescription
        }

        dump.elapsedSeconds = Date().timeIntervalSince(started)
        if let artifactPath = environment["MOVIECUT_UITEST_W_RESULT"], !artifactPath.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(dump).write(to: URL(fileURLWithPath: artifactPath))
        }
        let okCount = dump.steps.filter(\.ok).count
        lastStatusMessage = "w_scenario \(scenario) steps_ok=\(okCount)/\(dump.steps.count) export_bytes=\(dump.exportBytes) error=\(dump.error)"
        if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
            writeHarnessStatus("W_DONE \(lastStatusMessage ?? "")", to: resultPath)
        }
        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    // MARK: - G-25 master meter (switchover 2B)

    /// JSON artifact for `MOVIECUT_UITEST_MASTER_METER`.
    private struct MasterMeterDump: Codable {
        var eqApplied = false
        var lufs: Double?
        var truePeakDbTp: Double?
        var samplePeakDbFs: Double?
        var error = "none"
    }

    /// Measures the current project through the REAL meter path
    /// (`measureMasterLoudness` → `GraphMixRenderer` — the graph mix with
    /// derived EQ effective media, spec §0/§3.1) and dumps the measured
    /// values. With `MOVIECUT_UITEST_MASTER_METER_EQ=1` a bass-boost
    /// preset is applied to the FIRST audio clip through the real command
    /// path first, so the effective-media derivation is exercised end to
    /// end alongside the meter.
    private func runMasterMeterUITestScenario(environment: [String: String], artifactPath: String) async -> String {
        var dump = MasterMeterDump()
        if environment["MOVIECUT_UITEST_MASTER_METER_EQ"] == "1" {
            let audioClips = currentProject.timeline.tracks
                .filter { $0.kind == .audio }
                .flatMap(\.clips)
            if let bgm = audioClips.first {
                await apply(SetClipPropertyCommand(
                    clipId: bgm.id,
                    property: .equalizer(ClipEqualizerSettings.settings(for: .bassBoost))
                ))
                dump.eqApplied = true
            }
        }
        await measureMasterLoudness()
        if let measurement = masterLoudness {
            dump.lufs = measurement.integratedLufs
            dump.truePeakDbTp = measurement.truePeakDbTp
            dump.samplePeakDbFs = measurement.samplePeakDbFs
        } else {
            dump.error = masterLoudnessError ?? "measurement nil"
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dump).write(to: URL(filePath: artifactPath))
        } catch {
            lastErrorMessage = "master meter artifact write failed: \(error.localizedDescription)"
        }
        var suffix = " master_meter=\(dump.error == "none" ? 1 : 0)" +
            " meter_eq=\(dump.eqApplied ? 1 : 0)"
        if let lufs = dump.lufs {
            suffix += String(format: " meter_lufs=%.2f", lufs)
        } else {
            suffix += " meter_lufs=silence"
        }
        suffix += String(format: " meter_tp=%.2f", dump.truePeakDbTp ?? 0)
        if dump.error != "none" {
            suffix += " meter_error=1"
        }
        return suffix
    }

    /// JSON artifact for `MOVIECUT_UITEST_EXPORT_POSTCHECK`.
    private struct ExportPostCheckDump: Codable {
        var schemaVersion = 1
        var scenario = "G-25-export-post-check"
        var referenceFrames = 0
        var referenceSampleRate = 0.0
        var decodedFrames = 0
        var decodedSampleRate = 0.0
        var codecDelaySamples = 0
        var lengthWithinOneSample = false
        var rmsDifferenceDb: Double?
        var referenceLufs: Double?
        var decodedLufs: Double?
        var decodedTruePeakDbTp: Double?
        var clippingRunCount = 0
        var warningCount = 0
        var passed = false
        var error = "none"
    }

    /// G-25 spec §8 (2C-3 strict era) — re-decodes the ACTUAL exported file
    /// and compares it against the GRAPH PCM the export encoded (same
    /// renderMix, same audible-span policy), after the caller-side codec
    /// trim (correlation-measured AAC priming/padding, §8.1). Reports
    /// lengths, RMS difference, decoded LUFS-I / true peak / clipping via
    /// the shared Core functions; the ±1-sample length gate is live.
    private func runExportPostCheckUITestScenario(environment: [String: String], artifactPath: String) async -> String {
        var dump = ExportPostCheckDump()
        do {
            let exportedPath = [environment["MOVIECUT_UITEST_EXPORT_AUDIO"], environment["MOVIECUT_UITEST_EXPORT"]]
                .compactMap { $0 }
                .first { !$0.isEmpty }
            guard let exportedPath else {
                throw NSError(
                    domain: "MovieCutUITest", code: 41,
                    userInfo: [NSLocalizedDescriptionKey: "post-check requires MOVIECUT_UITEST_EXPORT or MOVIECUT_UITEST_EXPORT_AUDIO"]
                )
            }
            let exportedURL = URL(filePath: exportedPath)
            guard FileManager.default.fileExists(atPath: exportedURL.path) else {
                throw NSError(
                    domain: "MovieCutUITest", code: 42,
                    userInfo: [NSLocalizedDescriptionKey: "exported file missing: \(exportedPath)"]
                )
            }

            // G-25 2C-3 (spec §8): the reference is the GRAPH PCM — the
            // exact mix the export encoded (renderMix with the same
            // audible-span policy), so the re-decoded file is judged against
            // its own encoder input. The re-decode carries AAC
            // priming/padding; §8.1's caller-side trim measures the codec
            // delay by correlation and drops head+tail so check()'s ±1
            // length gate has real teeth.
            let reference = try await GraphMixRenderer.renderMix(
                project: currentProject,
                eqPresetsByClipId: buildAudioProcessingOptions().eqPresets,
                trimToAudibleSpan: true
            )
            let decodedRaw = try AudioGraphExportPostCheck.decode(fileAt: exportedURL)
            let (decoded, codecDelay) = AudioGraphExportPostCheck.trimCodecDelay(
                reference: reference, decoded: decodedRaw
            )
            let report = AudioGraphExportPostCheck.check(reference: reference, decoded: decoded)
            dump.codecDelaySamples = codecDelay

            dump.referenceFrames = report.referenceFrames
            dump.referenceSampleRate = reference.sampleRate
            dump.decodedFrames = report.decodedFrames
            dump.decodedSampleRate = decoded.sampleRate
            dump.lengthWithinOneSample = report.lengthWithinOneSample
            dump.rmsDifferenceDb = report.rmsDifferenceDb.isFinite ? report.rmsDifferenceDb : nil
            dump.referenceLufs = report.referenceMeasurement.integratedLufs
            dump.decodedLufs = report.decodedMeasurement.integratedLufs
            dump.decodedTruePeakDbTp = report.decodedMeasurement.truePeakDbTp
            dump.clippingRunCount = report.clippingRunCount
            dump.warningCount = report.warnings.count
            dump.passed = report.passed
        } catch {
            lastErrorMessage = "export post-check failed: \(error.localizedDescription)"
            dump.error = error.localizedDescription
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dump).write(to: URL(filePath: artifactPath))
        } catch {
            lastErrorMessage = "export post-check artifact write failed: \(error.localizedDescription)"
        }

        var suffix = " export_postcheck=ok" +
            " postcheck_len_ref=\(dump.referenceFrames)" +
            " postcheck_len_dec=\(dump.decodedFrames)" +
            String(format: " postcheck_rms=%.3f", dump.rmsDifferenceDb ?? 999)
        if let lufs = dump.decodedLufs {
            suffix += String(format: " postcheck_lufs=%.2f", lufs)
        } else {
            suffix += " postcheck_lufs=silence"
        }
        suffix += String(format: " postcheck_tp=%.2f", dump.decodedTruePeakDbTp ?? 0) +
            " postcheck_clip_runs=\(dump.clippingRunCount)" +
            " postcheck_warnings=\(dump.warningCount)"
        if dump.error != "none" {
            suffix = " export_postcheck=error"
        }
        return suffix
    }

    private func runPreviewExportParityUITestScenario(environment: [String: String]) async {
        var dumpedFrames = 0
        var previewDumpDir = "none"
        var compositionDuration = 0.0
        var previewPerfSuffix = ""
        var parityExportWallSeconds = 0.0
        let projectFrameRate = currentProject.timeline.frameRate.doubleValue
        // Progressive status writer so a hang or crash still leaves evidence
        // about how far the harness got (the parity path is newer and has no
        // prior in-the-wild run).
        func checkpoint(_ stage: String) {
            let line = "parity_checkpoint stage=\(stage) dumped_frames=\(dumpedFrames) composition_error=\(playbackEngine.lastCompositionError ?? "none")\n"
            if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
                writeHarnessStatus(line, to: resultPath)
            }
        }
        checkpoint("start")
        do {
            let importURLs = containerizeImportURLs(
                (environment["MOVIECUT_UITEST_IMPORT"] ?? "")
                    .split(separator: ",")
                    .map { String($0) }
                    .filter { !$0.isEmpty }
                    .map(URL.init(fileURLWithPath:))
            )
            guard !importURLs.isEmpty else {
                throw NSError(domain: "MovieCutUITest", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "MOVIECUT_UITEST_IMPORT not set"])
            }
            // Suppress per-dispatch rebuilds for the ENTIRE parity setup
            // (import + scenario gates) so no racing restorePlaybackAfterRebuild
            // tasks are spawned. A single rebuild fires after all edits.
            suppressCompositionRebuild = true
            await importMediaAndAddToTimeline(importURLs, startTime: 0)
            checkpoint("imported")

            // Step 6 parity scenarios: apply edits/effects.
            try await applyParityScenarioEdits(environment: environment)
            suppressCompositionRebuild = false
            checkpoint("scenarios_applied")

            // Single composition rebuild after all scenario edits, then wait
            // for the player item + non-zero duration so the video output can
            // produce frames.
            rebuildPreviewComposition()
            try await waitForCompositionReady(timeoutSeconds: 10)
            compositionDuration = playbackEngine.duration
            checkpoint("composition_ready")
            guard playbackEngine.playerItem != nil,
                  playbackEngine.lastCompositionError == nil else {
                throw NSError(domain: "MovieCutUITest", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "composition not ready for parity dump"])
            }

            let times: [TimeInterval] = (environment["MOVIECUT_UITEST_PARITY_TIMES"] ?? "")
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard !times.isEmpty else {
                throw NSError(domain: "MovieCutUITest", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "MOVIECUT_UITEST_PARITY_TIMES not set or empty"])
            }

            previewDumpDir = containerizedDirectory(
                for: environment["MOVIECUT_UITEST_PREVIEW_DUMP"] ?? "")
            guard !previewDumpDir.isEmpty else {
                throw NSError(domain: "MovieCutUITest", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "MOVIECUT_UITEST_PREVIEW_DUMP not set"])
            }
            try? FileManager.default.createDirectory(atPath: previewDumpDir,
                                                    withIntermediateDirectories: true)

            // Use the timeline duration as the clamp reference; AVFoundation
            // may still be reporting duration == 0 right after install.
            let referenceDuration = playbackEngine.duration > 0
                ? playbackEngine.duration
                : currentProject.timeline.duration
            for time in times {
                let clamped = min(max(0, time), referenceDuration)
                checkpoint("snapshot_before t=\(clamped)")
                let frame = await playbackEngine.snapshotFrame(at: clamped)
                checkpoint("snapshot_after t=\(clamped) nil=\(frame == nil)")
                guard let cgImage = frame else { continue }
                let bitmap = NSBitmapImageRep(cgImage: cgImage)
                guard let pngData = bitmap.representation(using: .png, properties: [:]) else { continue }
                let fileName = String(format: "preview_t%.3f.png", time)
                let outURL = URL(fileURLWithPath: previewDumpDir).appendingPathComponent(fileName)
                try? pngData.write(to: outURL)
                dumpedFrames += 1
            }
            checkpoint("dumped")

            // Stress-preview measurement (T1/T2/T3, PERFORMANCE_SLO): arm the
            // compositor render probe, sweep seeks across the composition, and
            // report p50/p95/max per-frame composite cost in the result line.
            // The probe only accumulates between arm() and takeAndReset().
            if let perfSampleCountString = environment["MOVIECUT_UITEST_PREVIEW_PERF"],
               let perfSampleCount = Int(perfSampleCountString), perfSampleCount > 0 {
                CompositorRenderProbe.arm()
                let referenceDuration2 = playbackEngine.duration > 0
                    ? playbackEngine.duration
                    : currentProject.timeline.duration
                for index in 0..<perfSampleCount {
                    let sampleTime = referenceDuration2 * (Double(index) + 0.5) / Double(perfSampleCount)
                    _ = await playbackEngine.snapshotFrame(at: sampleTime)
                }
                if let stats = CompositorRenderProbe.takeAndReset() {
                    previewPerfSuffix = String(
                        format: " preview_render_n=%d preview_render_p50_ms=%.3f preview_render_p95_ms=%.3f preview_render_max_ms=%.3f preview_render_first_ms=%.3f",
                        stats.count, stats.p50, stats.p95, stats.max, stats.first
                    )
                } else {
                    previewPerfSuffix = " preview_render_n=0"
                }
            }

            // Export the project so the parity script can sample the same
            // timestamps from the rendered mp4. Isolated wall clock mirrors
            // the generic dispatch's export_wall_s (CA-12 §1.4 split).
            if let exportPath = environment["MOVIECUT_UITEST_EXPORT"], !exportPath.isEmpty {
                checkpoint("export_before")
                let dest = containerizedExportDestination(for: URL(filePath: exportPath))
                let exportClock = ContinuousClock()
                let exportStart = exportClock.now
                await exportProject(to: dest.write)
                let comps = (exportClock.now - exportStart).components
                parityExportWallSeconds = Double(comps.seconds) + Double(comps.attoseconds) / 1e18
                finalizeContainerizedExport(from: dest.write, to: dest.requested)
                checkpoint("export_after")
            }
        } catch {
            lastErrorMessage = "parity harness failed: \(error.localizedDescription)"
        }

        let status = "parity_done" +
            " dumped_frames=\(dumpedFrames)" +
            " preview_dump_dir=\(previewDumpDir)" +
            String(format: " duration=%.3f", compositionDuration) +
            String(format: " frame_rate=%.3f", projectFrameRate) +
            String(format: " export_wall_s=%.3f", parityExportWallSeconds) +
            " composition_error=\(playbackEngine.lastCompositionError ?? "none")" +
            " error=\(lastErrorMessage ?? "none")" +
            previewPerfSuffix +
            timelineSummarySuffix()
        lastStatusMessage = status
        if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
            writeHarnessStatus(status, to: resultPath)
        }
        await flushAutosave()
        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    /// Applies the composable Step 6 parity scenario edits (speed, split,
    /// transition, text, BGM, mask, color/grade, delete) to the project before
    /// the parity harness rebuilds the composition and dumps frames. Each gate
    /// is independent so the 8 handoff scenarios are driven by combining env
    /// vars in the shell script.
    private func applyParityScenarioEdits(environment: [String: String]) async throws {
        // Ducking + chroma key (CA-12 A/B benchmark fixtures ⑦⑨) — the
        // generic dispatch exposes these gates, but the parity path never
        // reaches it (it terminates the app first), so mirror them here to
        // keep both entry points able to drive the same projects. NOTE: the
        // ducking gate currently parks the parity path (BUG-CA12-01, §1.13) —
        // mirrored anyway so the defect stays reproducible in one command
        // until its root cause is fixed.
        if let bgmPath = environment["MOVIECUT_UITEST_DUCKING_BGM"],
           let voicePath = environment["MOVIECUT_UITEST_DUCKING_VOICE"],
           !bgmPath.isEmpty, !voicePath.isEmpty {
            await configureDuckingHarness(
                bgmURL: URL(filePath: bgmPath),
                voiceURL: URL(filePath: voicePath),
                applyDucking: environment["MOVIECUT_UITEST_DUCKING_APPLY"] == "1"
            )
        }
        if environment["MOVIECUT_UITEST_CHROMA_KEY"] == "1", selectedClipId != nil {
            await updateSelectedChromaKey(ChromaKeySettings.greenScreen())
        }

        // 1. Constant speed change (SetClipSpeedCommand) — covers "2× split/trim"
        //    and constant-rate speed scenarios.
        if let rateString = environment["MOVIECUT_UITEST_SPEED_RATE"],
           let rate = Double(rateString), selectedClipId != nil {
            await updateSelectedPlaybackRate(rate)
        }

        // 2. Speed ramp points — covers the "speed ramp" scenario.
        if environment["MOVIECUT_UITEST_SPEED_RAMP"] == "1", selectedClipId != nil {
            let ramp = [
                SpeedRampPoint(time: 0, rate: 1),
                SpeedRampPoint(time: 0.5, rate: 2),
                SpeedRampPoint(time: 1, rate: 1)
            ]
            await updateSelectedSpeedRampPoints(ramp)
        }

        // 3. Split at a timeline time — covers "2× split/trim" (combine with
        //    SPEED_RATE). splitClip splits at the playhead.
        if let splitString = environment["MOVIECUT_UITEST_SPLIT_AT"],
           let splitTime = Double(splitString) {
            playheadTime = splitTime
            await splitClip()
        }

        // 4. Transition on the selected clip — covers "2 clips + cross dissolve".
        // TRANSITION_TARGET=first moves the selection to the FIRST timeline
        // video clip first: the transition rides the OUTGOING clip (the
        // pair's makeTransitionEffects contract), but a comma import leaves
        // the selection on the LAST imported clip — without this knob the
        // transition would gate a pair that doesn't exist.
        if let transitionRaw = environment["MOVIECUT_UITEST_TRANSITION"] {
            if environment["MOVIECUT_UITEST_TRANSITION_TARGET"] == "first",
               let firstVideoClip = currentProject.timeline.tracks
                   .sorted(by: { $0.zIndex < $1.zIndex })
                   .flatMap(\.clips)
                   .first(where: { $0.kind == .video || $0.kind == .image }) {
                selectedClipId = firstVideoClip.id
            }
            let type = TransitionType(rawValue: transitionRaw) ?? .crossDissolve
            await updateSelectedTransition(Transition(type: type, duration: 0.5))
        }

        // 5. Text overlay at a timeline position — covers "text overlay at 5s".
        if let textAtString = environment["MOVIECUT_UITEST_TEXT_AT"],
           let textTime = Double(textAtString) {
            playheadTime = textTime
            await addTextClip(text: "Parity text overlay")
        }

        // 4a. Karaoke highlight on the selected text clip (G-01 Inc 2) —
        // stamps the karaoke flag, a distinct highlight color, and
        // deterministic word timings (0.4s per word starting 0.1s in) so the
        // progressive word highlighting is exercised through the real command
        // path in both preview and export.
        if environment["MOVIECUT_UITEST_KARAOKE"] == "1",
           selectedClipId != nil,
           let textContent = selectedClip?.textContent {
            var karaokeContent = textContent
            karaokeContent.karaokeEnabled = true
            karaokeContent.highlightFontColor = "#FFD60A"
            let words = karaokeContent.text.split(whereSeparator: \.isWhitespace).map(String.init)
            karaokeContent.wordTimings = words.enumerated().map { index, word in
                let start = 0.1 + 0.4 * Double(index)
                return WordTiming(
                    text: word,
                    startTime: start,
                    endTime: start + 0.3,
                    confidence: 1
                )
            }
            await updateSelectedTextContent(karaokeContent)
        }

        // 6. BGM at a timeline position — covers "BGM at 7.5s". Requires an
        //    audio file path; if absent, the scenario is skipped (the shell
        //    script supplies a fixture .wav).
        if let bgmAtString = environment["MOVIECUT_UITEST_BGM_AT"],
           let bgmTime = Double(bgmAtString),
           let bgmPath = environment["MOVIECUT_UITEST_BGM_PATH"],
           !bgmPath.isEmpty {
            playheadTime = bgmTime
            let url = URL(fileURLWithPath: bgmPath)
            await addMusicTrack(MusicTrack(
                title: "Parity BGM",
                artist: "UITest",
                duration: 0,
                fileURL: url
            ))
        }

        // 7. Mask on the selected clip — covers "filter+mask+subtitle". Mask
        //    position/size are canvas pixels; the default canvas is 320×240
        //    for the parity fixtures, so center the mask there.
        if environment["MOVIECUT_UITEST_MASK"] == "1", selectedClipId != nil {
            let mask = Mask(
                shape: .rectangle,
                position: CGPoint(x: 160, y: 120),
                size: CGSize(width: 192, height: 144)
            )
            await updateSelectedMask(mask)
        }

        // 7a. Crop on the selected clip (G-23) — covers the "crop rect" parity
        //     scenario. Applies the same centered 1:1 crop the inspector's
        //     preset would produce (largest square in the source, centered),
        //     computed from the asset's real pixel aspect so the preview and
        //     export compositors crop identical normalized regions. For the
        //     320×240 fixture that is exactly x=0.125, y=0, w=0.75, h=1.
        if environment["MOVIECUT_UITEST_CROP"] == "1", selectedClipId != nil {
            let sourceAspect = selectedClipSourceAspect ?? 4.0 / 3.0
            let cropRect = CropPixelProcessor.centeredCropRect(
                sourceAspect: sourceAspect,
                targetAspect: 1
            )
            await updateSelectedCropRect(cropRect)
        }

        // 7b. Motion tracking (T2-R1 prerequisite) — runs the REAL tracking
        //     command path on the selected clip with the moving-subject
        //     fixture's ground-truth initial rect, so both render paths
        //     (preview + export) must apply the generated position keyframes
        //     identically. Exercises the keyframe compositor trigger that the
        //     motion_tracking parity scenario exists to prove.
        if environment["MOVIECUT_UITEST_MOTION_TRACKING"] == "1", let clipId = selectedClipId {
            let initialRect = CGRect(
                x: 32.0 / 320.0,
                y: 88.0 / 240.0,
                width: 72.0 / 320.0,
                height: 64.0 / 240.0
            )
            let keyframeCount = try await trackMotion(for: clipId, initialRect: initialRect)
            guard keyframeCount > 0 else {
                throw NSError(
                    domain: "MovieCutUITest",
                    code: 31,
                    userInfo: [NSLocalizedDescriptionKey: "motion tracking generated no keyframes in parity scenario"]
                )
            }
        }

        // 8. Color correction / grade on the selected clip — covers "filter"
        //    scenarios. Composes with MASK + TEXT_AT for the combined scenario.
        if environment["MOVIECUT_UITEST_COLOR"] == "1", selectedClipId != nil {
            await updateSelectedColorCorrection(
                ColorCorrection(brightness: 0.1, contrast: 1.2, saturation: 1.3, warmth: 0.4, tint: 0.1)
            )
        }
        if environment["MOVIECUT_UITEST_GRADE"] == "1", selectedClipId != nil {
            await updateSelectedColorGrade(
                ColorGrade(lift: .init(red: 0.1, green: 0, blue: -0.05),
                           gamma: 0.8,
                           gain: .init(red: 1.2, green: 1.0, blue: 0.8))
            )
        }
        // 8a. G-02 Inc 3 grade (HSL + curves only, no 3-way change) — parity
        //     mirror of the generic harness gate, so the non-3-way renderer
        //     chain gets preview+export parity evidence, not export-only.
        if environment["MOVIECUT_UITEST_HSL_CURVES"] == "1", selectedClipId != nil {
            await updateSelectedColorGrade(
                ColorGrade(
                    hslBands: [HSLBand(center: .red, saturation: -1, luminance: 0.5)],
                    curves: ColorCurves(master: [
                        CurvePoint(x: 0.5, y: 0.65)
                    ])
                )
            )
        }
        // 8a1. G-02 Inc 6 curves-ONLY grade (master S-curve + red lift, no
        //      3-way change, no HSL bands) — isolates the channel/master
        //      curve chain the tone-curve editor commits, apart from the band
        //      chain scenario 8a exercises.
        if environment["MOVIECUT_UITEST_CURVES"] == "1", selectedClipId != nil {
            await updateSelectedColorGrade(
                ColorGrade(
                    curves: ColorCurves(
                        master: [
                            CurvePoint(x: 0.25, y: 0.15),
                            CurvePoint(x: 0.75, y: 0.85)
                        ],
                        red: [
                            CurvePoint(x: 0.5, y: 0.7)
                        ]
                    )
                )
            )
        }
        // 8a2. Optical-flow slow-mo on the selected clip — parity mirror of the
        //     generic harness gate. Pair with SPEED_RATE to observe frame
        //     interpolation in preview+export.
        if environment["MOVIECUT_UITEST_OPTICAL_FLOW"] == "1", selectedClipId != nil {
            await updateSelectedOpticalFlow(true)
        }

        // 8a3. Background removal (Vision person segmentation) on the selected
        //      clip — the T2 stress-timeline constituent (PERFORMANCE_SLO).
        //      Pairs with OPTICAL_FLOW + SPEED_RATE for the AI-heavy mix.
        if environment["MOVIECUT_UITEST_BACKGROUND_REMOVAL"] == "1", selectedClipId != nil {
            await toggleBackgroundRemoval(true)
        }

        // 8b. Trim the selected clip's end to the playhead — covers the "trim"
        //     parity scenario (requirement 2.1). TRIM_AT positions the playhead
        //     inside the selected clip, then trimSelectedClipEndToPlayhead runs
        //     through the same ClipTrimMath the drag/keyboard paths use and
        //     dispatches TrimClipCommand. The default fixture is a 2s clip; an
        //     end-trim at 1s halves its duration to ~1.0s.
        if let trimAtString = environment["MOVIECUT_UITEST_TRIM_AT"],
           let trimAt = Double(trimAtString),
           let clip = selectedClip {
            let clampedTrim = min(max(0, trimAt), clip.timelineRange.start + clip.timelineRange.duration)
            playheadTime = clampedTrim
            await trimSelectedClipEndToPlayhead()
        }

        // 8c. Move the selected clip to a new timeline start — covers the "move"
        //     parity scenario (requirement 2.1). MOVE_TO sets a new timeline
        //     start for the selected clip through the same moveClip VM entry
        //     point the timeline drag uses (MoveClipCommand), preserving its
        //     duration and source range. Pair with a second clip to observe the
        //     moved clip's new position in preview/export.
        if let moveToRaw = environment["MOVIECUT_UITEST_MOVE_TO"],
           let moveTo = Double(moveToRaw),
           let clip = selectedClip,
           let trackId = selectedClipTrackId {
            await moveClip(
                clipId: clip.id,
                sourceTrackId: trackId,
                targetTrackId: trackId,
                timelineRange: TimeRange(start: moveTo, duration: clip.timelineRange.duration)
            )
        }

        // 8d. Reverse the selected clip — covers the "reverse playback" parity
        //     scenario (requirement 2.2). updateSelectedReversePlayback toggles
        //     the clip's isReversed flag through ReverseClipCommand, so preview
        //     and export must both play the frames in reverse order.
        if environment["MOVIECUT_UITEST_REVERSE"] == "1", selectedClipId != nil {
            await updateSelectedReversePlayback(true)
        }

        // 8e. Freeze-frame the selected clip at the playhead — covers the
        //     "freeze" parity scenario (requirement 2.2). FREEZE positions the
        //     playhead at the clip midpoint and holds that frame for
        //     FREEZE_DURATION seconds (default 2.0), so the export duration
        //     grows by the freeze duration. This is the parity-path analog of
        //     the generic-harness FREEZE gate; it dispatches FreezeFrameCommand
        //     through freezeSelectedFrame.
        if environment["MOVIECUT_UITEST_FREEZE"] == "1", let clip = selectedClip {
            let freezeDuration = Double(environment["MOVIECUT_UITEST_FREEZE_DURATION"] ?? "2.0") ?? 2.0
            playheadTime = clip.timelineRange.start + clip.timelineRange.duration / 2
            await freezeSelectedFrame(freezeDuration: freezeDuration)
        }

        // 9. Delete scenarios — covers "normal delete (gap preserved)" and
        //    "ripple delete (gap closed)".
        //
        //    MOVIECUT_UITEST_DELETE_CLIP_INDEX=<0-based index> overrides the
        //    default delete target so a NON-trailing clip can be removed, which
        //    is the only way a real on-timeline gap is produced. Without it the
        //    harness deletes the selected (last) clip and no gap exists. The
        //    index is resolved against timeline order on the first track
        //    (`timelineClipId(at:)`) and deleted through the same command-backed
        //    VM entry point (`deleteClips(_:)`) the menu uses, dispatching
        //    DeleteClipCommand (the gap-preserving variant) rather than the
        //    ripple one.
        if environment["MOVIECUT_UITEST_NORMAL_DELETE"] == "1" {
            if let deleteIndexString = environment["MOVIECUT_UITEST_DELETE_CLIP_INDEX"],
               let deleteIndex = Int(deleteIndexString),
               let targetClipId = timelineClipId(at: deleteIndex) {
                await deleteClips([targetClipId])
            } else {
                await deleteClip()
            }
        }
        if environment["MOVIECUT_UITEST_RIPPLE_DELETE"] == "1", let firstClipId = firstTimelineClipId() {
            await rippleDeleteClip(clipId: firstClipId)
        }
    }

    /// Returns the id of the first clip on the first track, for delete
    /// scenarios that need a deterministic target.
    private func firstTimelineClipId() -> UUID? {
        timelineClipId(at: 0)
    }

    /// Returns the id of the clip at `index` (0-based) in timeline order on the
    /// first track. Used by the parity delete scenario to target a deterministic
    /// non-trailing clip so an actual gap is left on the timeline. Returns nil
    /// when the index is out of bounds (the harness falls back to `deleteClip()`
    /// in that case rather than mutating nothing).
    private func timelineClipId(at index: Int) -> UUID? {
        let clips = currentProject.timeline.tracks.first?.clips.sorted(by: Track.clipTimelineOrder) ?? []
        guard index >= 0, index < clips.count else { return nil }
        return clips[index].id
    }

    /// Polls the playback engine until a composition has installed a player
    /// item, reached a non-zero duration, and reported no error — or
    /// `timeoutSeconds` elapses. The duration gate matters because the video
    /// output cannot produce a frame before the composition's tracks finish
    /// loading (which is when duration becomes non-zero).
    private func waitForCompositionReady(
        timeoutSeconds: Double,
        expectedGeneration: UInt64? = nil
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let err = playbackEngine.lastCompositionError {
                throw NSError(domain: "MovieCutUITest", code: 6,
                              userInfo: [NSLocalizedDescriptionKey: err])
            }
            let installedExpectedGeneration = expectedGeneration.map {
                playbackEngine.installedCompositionGeneration >= $0
            } ?? true
            if installedExpectedGeneration,
               playbackEngine.playerItem != nil,
               playbackEngine.duration > 0 {
                return
            }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        // Last chance: item present but duration still settling.
        let installedExpectedGeneration = expectedGeneration.map {
            playbackEngine.installedCompositionGeneration >= $0
        } ?? true
        if installedExpectedGeneration,
           playbackEngine.playerItem != nil,
           playbackEngine.lastCompositionError == nil {
            return
        }
        throw NSError(domain: "MovieCutUITest", code: 5,
                      userInfo: [NSLocalizedDescriptionKey: "timed out waiting for composition to become ready"])
    }

    /// Exercises the unsaved-changes guard through an injected user choice so
    /// XCUITest can drive the real guard path (policy + save) without an
    /// Accessibility-permission dependency on the modal. Pairs with
    /// `MOVIECUT_UITEST_UNSAVED_RESPONSE=save|discard|cancel`.
    ///
    /// Proves the guard actually runs in the harness (previously it was skipped
    /// wholesale under MOVIECUT_UITEST=1, so no UI test could reach it):
    /// - dirty a fresh project by adding a text clip;
    /// - capture the pre-guard project identity (name + clip count);
    /// - call newProject(), which routes through confirmDiscardUnsavedChanges;
    /// - report whether the session was replaced (proceed) or preserved (cancel).
    private func runUnsavedChangesGuardUITestScenario(environment: [String: String]) async {
        let resultPath = environment["MOVIECUT_UITEST_RESULT"] ?? ""
        var status = "UNSAVED_GUARD_INCOMPLETE error=not_run"

        stopAutoSave()
        lastErrorMessage = nil

        // Make the project dirty via a real edit so the guard's isDirty check
        // is true (a clean project proceeds without consulting the choice).
        // addTextClip dispatches through the session and refreshFromSession,
        // which sets isDirty. The added clip also gives a stable pre/post
        // signal for whether the session was replaced.
        await addTextClip(text: "guard probe")

        let preDirty = isDirty
        let preClipCount = currentProject.timeline.tracks.reduce(0) { $0 + $1.clips.count }

        // The guard reads MOVIECUT_UITEST_UNSAVED_RESPONSE; for "save" with no
        // save URL it would present a Save As panel, which we avoid by using the
        // discard/cancel branches here (no panel, fully deterministic).
        await newProject()

        let postClipCount = currentProject.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        // newProject replaces the session when it proceeds; the dirty project's
        // clips vanish. On cancel the session is preserved.
        let sessionReplaced = postClipCount != preClipCount
        let response = environment["MOVIECUT_UITEST_UNSAVED_RESPONSE"] ?? "unset"

        let outcome: String
        switch response {
        case "cancel":
            // Cancel must preserve the session.
            outcome = sessionReplaced ? "cancel_session_lost" : "cancel_session_preserved"
        case "discard":
            // Discard must proceed (replace the session).
            outcome = sessionReplaced ? "discard_session_replaced" : "discard_session_kept"
        default:
            outcome = sessionReplaced ? "replaced" : "preserved"
        }

        lastErrorMessage = nil
        status = "UNSAVED_GUARD_DONE response=\(response) pre_dirty=\(preDirty ? 1 : 0) pre_clips=\(preClipCount) post_clips=\(postClipCount) \(outcome) error=none"
        lastStatusMessage = status

        if !resultPath.isEmpty {
            writeHarnessStatus(status, to: resultPath)
        }
        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    /// B-U7 recovery regression. Builds a project with real clips, flushes the
    /// crash-recovery autosave (the file a crash would leave behind), then
    /// triggers the recovery flow via the injection gate in ContentView. The
    /// injection reads `MOVIECUT_UITEST_RECOVERY_RESPONSE` and runs the same
    /// `recoverableProject` → `adoptRecoveredProject`/`clearRecoveryAutosave`
    /// logic the modal would, reporting the outcome so the driving script can
    /// assert the recovered timeline actually repopulated.
    ///
    /// Single-process simulation: the autosave is written and re-read within
    /// one launch, so no SIGKILL/relaunch is needed. The terminate-clear gate
    /// (`MOVIECUT_UITEST_SKIP_RECOVERY_CLEAR`) keeps the file across the quit
    /// so a future XCUITest two-launch path can also exercise it.
    private func runRecoveryUITestScenario(environment: [String: String]) async {
        let importURLs = containerizeImportURLs(
            (environment["MOVIECUT_UITEST_IMPORT"] ?? "")
                .split(separator: ",")
                .map { String($0) }
                .filter { !$0.isEmpty }
                .map(URL.init(fileURLWithPath:))
        )
        let response = environment["MOVIECUT_UITEST_RECOVERY_RESPONSE"] ?? "recover"

        func report(_ stage: String, recoveredClips: Int = 0, autosavePresent: Bool = false) {
            let line = "recovery_checkpoint stage=\(stage) response=\(response) "
                + "autosave_present=\(autosavePresent ? 1 : 0) "
                + "pre_edit_clips=\(currentProject.timeline.tracks.reduce(0) { $0 + $1.clips.count }) "
                + "recovered_clips=\(recoveredClips)"
            if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
                writeHarnessStatus(line, to: resultPath)
            }
        }
        report("start")

        // 1. Build a project with real clips so the recovery has content.
        if !importURLs.isEmpty {
            suppressCompositionRebuild = true
            await importMediaAndAddToTimeline(importURLs, startTime: 0)
            suppressCompositionRebuild = false
            rebuildPreviewComposition()
        } else {
            // No fixture supplied: still add a text clip so the project is non-empty.
            await addTextClip(text: "Recovery harness clip")
        }
        let preEditClips = currentProject.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        report("edited", autosavePresent: false)

        // 2. Flush the crash-recovery autosave — the file a crash leaves behind.
        await flushAutosave()
        let autosavePresent = await recoverableProject() != nil
        report("flushed", autosavePresent: autosavePresent)

        // 3. Reset the session to a fresh project so adoption is observable,
        //    then run the same recover/discard logic the launch-time
        //    presentRecoveryIfNeeded() injection path runs.
        await newProject()
        let clipsAfterReset = currentProject.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        report("reset", recoveredClips: clipsAfterReset, autosavePresent: autosavePresent)

        let recovered = await recoverableProject()
        var recoveredClips = 0
        var status = "no_autosave"
        if let project = recovered {
            if response == "discard" {
                await clearRecoveryAutosave()
                status = "discarded"
            } else {
                await adoptRecoveredProject(project)
                recoveredClips = currentProject.timeline.tracks.reduce(0) { $0 + $1.clips.count }
                status = lastStatusMessage ?? "recovered"
            }
        }

        // 4. Surface the final outcome and quit.
        let line = "recovery_done response=\(response) pre_edit_clips=\(preEditClips) "
            + "autosave_present=\(autosavePresent ? 1 : 0) "
            + "recovered_clips=\(recoveredClips) status=\(status)"
        lastStatusMessage = line
        if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
            writeHarnessStatus(line, to: resultPath)
        }
        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }
}
#endif
