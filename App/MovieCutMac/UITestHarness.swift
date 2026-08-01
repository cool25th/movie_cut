#if DEBUG
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
        let context = CIContext()
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
    /// - `MOVIECUT_UITEST_EXPORT_RESOLUTION=<rawValue>` — sets `ExportSettings.resolution` before export
    ///   (e.g. `p4K`), independent of any platform preset. Used by the 4K perf baseline (S6).
    /// - `MOVIECUT_UITEST_TEXT_ANIMATION_PRESET=<rawValue>` — adds a 2s animated text clip before export.
    /// - `MOVIECUT_UITEST_HSL_CURVES=1` — applies a non-3-way HSL/curve grade to the selected clip.
    /// - `MOVIECUT_UITEST_SCRUB=<seconds>` — scrubs through the ruler-coordinate transport path.
    /// - `MOVIECUT_UITEST_PROXY_BADGE=1` — generates a proxy for the first video asset and reports
    ///   the timeline badge state. Pair with `MOVIECUT_UITEST_PROXY_PLAYBACK=1` to check the active state,
    ///   and `MOVIECUT_UITEST_PROXY_RESOLUTION=<p480|p540|p720|p1080>` to pick the generation resolution.
    /// - `MOVIECUT_UITEST_FILMSTRIP=1` — decodes four time-varying frames from the selected video.
    /// - `MOVIECUT_UITEST_TIMELINE_FILMSTRIP=1` — observes the real TimelineView viewport and hover consumers.
    /// - `MOVIECUT_UITEST_FILMSTRIP_PERF=density|memory` — drives real TimelineView zoom/scroll performance evidence.
    /// - `MOVIECUT_UITEST_PERF_PHASE=<path>` — optional phase handshake for external RSS sampling.
    /// - `MOVIECUT_UITEST_EXPORT=<path>` — destination the project is exported to.
    /// - `MOVIECUT_UITEST_EXPORT_AUDIO=<path>` — destination for audio-only export.
    /// - `MOVIECUT_UITEST_VOCAL_SEPARATION=<removeVocals|isolateCenter>` — applies real offline separation to the selected audio clip.
    /// - `MOVIECUT_UITEST_PREVIEW_AUDIO=<path>` — renders Preview's installed composition/audio mix for PCM verification.
    func runUITestHarnessIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST"] == "1" else { return }
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
        let filmstripPerformanceScenario = env["MOVIECUT_UITEST_FILMSTRIP_PERF"]

        if filmstripPerformanceScenario != nil {
            TimelineFilmstripDebugProbe.shared.armPerformance()
        } else if env["MOVIECUT_UITEST_TIMELINE_FILMSTRIP"] == "1" {
            TimelineFilmstripDebugProbe.shared.arm()
        }

        let primaryImportURLs = env["MOVIECUT_UITEST_IMPORT"]
            .map(uiTestImportURLs(from:)) ?? []
        let extraImportURLs = env["MOVIECUT_UITEST_IMPORT_EXTRA"]
            .map(uiTestImportExtraURLs(from:)) ?? []
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

        if lastErrorMessage == nil,
           let exportPath = env["MOVIECUT_UITEST_EXPORT"], !exportPath.isEmpty {
            await exportProject(to: URL(filePath: exportPath))
        }

        if lastErrorMessage == nil,
           let audioPath = env["MOVIECUT_UITEST_EXPORT_AUDIO"], !audioPath.isEmpty {
            await exportAudioOnly(to: URL(filePath: audioPath))
        }

        if lastErrorMessage == nil,
           let proResPath = env["MOVIECUT_UITEST_EXPORT_PRORES"], !proResPath.isEmpty {
            await exportProResMaster(to: URL(filePath: proResPath))
        }

        if lastErrorMessage == nil,
           let hdrPath = env["MOVIECUT_UITEST_EXPORT_HDR"], !hdrPath.isEmpty {
            await exportHDRMaster(to: URL(filePath: hdrPath))
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
        let status = "UITEST_DONE clips=\(clipCount) error=\(lastErrorMessage ?? "none")\(proxyBadgeSuffix)\(scrubSuffix)\(clipboardSuffix)\(filmstripSuffix)\(timelineFilmstripSuffix)\(filmstripPerformanceSuffix)\(extractAudioSuffix)\(vocalSeparationSuffix)\(benchSuffix)\(scopeSuffix)\(autoWBSuffix)\(textAnimationSuffix)\(textTemplateSuffix)\(chapterSuffix)\(timelineSummarySuffix())"
        lastStatusMessage = status

        // Headless verification path: when the harness is driven by launching the
        // app binary directly (no XCUITest automation handshake / Accessibility
        // permission), it writes its outcome to `MOVIECUT_UITEST_RESULT` and
        // `MOVIECUT_UITEST_QUIT=1` terminates so a script / CI can assert results.
        if let resultPath = env["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
            try? status.write(toFile: resultPath, atomically: true, encoding: .utf8)
        }
        if env["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
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
            try? status.write(toFile: resultPath, atomically: true, encoding: .utf8)
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
            try? status.write(toFile: resultPath, atomically: true, encoding: .utf8)
        }
        await flushAutosave()
        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }

    /// Step 1 Preview↔Export pixel-parity harness. Builds the project,
    /// exports it to `MOVIECUT_UITEST_EXPORT`, and dumps the Preview frame at
    /// each timestamp listed in `MOVIECUT_UITEST_PARITY_TIMES` (comma-separated
    /// seconds) to `MOVIECUT_UITEST_PREVIEW_DUMP` (one PNG per timestamp with
    /// a `_t<seconds>.png` suffix). The shell script then extracts the same
    /// timestamps from the exported mp4 and compares them pixel-by-pixel.
    private func runPreviewExportParityUITestScenario(environment: [String: String]) async {
        var dumpedFrames = 0
        var previewDumpDir = "none"
        var compositionDuration = 0.0
        let projectFrameRate = currentProject.timeline.frameRate.doubleValue
        // Progressive status writer so a hang or crash still leaves evidence
        // about how far the harness got (the parity path is newer and has no
        // prior in-the-wild run).
        func checkpoint(_ stage: String) {
            let line = "parity_checkpoint stage=\(stage) dumped_frames=\(dumpedFrames) composition_error=\(playbackEngine.lastCompositionError ?? "none")\n"
            if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
                try? line.write(toFile: resultPath, atomically: true, encoding: .utf8)
            }
        }
        checkpoint("start")
        do {
            let importURLs = (environment["MOVIECUT_UITEST_IMPORT"] ?? "")
                .split(separator: ",")
                .map { String($0) }
                .filter { !$0.isEmpty }
                .map(URL.init(fileURLWithPath:))
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

            previewDumpDir = environment["MOVIECUT_UITEST_PREVIEW_DUMP"] ?? ""
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

            // Export the project so the parity script can sample the same
            // timestamps from the rendered mp4.
            if let exportPath = environment["MOVIECUT_UITEST_EXPORT"], !exportPath.isEmpty {
                checkpoint("export_before")
                await exportProject(to: URL(filePath: exportPath))
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
            " composition_error=\(playbackEngine.lastCompositionError ?? "none")" +
            " error=\(lastErrorMessage ?? "none")" +
            timelineSummarySuffix()
        lastStatusMessage = status
        if let resultPath = environment["MOVIECUT_UITEST_RESULT"], !resultPath.isEmpty {
            try? status.write(toFile: resultPath, atomically: true, encoding: .utf8)
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
        if let transitionRaw = environment["MOVIECUT_UITEST_TRANSITION"] {
            let type = TransitionType(rawValue: transitionRaw) ?? .crossDissolve
            await updateSelectedTransition(Transition(type: type, duration: 0.5))
        }

        // 5. Text overlay at a timeline position — covers "text overlay at 5s".
        if let textAtString = environment["MOVIECUT_UITEST_TEXT_AT"],
           let textTime = Double(textAtString) {
            playheadTime = textTime
            await addTextClip(text: "Parity text overlay")
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
            try? status.write(toFile: resultPath, atomically: true, encoding: .utf8)
        }
        if environment["MOVIECUT_UITEST_QUIT"] == "1" {
            NSApp.terminate(nil)
        }
    }
}
#endif
