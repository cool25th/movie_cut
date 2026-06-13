import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

/// F-19 auto reframe: crop-path smoothing math (AC③ jitter reduction) and the
/// clamping that keeps the crop inside the source frame.
@Suite("Reframe Smoothing")
struct ReframeSmoothingTests {
    /// A jittery crop path: a subject drifting right with per-frame noise.
    private func jitteryFrames(count: Int = 30) -> [CropFrame] {
        var frames: [CropFrame] = []
        let width: CGFloat = 0.5
        let height: CGFloat = 0.5
        for index in 0..<count {
            // Deterministic alternating noise around a slow rightward drift.
            let drift = CGFloat(index) / CGFloat(count) * 0.3 + 0.1
            let noise: CGFloat = (index % 2 == 0) ? 0.08 : -0.08
            let centerX = min(max(drift + noise, width / 2), 1 - width / 2)
            let rect = ReframeSmoothing.clampedRect(
                centerX: centerX,
                centerY: 0.5,
                width: width,
                height: height
            )
            frames.append(CropFrame(time: Double(index), rect: rect))
        }
        return frames
    }

    @Test("smoothing reduces frame-to-frame jitter (AC③)")
    func reducesJitter() {
        let raw = jitteryFrames()
        let smoothed = ReframeSmoothing.smooth(raw, windowRadius: 3)

        let rawJitter = ReframeSmoothing.maxCenterDelta(of: raw)
        let smoothedJitter = ReframeSmoothing.maxCenterDelta(of: smoothed)

        #expect(smoothed.count == raw.count)
        #expect(smoothedJitter < rawJitter)
        // The alternating ±0.08 noise (0.16 peak swing) must be visibly damped.
        #expect(smoothedJitter < rawJitter * 0.6)
    }

    @Test("smoothing preserves the overall drift direction")
    func preservesDrift() {
        let raw = jitteryFrames()
        let smoothed = ReframeSmoothing.smooth(raw, windowRadius: 3)
        // The subject drifts right, so the last center should sit right of the first.
        #expect(smoothed.last!.rect.midX > smoothed.first!.rect.midX)
    }

    @Test("clamped rect never extends past the unit square (AC② support)")
    func clampStaysInFrame() {
        // Center pushed beyond the edges with a large crop.
        let rect = ReframeSmoothing.clampedRect(centerX: 0.95, centerY: -0.2, width: 0.6, height: 0.5)
        #expect(rect.minX >= 0)
        #expect(rect.minY >= 0)
        #expect(rect.maxX <= 1.0001)
        #expect(rect.maxY <= 1.0001)
        #expect(abs(rect.width - 0.6) < 0.001)
    }

    @Test("oversized dimensions clamp to the full frame")
    func oversizedClamps() {
        let rect = ReframeSmoothing.clampedRect(centerX: 0.5, centerY: 0.5, width: 1.5, height: 2.0)
        #expect(rect.width <= 1.0001)
        #expect(rect.height <= 1.0001)
    }

    @Test("every smoothed frame stays within the source frame")
    func allSmoothedInBounds() {
        let smoothed = ReframeSmoothing.smooth(jitteryFrames(), windowRadius: 2)
        for frame in smoothed {
            #expect(frame.rect.minX >= 0)
            #expect(frame.rect.minY >= 0)
            #expect(frame.rect.maxX <= 1.0001)
            #expect(frame.rect.maxY <= 1.0001)
        }
    }

    @Test("short inputs pass through unchanged")
    func shortInputsUnchanged() {
        let frames = [
            CropFrame(time: 0, rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)),
            CropFrame(time: 1, rect: CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.5))
        ]
        let smoothed = ReframeSmoothing.smooth(frames, windowRadius: 2)
        #expect(smoothed == frames)
    }

    @Test("smoothing keeps frames time-ordered")
    func keepsTimeOrder() {
        let unordered = [
            CropFrame(time: 2, rect: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)),
            CropFrame(time: 0, rect: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4)),
            CropFrame(time: 1, rect: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4))
        ]
        let smoothed = ReframeSmoothing.smooth(unordered, windowRadius: 1)
        #expect(smoothed.map(\.time) == [0, 1, 2])
    }
}

/// Wiring visibility for the reframe preview UI (not a completion criterion by
/// itself — see spec DoD §1.3).
@Suite("Auto Reframe Preview Static Contract")
struct AutoReframePreviewStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("view model smooths frames and exposes preview/apply/cancel")
    func viewModelExposesPreview() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("ReframeSmoothing.smooth"))
        #expect(viewModel.contains("func previewAutoReframeOnSelection"))
        #expect(viewModel.contains("func applyAutoReframePreview"))
        #expect(viewModel.contains("func cancelAutoReframePreview"))
    }

    @Test("preview panel draws the crop path overlay")
    func previewPanelDrawsOverlay() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        #expect(preview.contains("ReframeCropPathOverlay"))
        #expect(preview.contains("reframePreviewFrames"))
    }

    @Test("inspector exposes reframe preview controls")
    func inspectorExposesControls() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        #expect(inspector.contains("autoReframeSection"))
        #expect(inspector.contains("previewAutoReframeOnSelection"))
        #expect(inspector.contains("applyAutoReframePreview"))
    }
}
