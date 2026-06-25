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
    /// - `MOVIECUT_UITEST_IMPORT=<path>` — media imported and added to the timeline.
    /// - `MOVIECUT_UITEST_EXPORT=<path>` — destination the project is exported to.
    func runUITestHarnessIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST"] == "1" else { return }

        if let importPath = env["MOVIECUT_UITEST_IMPORT"], !importPath.isEmpty {
            await importMediaAndAddToTimeline(
                [URL(filePath: importPath)],
                startTime: currentProject.timeline.duration
            )
        }

        // Optional freeze-frame step: holds a single frame for 2s mid-clip, so an
        // E2E check can confirm freeze is reflected in export (output duration
        // grows by the freeze duration).
        if env["MOVIECUT_UITEST_FREEZE"] == "1", let clip = selectedClip {
            playheadTime = clip.timelineRange.start + clip.timelineRange.duration / 2
            await freezeSelectedFrame(freezeDuration: 2.0)
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

        if lastErrorMessage == nil,
           let exportPath = env["MOVIECUT_UITEST_EXPORT"], !exportPath.isEmpty {
            await exportProject(to: URL(filePath: exportPath))
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
        let status = "UITEST_DONE clips=\(clipCount) error=\(lastErrorMessage ?? "none")\(benchSuffix)\(scopeSuffix)"
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
}
#endif
