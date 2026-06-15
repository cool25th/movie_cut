import Foundation
import Testing

/// UX-08 is a source-level regression guard for the macOS presentation layer:
/// UI rearrangement must keep VoiceOver labels/values/hints and F-05 shortcuts visible.
@Suite("UIUX Accessibility Regression StaticContract")
struct UIUXAccessibilityRegressionStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("UX-08 StaticContract keeps F-05 command menus visible")
    func ux08StaticContractKeepsF05CommandMenusVisible() throws {
        let app = try source("App/MovieCutMac/MovieCutMacApp.swift")
        let shortcutContract = try source("Tests/MovieCutCoreTests/KeyboardShortcutStaticContractTests.swift")

        for marker in [
            #"CommandMenu("Playback")"#,
            #"CommandMenu("Timeline")"#,
            #"Button("Play/Pause")"#,
            #".keyboardShortcut(.space, modifiers: [])"#,
            #"Button("Step Back One Frame")"#,
            #".keyboardShortcut(.leftArrow, modifiers: [])"#,
            #"Button("Step Forward One Frame")"#,
            #".keyboardShortcut(.rightArrow, modifiers: [])"#,
            #"Button("Split at Playhead")"#,
            #".keyboardShortcut("b", modifiers: .command)"#,
            #"Button("Trim Start to Playhead")"#,
            #".keyboardShortcut("q", modifiers: [])"#,
            #"Button("Trim End to Playhead")"#,
            #".keyboardShortcut("w", modifiers: [])"#,
            #"Button("Delete Selected Clips")"#,
            #".keyboardShortcut(.delete, modifiers: [])"#,
            #"Button("Ripple Delete Selected Clip")"#,
            #".keyboardShortcut(.delete, modifiers: [.shift])"#,
            #"Button("Duplicate Selected Clips")"#,
            #".keyboardShortcut("d", modifiers: .command)"#,
            #"Button("Zoom In")"#,
            #".keyboardShortcut("+", modifiers: [])"#,
            #"Button("Zoom Out")"#,
            #".keyboardShortcut("-", modifiers: [])"#,
            #"Button("Add Marker")"#,
            #".keyboardShortcut("m", modifiers: [])"#,
        ] {
            #expect(app.contains(marker))
        }

        #expect(shortcutContract.contains(#"@Suite("Keyboard Shortcut StaticContract")"#))
        #expect(shortcutContract.contains("macOS app menus register the F-05 playback and timeline shortcuts"))
        #expect(shortcutContract.contains("text-entry-sensitive shortcuts are centralized and guarded"))
    }

    @Test("UX-08 StaticContract preserves preview accessibility")
    func ux08StaticContractPreservesPreviewAccessibility() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")

        for marker in [
            #"accessibilityLabel(NSLocalizedString("Preview", comment: ""))"#,
            #"accessibilityValue(previewAccessibilityValue)"#,
            #"accessibilityLabel: NSLocalizedString("Current Time", comment: "")"#,
            #"accessibilityLabel: NSLocalizedString("Duration", comment: "")"#,
            #"accessibilityLabel(NSLocalizedString("Seek Back One Frame", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Moves the playhead back by one frame.", comment: ""))"#,
            #"NSLocalizedString("Pause", comment: "") : NSLocalizedString("Play", comment: "")"#,
            #"accessibilityHint(NSLocalizedString("Starts or pauses preview playback.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Seek Forward One Frame", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Moves the playhead forward by one frame.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Playback transport", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Canvas ratio", comment: ""))"#,
            #"accessibilityValue(canvasRatioText)"#,
            #"accessibilityLabel(NSLocalizedString("Volume", comment: ""))"#,
            #"accessibilityValue(String(format: NSLocalizedString("%.0f%%", comment: ""), previewVolume * 100))"#,
            #"accessibilityHint(NSLocalizedString("Adjusts preview playback volume.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Import media", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Opens a file picker for video, audio, or image assets.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Preview transport controls", comment: ""))"#,
        ] {
            #expect(preview.contains(marker))
        }
    }

    @Test("UX-08 StaticContract preserves media library accessibility")
    func ux08StaticContractPreservesMediaLibraryAccessibility() throws {
        let mediaLibrary = try source("App/MovieCutMac/MediaLibraryPanel.swift")

        for marker in [
            #"accessibilityLabel(NSLocalizedString("Library", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Drop media files here to import them.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Import", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Opens a file picker to import media.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Add Text", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Creates a new text clip.", comment: ""))"#,
            #"accessibilityLabel(tab.displayName)"#,
            #"accessibilityHint(tab.accessibilityHint)"#,
            #"accessibilityLabel(NSLocalizedString("Library browser tabs", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Add to Timeline", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Adds the selected library asset to the timeline.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Asset List", comment: ""))"#,
            #"accessibilityValue(assetAccessibilityValue(asset))"#,
            #"private func assetAccessibilityValue(_ asset: MediaAsset) -> String"#,
            #"if let metadata = metadataSummary(asset)"#,
            #"states.append(metadata)"#,
            #"states.append(NSLocalizedString("draggable to timeline", comment: ""))"#,
        ] {
            #expect(mediaLibrary.contains(marker))
        }
    }

    @Test("UX-08 StaticContract preserves timeline accessibility")
    func ux08StaticContractPreservesTimelineAccessibility() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")

        for marker in [
            #"title: NSLocalizedString("Timeline", comment: "")"#,
            #"accessibilityLabel(NSLocalizedString("타임라인", comment: ""))"#,
            #"accessibilityLabel(trackHeaderAccessibilityLabel(for: track))"#,
            #"accessibilityLabel(String(format: NSLocalizedString("%@ 클립 추가 영역", comment: ""), trackHeaderAccessibilityLabel(for: track)))"#,
            #"accessibilityHint(NSLocalizedString("Drop media files or library assets here to add clips at the drop position.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Timeline edit tools", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Snap Playhead to Clip Start", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Moves the playhead to the selected clip start.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Snap Playhead to Clip End", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Moves the playhead to the selected clip end.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Split at Playhead", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Splits the selected clip at the playhead.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Reverse Selected Clip", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Reverse Selected Clip toggles reverse playback for the selected visual clip.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Freeze Selected Frame", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Freeze Selected Frame inserts a still frame at the playhead for the selected visual clip.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Duplicate Selected Clips", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Duplicates the selected clips on the timeline.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Send Selected Clip to Back", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Moves the selected clip behind the other tracks.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Bring Selected Clip to Front", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Moves the selected clip in front of the other tracks.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Delete Selected Clips", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Deletes the selected clips from the timeline.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Ripple Delete Selected Clip", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Deletes the selected clip and closes the resulting gap.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Timeline zoom controls", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Zooms the timeline out.", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Zooms the timeline in.", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Selects the clip. Drag to move it on the timeline. Layer actions adjust its zIndex.", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Drag to trim the clip start.", comment: ""))"#,
            #"accessibilityHint(NSLocalizedString("Drag to trim the clip end.", comment: ""))"#,
        ] {
            #expect(timeline.contains(marker))
        }
    }

    @Test("UX-08 StaticContract preserves inspector section labels")
    func ux08StaticContractPreservesInspectorSectionLabels() throws {
        let inspector = try source("App/MovieCutMac/InspectorPanel.swift")
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")

        for marker in [
            #"title: viewModel.selectedClip == nil ? "Inspector" : "Clip""#,
            #"title: "Project Tools""#,
            #"Label("Markers", systemImage: "flag.fill")"#,
            #"Label("AI Assistant", systemImage: "sparkles")"#,
            #"Label("Auto Highlights", systemImage: "wand.and.stars")"#,
            #"Label("Analysis Results", systemImage: "chart.line.uptrend.xyaxis")"#,
            #"selectedClipInspectorSections(for: clip)"#,
            #"mode: InspectorBasicMode.audio"#,
            #"mode: InspectorBasicMode.text"#,
            #"visualClipInspectorSections(for: clip)"#,
            #"Picker("Inspector section", selection: $selectedInspectorSubtab)"#,
            #".accessibilityLabel("Inspector section")"#,
            #".accessibilityHint("Switches between clip inspector sections.")"#,
            #"InspectorAnalysisSection(viewModel: viewModel, clip: clip)"#,
        ] {
            #expect(inspector.contains(marker))
        }

        #expect(shared.contains("struct MovieCutPanelHeader"))
        #expect(shared.contains("struct MovieCutSectionCard"))
        #expect(shared.contains("MovieCutIconTitle(title: title, systemImage: systemImage"))
    }

    @Test("UX-08 StaticContract docs mark source-level guard implemented")
    func ux08StaticContractDocsMarkSourceLevelGuardImplemented() throws {
        let handoff = try source("docs/UIUX_HANDOFF.md")

        #expect(handoff.contains("#### UX-08. 접근성·키보드 유지 ✅ 구현(2026-06-16)"))
        #expect(handoff.contains("UIUXAccessibilityRegressionStaticContractTests.swift"))
        #expect(handoff.contains("VoiceOver 실기기 리딩·스크린샷 검증은 별도 검증 범위"))
    }
}
