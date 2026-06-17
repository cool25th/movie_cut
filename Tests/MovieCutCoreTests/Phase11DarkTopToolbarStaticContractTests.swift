import Foundation
import Testing

/// Phase 1-1 keeps the macOS top toolbar visually aligned with the dark editor
/// shell without moving commands out of their existing presentation surface.
@Suite("Phase 1-1 Dark Top Toolbar StaticContract")
struct Phase11DarkTopToolbarStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase11DarkTopToolbarStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase11DarkTopToolbarStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("ContentView forces the native macOS window toolbar dark")
    func contentViewForcesNativeMacOSWindowToolbarDark() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")

        #expect(content.contains(".preferredColorScheme(.dark)"))
        #expect(content.contains(".tint(MovieCutTheme.accentCyan)"))
        #expect(content.contains(".toolbarBackground(MovieCutTheme.panelBackgroundRaised, for: .windowToolbar)"))
        #expect(content.contains(".toolbarBackground(.visible, for: .windowToolbar)"))
    }

    @Test("Dark toolbar keeps required action wiring")
    func darkToolbarKeepsRequiredActionWiring() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let toolbar = try section(
            in: content,
            from: ".toolbar {",
            to: "        .toolbarBackground(MovieCutTheme.panelBackgroundRaised, for: .windowToolbar)"
        )

        for marker in [
            "ToolbarItem(placement: .principal)",
            "projectStatusToolbarItem",
            "ToolbarItemGroup(placement: .primaryAction)",
            "await viewModel.undo()",
            "await viewModel.redo()",
            "await viewModel.splitClip()",
            "viewModel.addMarkerAtPlayhead()",
            "await viewModel.deleteClip()",
            #"Picker("Canvas", selection: $viewModel.canvasSelection)"#,
            "toolbarCanvasResolutionBadge",
            "CanvasSettingsView(",
            "isTemplatePickerPresented.toggle()",
            "TemplatePickerView(viewModel: viewModel)",
            #"Button("Export Package…")"#,
            #"Button("Import Package…")"#,
            "await viewModel.syncToCloud()",
            "exportToolbarControl"
        ] {
            #expect(toolbar.contains(marker) || content.contains(marker))
        }
    }

    @Test("Dark toolbar keeps VoiceOver labels and hints")
    func darkToolbarKeepsVoiceOverLabelsAndHints() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")

        for marker in [
            #"accessibilityLabel(NSLocalizedString("Project save status", comment: ""))"#,
            #"accessibilityValue("\(viewModel.projectDisplayName), \(viewModel.projectSaveStatusLabel)")"#,
            #"accessibilityHint(NSLocalizedString("Shows the current project name and save or autosave status.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Canvas and export resolution", comment: ""))"#,
            "accessibilityValue(viewModel.canvasResolutionBadgeText)",
            #"accessibilityHint(NSLocalizedString("Shows the current canvas aspect ratio and computed export render size.", comment: ""))"#,
            #".accessibilityLabel("Export project")"#,
            ".accessibilityValue(exportButtonAccessibilityValue)",
            ".accessibilityHint(exportButtonHelpText)",
            #".accessibilityLabel("Export formats")"#,
            #".accessibilityHint("Choose explicit-bitrate video, ProRes, audio-only, animated GIF, still frame, or share the latest export.")"#
        ] {
            #expect(content.contains(marker))
        }
    }

    @Test("Phase 1-1 does not alter app command shortcuts")
    func phase11DoesNotAlterAppCommandShortcuts() throws {
        let app = try source("App/MovieCutMac/MovieCutMacApp.swift")

        for marker in [
            "CommandGroup(replacing: .undoRedo)",
            #"Button("Undo")"#,
            #".keyboardShortcut("z", modifiers: .command)"#,
            #"Button("Redo")"#,
            #".keyboardShortcut("z", modifiers: [.command, .shift])"#,
            #"Button("Split at Playhead")"#,
            #".keyboardShortcut("b", modifiers: .command)"#,
            #"Button("Delete Selected Clips")"#,
            #".keyboardShortcut(.delete, modifiers: [])"#,
            #"Button("Add Marker")"#,
            #".keyboardShortcut("m", modifiers: [])"#,
            #"Button("Export...")"#,
            #".keyboardShortcut("e", modifiers: .command)"#
        ] {
            #expect(app.contains(marker))
        }
    }
}

private enum Phase11DarkTopToolbarStaticContractError: Error {
    case missingMarker(String)
}
