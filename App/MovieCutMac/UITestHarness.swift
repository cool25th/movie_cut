#if DEBUG
import AppKit
import CoreImage
import Foundation
import MovieCutCore

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
    /// - `MOVIECUT_UITEST_TEXT_ANIMATION_PRESET=<rawValue>` — adds a 2s animated text clip before export.
    /// - `MOVIECUT_UITEST_HSL_CURVES=1` — applies a non-3-way HSL/curve grade to the selected clip.
    /// - `MOVIECUT_UITEST_SCRUB=<seconds>` — scrubs through the ruler-coordinate transport path.
    /// - `MOVIECUT_UITEST_EXPORT=<path>` — destination the project is exported to.
    /// - `MOVIECUT_UITEST_EXPORT_AUDIO=<path>` — destination for audio-only export.
    func runUITestHarnessIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST"] == "1" else { return }
        var extractAudioSuffix = ""
        var scrubSuffix = ""
        var clipboardSuffix = ""

        let primaryImportURLs = env["MOVIECUT_UITEST_IMPORT"]
            .map(uiTestImportURLs(from:)) ?? []
        let extraImportURLs = env["MOVIECUT_UITEST_IMPORT_EXTRA"]
            .map(uiTestImportExtraURLs(from:)) ?? []
        let importURLs = primaryImportURLs + extraImportURLs
        if !importURLs.isEmpty {
            await importMediaAndAddToTimeline(
                importURLs,
                startTime: currentProject.timeline.duration
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
        let status = "UITEST_DONE clips=\(clipCount) error=\(lastErrorMessage ?? "none")\(scrubSuffix)\(clipboardSuffix)\(extractAudioSuffix)\(benchSuffix)\(scopeSuffix)\(autoWBSuffix)\(textAnimationSuffix)\(textTemplateSuffix)\(chapterSuffix)\(timelineSummarySuffix())"
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

    private enum ClipboardUITestError: LocalizedError {
        case invariant(String)

        var errorDescription: String? {
            switch self {
            case .invariant(let message): message
            }
        }
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
}
#endif
