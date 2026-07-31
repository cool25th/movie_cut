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
            #"accessibilityLabel(NSLocalizedString("Preview canvas and export resolution", comment: ""))"#,
            #"accessibilityValue(viewModel.canvasResolutionBadgeText)"#,
            #"accessibilityHint(NSLocalizedString("Shows the preview canvas ratio and computed export render size.", comment: ""))"#,
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
            #"accessibilityLabel(NSLocalizedString("Asset Grid", comment: ""))"#,
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

        // Task 1.3: the four Korean-key markers that used to sit in this array
        // (timeline container label, `%@ 클립 추가 영역`, the two zoom-button
        // labels) were deleted, not re-pinned to their new English keys. They
        // asserted the exact defect requirement 1 removed, and re-pinning would
        // add a new StaticContract (requirement 15.6 forbids that). Their
        // accessibility-regression intent is verified at runtime by
        // `App/MovieCutMacUITests/TimelineAccessibilityLabelUITests.swift`.
        for marker in [
            #"title: NSLocalizedString("Timeline", comment: "")"#,
            #"accessibilityLabel(trackHeaderAccessibilityLabel(for: track))"#,
            #"accessibilityHint(NSLocalizedString("Drop media files or library assets here to add clips at the drop position.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Timeline edit tools", comment: ""))"#,
            "private func timelineToolbarIconButton(",
            "let localizedAccessibilityLabel = accessibilityLabel.map { NSLocalizedString($0, comment: \"\") } ?? localizedTitle",
            ".accessibilityLabel(localizedAccessibilityLabel)",
            ".accessibilityHint(localizedHint)",
            #"title: "Snap Playhead to Clip Start""#,
            #"hint: "Moves the playhead to the selected clip start.""#,
            #"title: "Snap Playhead to Clip End""#,
            #"hint: "Moves the playhead to the selected clip end.""#,
            #"title: "Split at Playhead""#,
            #"hint: "Splits the selected clip at the playhead.""#,
            #"title: "Reverse Selected Clip""#,
            #"hint: "Reverse Selected Clip toggles reverse playback for the selected visual clip.""#,
            #"title: "Freeze Selected Frame""#,
            #"hint: "Freeze Selected Frame inserts a still frame at the playhead for the selected visual clip.""#,
            #"title: "Duplicate Selected Clips""#,
            #"hint: "Duplicates the selected clips on the timeline.""#,
            #"title: "Delete Selected Clips""#,
            #"hint: "Deletes the selected clips from the timeline.""#,
            #"title: "Ripple Delete Selected Clip""#,
            #"hint: "Deletes the selected clip and closes the resulting gap.""#,
            #"accessibilityLabel(NSLocalizedString("Timeline marker controls", comment: ""))"#,
            #"title: "Previous Marker""#,
            #"hint: "Moves the playhead to the previous marker.""#,
            #"title: "Add Marker at Playhead""#,
            #"hint: "Adds a marker at the current playhead time.""#,
            #"title: "Next Marker""#,
            #"hint: "Moves the playhead to the next marker.""#,
            #"accessibilityLabel(NSLocalizedString("Timeline zoom controls", comment: ""))"#,
            #"title: "Zoom Timeline Out""#,
            #"hint: "Zooms the timeline out.""#,
            #"title: "Zoom Timeline In""#,
            #"hint: "Zooms the timeline in.""#,
            #"title: "Fit Timeline""#,
            #"hint: "Fits the visible timeline duration in the available timeline width.""#,
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
}
