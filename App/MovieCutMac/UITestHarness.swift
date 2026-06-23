#if DEBUG
import AppKit
import Foundation

extension EditorViewModel {
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

        let clipCount = currentProject.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        let status = "UITEST_DONE clips=\(clipCount) error=\(lastErrorMessage ?? "none")"
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
