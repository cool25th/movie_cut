import Foundation
import Testing

/// Phase 3-3 exposes the existing speed-ramp model in the inspector UI only.
@Suite("Phase 3-3 Speed Curve Editor StaticContract")
struct Phase33SpeedCurveEditorStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase33SpeedCurveEditorStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase33SpeedCurveEditorStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Speed section keeps constant speed controls and mounts the speed curve editor")
    func speedSectionKeepsConstantSpeedControlsAndMountsCurveEditor() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let speedSection = try section(
            in: inspector,
            from: "private var speedSection: some View",
            to: "    private var speedCurveEditor"
        )

        #expect(speedSection.contains("Text(\"Speed\")"))
        #expect(speedSection.contains("Text(String(format: \"%.0f%%\", clip.playbackRate * 100))"))
        #expect(speedSection.contains("Slider(value: Binding("))
        #expect(speedSection.contains("get: { clip.playbackRate }"))
        #expect(speedSection.contains("viewModel.updateSelectedPlaybackRate(newValue)"))
        #expect(speedSection.contains("ForEach(speedPresets, id: \\.self)"))
        #expect(speedSection.contains("viewModel.updateSelectedPlaybackRate(preset)"))
        // Task 1.3: the `Toggle("부드러운 슬로우모션"` and
        // `Text("내보낼 때 프레임 보간이 적용됩니다")` assertions were deleted. Both were
        // copy trivia on SwiftUI implicit `LocalizedStringKey`s, and the three
        // assertions that follow already pin the optical-flow control itself
        // (binding, command call, disabled rule). Whether that toggle reads
        // English in an English locale is task 1.4's locale sweep, not a source
        // literal check.
        #expect(speedSection.contains("get: { clip.useOpticalFlow }"))
        #expect(speedSection.contains("viewModel.updateSelectedOpticalFlow(newValue)"))
        #expect(speedSection.contains(".disabled(clip.playbackRate >= 1.0)"))
        #expect(speedSection.contains("speedCurveEditor"))
        #expect(speedSection.contains(#".accessibilityLabel("Constant speed")"#))
    }

    @Test("Speed curve editor exposes presets add reset point editing and accessibility")
    func speedCurveEditorExposesPresetsAddResetPointEditingAndAccessibility() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let editor = try section(
            in: inspector,
            from: "private var speedCurveEditor: some View",
            to: "    private var speedUnavailableSection"
        )

        #expect(inspector.contains("private struct SpeedCurvePreset: Identifiable"))
        #expect(inspector.contains("private let speedCurvePresets: [SpeedCurvePreset]"))
        #expect(inspector.contains("SpeedRampPoint(time:"))
        #expect(inspector.contains(#"id: "easeIn""#))
        #expect(inspector.contains(#"name: "Ease In""#))
        #expect(inspector.contains(#"id: "easeOut""#))
        #expect(inspector.contains(#"name: "Ease Out""#))
        #expect(inspector.contains(#"id: "montageFlash""#))
        #expect(inspector.contains(#"name: "Flash""#))
        #expect(editor.contains("ForEach(speedCurvePresets)"))
        #expect(editor.contains("applySpeedCurvePreset(preset)"))
        #expect(editor.contains("addSpeedCurvePoint()"))
        #expect(editor.contains("resetSpeedCurve()"))
        #expect(editor.contains("ForEach(Array(points.enumerated()), id: \\.element.id)"))
        #expect(editor.contains("updateSpeedCurvePoint(point.id, time: newValue, rate: point.rate)"))
        #expect(editor.contains("updateSpeedCurvePoint(point.id, time: point.time, rate: newValue)"))
        #expect(editor.contains("deleteSpeedCurvePoint(point.id)"))
        #expect(editor.contains("points.count > minimumSpeedCurvePointCount"))
        #expect(editor.contains("in: 0 ... 1"))
        #expect(editor.contains("in: 0.25 ... 4.0"))
        #expect(editor.contains("viewModel.updateSelectedSpeedRampPoints"))

        for accessibilityMarker in [
            #".accessibilityLabel("Speed Curve")"#,
            #".accessibilityHint("Edits the selected clip normalized speed ramp curve.")"#,
            #".accessibilityLabel("Add Speed Curve Point")"#,
            #".accessibilityLabel("Reset Speed Curve")"#,
            #".accessibilityLabel("Speed curve point time")"#,
            #".accessibilityLabel("Speed curve point rate")"#,
            #".accessibilityLabel("Speed curve point delete")"#
        ] {
            #expect(editor.contains(accessibilityMarker))
        }
    }

    @Test("Speed curve helpers clamp sort preserve IDs and route through existing ViewModel method")
    func speedCurveHelpersClampSortPreserveIDsAndRouteThroughExistingViewModelMethod() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let normalizer = try section(
            in: inspector,
            from: "private func normalizedSpeedRampPoints(_ points: [SpeedRampPoint]) -> [SpeedRampPoint]",
            to: "    private func applySpeedCurvePreset"
        )
        let addPoint = try section(
            in: inspector,
            from: "private func addSpeedCurvePoint()",
            to: "    private func updateSpeedCurvePoint"
        )
        let updatePoint = try section(
            in: inspector,
            from: "private func updateSpeedCurvePoint(_ id: SpeedRampPoint.ID, time: Double, rate: Double)",
            to: "    private func deleteSpeedCurvePoint"
        )
        let deletePoint = try section(
            in: inspector,
            from: "private func deleteSpeedCurvePoint(_ id: SpeedRampPoint.ID)",
            to: "    private func resetSpeedCurve"
        )
        let resetCurve = try section(
            in: inspector,
            from: "private func resetSpeedCurve()",
            to: "    private func defaultSpeedCurvePointTime"
        )

        #expect(normalizer.contains("SpeedRampPoint(id: point.id, time: point.time, rate: point.rate)"))
        #expect(normalizer.contains(".sorted { lhs, rhs in"))
        #expect(normalizer.contains("return lhs.time < rhs.time"))
        #expect(addPoint.contains("normalizedSpeedRampPoints(clip.speedRampPoints)"))
        #expect(addPoint.contains("SpeedRampPoint("))
        #expect(addPoint.contains("Task { await viewModel.updateSelectedSpeedRampPoints(normalizedSpeedRampPoints(points)) }"))
        #expect(updatePoint.contains("if point.id == id"))
        #expect(updatePoint.contains("SpeedRampPoint(id: point.id, time: time, rate: rate)"))
        #expect(updatePoint.contains("Task { await viewModel.updateSelectedSpeedRampPoints(normalizedSpeedRampPoints(points)) }"))
        #expect(deletePoint.contains("guard points.count > minimumSpeedCurvePointCount else { return }"))
        #expect(deletePoint.contains("points.filter { $0.id != id }"))
        #expect(deletePoint.contains("viewModel.updateSelectedSpeedRampPoints"))
        #expect(resetCurve.contains("viewModel.updateSelectedSpeedRampPoints([])"))
    }

    @Test("Speed curve editor stays UI-only and does not couple core export playback or ViewModel to UI markers")
    func speedCurveEditorStaysUIOnly() throws {
        for path in [
            "Sources/MovieCutCore/Models/SpeedRampCurve.swift",
            "Sources/MovieCutCore/Models/SpeedRampPoint.swift",
            "Sources/MovieCutCore/Commands/SetClipPropertyCommand.swift",
            "App/MovieCutMac/Export/ExportEngine.swift",
            "App/MovieCutMac/Playback/PlaybackEngine.swift"
        ] {
            let serviceSource = try source(path)
            for uiMarker in [
                "speedCurveEditor",
                "SpeedCurvePreset",
                "speedCurvePresets",
                "Add Speed Curve Point",
                "Reset Speed Curve",
                "Speed curve point"
            ] {
                #expect(!serviceSource.contains(uiMarker))
            }
        }

        // Main file + inspector boundary (updateSelectedSpeedRampPoints moved
        // there in the decomposition); the UI-marker ban covers both parts.
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
            + source("App/MovieCutMac/EditorViewModel+Inspector.swift")
        #expect(viewModel.contains("func updateSelectedSpeedRampPoints(_ points: [SpeedRampPoint]) async"))
        for uiMarker in [
            "speedCurveEditor",
            "SpeedCurvePreset",
            "Add Speed Curve Point",
            "Reset Speed Curve",
            "Speed curve point"
        ] {
            #expect(!viewModel.contains(uiMarker))
        }
    }
}

private enum Phase33SpeedCurveEditorStaticContractError: Error {
    case missingMarker(String)
}
