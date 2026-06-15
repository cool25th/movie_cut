import Foundation
import Testing

/// R5-02 keeps timeline zoom presentation-scoped while adding CapCut-style
/// continuous zoom and fit affordances to the timeline header.
@Suite("R5-02 Timeline Zoom StaticContract")
struct R502TimelineZoomStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R502TimelineZoomStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R502TimelineZoomStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Zoom controls expose a continuous slider bound to timelineZoom")
    func zoomControlsExposeContinuousSliderBoundToTimelineZoom() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let zoomControls = try section(
            in: timeline,
            from: "private var zoomControls: some View",
            to: "    private var timelineZoomDisplay"
        )

        #expect(zoomControls.contains("Slider(value:"))
        #expect(zoomControls.contains("get: { viewModel.timelineZoom }"))
        #expect(zoomControls.contains("set: { viewModel.timelineZoom = clampedTimelineZoom($0) }"))
        #expect(zoomControls.contains("in: timelineZoomRange"))
        #expect(zoomControls.contains(#"accessibilityLabel(NSLocalizedString("Timeline zoom slider", comment: ""))"#))
        #expect(zoomControls.contains(#"accessibilityHint(NSLocalizedString("Adjusts pixels per second in the timeline.", comment: ""))"#))
    }

    @Test("Zoom controls keep plus minus and current pixels-per-second readout")
    func zoomControlsKeepButtonsAndCurrentZoomReadout() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let zoomControls = try section(
            in: timeline,
            from: "private var zoomControls: some View",
            to: "    private var timelineZoomDisplay"
        )
        let display = try section(
            in: timeline,
            from: "private var timelineZoomDisplay: String",
            to: "    private func fitTimelineToAvailableWidth"
        )

        #expect(zoomControls.contains("Button(action: { viewModel.zoomTimelineOut() })"))
        #expect(zoomControls.contains("Button(action: { viewModel.zoomTimelineIn() })"))
        #expect(zoomControls.contains("Text(timelineZoomDisplay)"))
        #expect(display.contains(#""\(Int(clampedTimelineZoom(viewModel.timelineZoom).rounded())) px/s""#))
    }

    @Test("Fit Timeline button uses presentation helper and accessibility copy")
    func fitTimelineButtonUsesPresentationHelperAndAccessibilityCopy() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let zoomControls = try section(
            in: timeline,
            from: "private var zoomControls: some View",
            to: "    private var timelineZoomDisplay"
        )

        #expect(zoomControls.contains("fitTimelineToAvailableWidth(timelineViewportWidth)"))
        #expect(zoomControls.contains(#"Label(NSLocalizedString("Fit", comment: ""), systemImage: "arrow.left.and.right")"#))
        #expect(zoomControls.contains(#".help("Fit Timeline")"#))
        #expect(zoomControls.contains(#"accessibilityLabel(NSLocalizedString("Fit Timeline", comment: ""))"#))
        #expect(zoomControls.contains(#"accessibilityHint(NSLocalizedString("Fits the visible timeline duration in the available timeline width.", comment: ""))"#))
    }

    @Test("Fit helper computes and clamps timelineZoom in presentation layer")
    func fitHelperComputesAndClampsTimelineZoomInPresentationLayer() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let helper = try section(
            in: timeline,
            from: "private func fitTimelineToAvailableWidth",
            to: "    private var timeRuler"
        )

        #expect(timeline.contains("private let timelineZoomRange: ClosedRange<Double> = 20...300"))
        #expect(helper.contains("viewModel.timelineZoom = fittedTimelineZoom(for: availableWidth)"))
        #expect(helper.contains("viewModel.visibleTimelineDuration"))
        #expect(helper.contains("minimumTimelineContentWidth"))
        #expect(helper.contains("markerLabelWidth"))
        #expect(helper.contains("return clampedTimelineZoom(Double(timelinePixelsWidth / CGFloat(duration)))"))
        #expect(helper.contains("return min(timelineZoomRange.upperBound, max(timelineZoomRange.lowerBound, zoom))"))
        #expect(!helper.contains("EditorSession"))
        #expect(!helper.contains("Command"))
    }

    @Test("R5-02 parity row is marked implemented without overclaiming R5-04")
    func r502ParityRowIsMarkedImplementedWithoutOverclaimingR504() throws {
        let docs = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")

        #expect(docs.contains("| R5-02 | 줌 슬라이더 + fit | ✅ 구현(2026-06-16, Codex R5-02):"))
        #expect(docs.contains("`TimelineView.swift` `zoomControls`에 +/- 버튼, `Slider(value:`"))
        #expect(docs.contains("Fit Timeline"))
        #expect(docs.contains("| R5-04 | 메인 비디오 트랙 개념 | 🟡 |"))
        #expect(!docs.contains("| R5-02 | 줌 슬라이더 + fit | 🟡 +/- 버튼 |"))
    }
}

private enum R502TimelineZoomStaticContractError: Error {
    case missingMarker(String)
}
