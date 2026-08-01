import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

@main
struct MovieCutMacApp: App {
    @State private var viewModel = EditorViewModel()
    @State private var didLoadBootstrapProject = false
    /// The editor ↔ home router (requirement 3 / design §4.2). Owns the current
    /// `AppStage`; the `WindowGroup` branches on `router.stage`. Under the
    /// harness gate (`MOVIECUT_UITEST` / `MOVIECUT_BOOTSTRAP_PROJECT`) the router
    /// starts in `.editor`, so existing E2E / parity / bootstrap paths are
    /// unchanged (requirement 3.6).
    @State private var router: AppStageRouter?
    /// File-backed recent-projects list (requirement 3.3). Shared by `HomeView`
    /// and by the save-time recording in
    /// `EditorViewModel.recordCurrentProjectToRecent`.
    private let recentProjectsStore = RecentProjectsStore()
    @NSApplicationDelegateAdaptor(MovieCutAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            // Branch on the router's stage. The router is created lazily on
            // first appear so its `@Observable` identity is stable for the
            // window's lifetime. Until it exists (first frame only) show a
            // neutral background — the `.task` below flips it to home/editor.
            Group {
                if let router {
                    switch router.stage {
                    case .home:
                        HomeView(
                            router: router,
                            viewModel: viewModel,
                            store: recentProjectsStore
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home.surface")
                    case .editor:
                        ContentView(viewModel: viewModel)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("editor.surface")
                    }
                } else {
                    MovieCutTheme.editorBackground.ignoresSafeArea()
                }
            }
            .task {
                appDelegate.viewModel = viewModel
                // Create the router once so its stage decision (home vs editor,
                // gate-aware) is made from the live process env. Subsequent launches
                // of the same window reuse the existing router.
                if router == nil {
                    router = AppStageRouter(viewModel: viewModel, store: recentProjectsStore)
                }
                await loadBootstrapProjectIfNeeded()
            }
        }
        .defaultSize(width: defaultWindowSize.width, height: defaultWindowSize.height)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    Task { await viewModel.newProject() }
                }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [UTType(filenameExtension: "moviecut") ?? .json, .json]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url {
                        Task { await viewModel.openProject(from: url) }
                    }
                }
                    .keyboardShortcut("o", modifiers: .command)
                // Return to the home/recent-projects screen from the editor
                // (requirement 3.7). Routes through AppStageRouter so the dirty
                // Save/Don't Save/Cancel guard runs with the same policy as
                // applicationShouldTerminate (design §4.2). Disabled when already
                // home or when the harness gate is active (home is unreachable
                // under the gate, so the command is a no-op there).
                Button("Go to Home") {
                    Task { await router?.requestReturnToHome() }
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(router?.stage != .editor)
                Button("Save...") {
                    Task { await viewModel.saveProject() }
                }
                    .keyboardShortcut("s", modifiers: .command)
                Divider()
                Button("Import Media...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [.movie, .video, .audio, .image]
                    if panel.runModal() == .OK {
                        let urls = panel.urls
                        Task { await viewModel.importMedia(urls) }
                    }
                }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Export...") {
                    Task { await viewModel.exportProject() }
                }
                .keyboardShortcut("e", modifiers: .command)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    Task { await viewModel.undo() }
                }
                .keyboardShortcut("z", modifiers: .command)

                Button("Redo") {
                    Task { await viewModel.redo() }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Copy Clips") {
                    MovieCutShortcutGuard.performPasteboardShortcut(
                        nativeAction: #selector(NSText.copy(_:))
                    ) {
                        viewModel.copySelectedClips()
                    }
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(!MovieCutShortcutGuard.isTextInputFirstResponder && !viewModel.canCopySelectedClips)

                Button("Cut Clips") {
                    MovieCutShortcutGuard.performPasteboardShortcut(
                        nativeAction: #selector(NSText.cut(_:))
                    ) {
                        Task { await viewModel.cutSelectedClips() }
                    }
                }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(!MovieCutShortcutGuard.isTextInputFirstResponder && !viewModel.canCutSelectedClips)

                Button("Paste Clips") {
                    MovieCutShortcutGuard.performPasteboardShortcut(
                        nativeAction: #selector(NSText.paste(_:))
                    ) {
                        Task { await viewModel.pasteClipsAtPlayhead() }
                    }
                }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(!MovieCutShortcutGuard.isTextInputFirstResponder && !viewModel.canPasteClips)
            }

            CommandMenu("Playback") {
                Button("Play/Pause") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.togglePlayPause()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Divider()

                Button("Step Back One Frame") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.seekByFrames(-1)
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Step Forward One Frame") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.seekByFrames(1)
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Seek Back 1 Second") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.seekBySeconds(-1)
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [.shift])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Seek Forward 1 Second") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.seekBySeconds(1)
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [.shift])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Divider()

                Button("Jump to Previous Clip Boundary") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.jumpToPreviousClipBoundary()
                    }
                }
                .keyboardShortcut(.upArrow, modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Jump to Next Clip Boundary") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.jumpToNextClipBoundary()
                    }
                }
                .keyboardShortcut(.downArrow, modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Divider()

                // J/K/L shuttle (S9). J = reverse back-step, K = stop, L =
                // forward; repeated L/J taps raise the speed step.
                Button("Shuttle Reverse (J)") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.shuttleReverse()
                    }
                }
                .keyboardShortcut("j", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Shuttle Stop (K)") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.shuttleStop()
                    }
                }
                .keyboardShortcut("k", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Shuttle Forward (L)") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.shuttleForward()
                    }
                }
                .keyboardShortcut("l", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)
            }

            CommandMenu("Timeline") {
                // Edit tool modes (S9). V = select, B = blade. Distinct from
                // Cmd+B (split at playhead): blade mode turns timeline clicks
                // into splits at the clicked point.
                Button("Select Tool") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.timelineTool = .select
                    }
                }
                .keyboardShortcut("v", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Blade Tool") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.timelineTool = .blade
                    }
                }
                .keyboardShortcut("b", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Divider()

                Button("Split at Playhead") {
                    Task { await viewModel.splitClip() }
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Trim Start to Playhead") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        Task { await viewModel.trimSelectedClipStartToPlayhead() }
                    }
                }
                .keyboardShortcut("q", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Trim End to Playhead") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        Task { await viewModel.trimSelectedClipEndToPlayhead() }
                    }
                }
                .keyboardShortcut("w", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Divider()

                Button("Delete Selected Clips") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        Task { await viewModel.deleteClip() }
                    }
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Ripple Delete Selected Clip") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        Task { await viewModel.rippleDeleteSelectedClip() }
                    }
                }
                .keyboardShortcut(.delete, modifiers: [.shift])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Duplicate Selected Clips") {
                    Task { await viewModel.duplicateSelectedClips() }
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Zoom In") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.zoomTimelineIn()
                    }
                }
                .keyboardShortcut("+", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Button("Zoom Out") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.zoomTimelineOut()
                    }
                }
                .keyboardShortcut("-", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)

                Divider()

                Button("Add Marker") {
                    MovieCutShortcutGuard.performTextEntrySensitiveShortcut {
                        viewModel.addMarkerAtPlayhead()
                    }
                }
                .keyboardShortcut("m", modifiers: [])
                .disabled(MovieCutShortcutGuard.isTextInputFirstResponder)
            }

            CommandGroup(after: .help) {
                Button("MovieCut Keyboard Shortcuts") {
                    MovieCutKeyboardShortcutHelp.show()
                }
            }
        }
    }

    private var bootstrapProjectPath: String? {
        guard let path = ProcessInfo.processInfo.environment["MOVIECUT_BOOTSTRAP_PROJECT"],
              !path.isEmpty else {
            return nil
        }
        return path
    }

    private var defaultWindowSize: CGSize {
        bootstrapProjectPath == nil ? CGSize(width: 1440, height: 900) : CGSize(width: 1811, height: 881)
    }

    @MainActor
    private func loadBootstrapProjectIfNeeded() async {
        guard !didLoadBootstrapProject else { return }
        guard let path = bootstrapProjectPath else {
            return
        }

        didLoadBootstrapProject = true
        await viewModel.openProject(from: URL(fileURLWithPath: path))

        if ProcessInfo.processInfo.environment["MOVIECUT_BOOTSTRAP_SELECT_TEXT"] == "1" {
            selectFirstTextClipForBootstrap()
        }

        applyBootstrapWindowFrame()
    }

    @MainActor
    private func applyBootstrapWindowFrame() {
        guard bootstrapProjectPath != nil else { return }

        DispatchQueue.main.async {
            let targetSize = CGSize(width: 1811, height: 881)
            let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(origin: NSPoint(x: 0, y: 0), size: targetSize)
            let targetFrame = NSRect(
                x: visibleFrame.minX,
                y: max(visibleFrame.minY, visibleFrame.maxY - targetSize.height),
                width: targetSize.width,
                height: targetSize.height
            )

            let window = NSApp.keyWindow
                ?? NSApp.mainWindow
                ?? NSApp.windows.first(where: { $0.isVisible })
            window?.setFrame(targetFrame, display: true)
        }
    }

    @MainActor
    private func selectFirstTextClipForBootstrap() {
        for track in viewModel.currentProject.timeline.tracks where track.kind == .text {
            guard let clip = track.clips.first else { continue }
            viewModel.selectedClipId = clip.id
            viewModel.playheadTime = clip.timelineRange.start
            return
        }
    }
}

@MainActor
private enum MovieCutShortcutGuard {
    /// Plain-letter, arrow, Space, Delete, and +/- menu shortcuts are centralized
    /// here so text fields keep first claim while the F-05 commands stay visible
    /// in the macOS menu bar. A full SwiftUI FocusState command router can refine
    /// this further if the app grows more independent text-editing surfaces.
    static var isTextInputFirstResponder: Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else {
            return false
        }

        if firstResponder is NSTextView || firstResponder is NSTextField {
            return true
        }

        if let view = firstResponder as? NSView {
            return view.enclosingTextInputView != nil
        }

        return false
    }

    static func performTextEntrySensitiveShortcut(_ action: () -> Void) {
        guard !isTextInputFirstResponder else { return }
        action()
    }

    static func performPasteboardShortcut(nativeAction: Selector, timelineAction: () -> Void) {
        if isTextInputFirstResponder {
            NSApp.sendAction(nativeAction, to: nil, from: nil)
        } else {
            timelineAction()
        }
    }
}

private extension NSView {
    var enclosingTextInputView: NSView? {
        if self is NSTextView || self is NSTextField {
            return self
        }

        return superview?.enclosingTextInputView
    }
}

@MainActor
private enum MovieCutKeyboardShortcutHelp {
    static let text = """
    Playback
    Space: Play/Pause
    Left/Right Arrow: Step one frame
    Shift+Left/Right Arrow: Seek one second
    Up/Down Arrow: Jump to previous/next clip boundary

    Timeline
    Cmd+B: Split at Playhead
    Q/W: Trim start/end to playhead
    Delete: Delete selected clips
    Shift+Delete: Ripple delete selected clip
    Cmd+D: Duplicate selected clips
    Cmd+C / Cmd+X / Cmd+V: Copy/Cut/Paste clips
    +/-: Zoom timeline
    M: Add marker
    Cmd+Z / Shift+Cmd+Z: Undo/Redo
    """

    static func show() {
        let alert = NSAlert()
        alert.messageText = "MovieCut Keyboard Shortcuts"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// Application delegate that guards termination against unsaved changes.
final class MovieCutAppDelegate: NSObject, NSApplicationDelegate {
    /// Set from the SwiftUI app so the delegate can reach the view model.
    weak var viewModel: EditorViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel, viewModel.isDirty else { return .terminateNow }

        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST"] != "1", env["MOVIECUT_BOOTSTRAP_PROJECT"] == nil else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Save changes to \"\(viewModel.currentProject.name)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Save asynchronously, then reply to the termination request with
            // the outcome so a failed save does not discard work. The VM is
            // captured strongly: the app is terminating, so outliving this Task
            // is intended, and a weak capture would risk deallocating it
            // mid-save (snapshot/projectStore torn down across the awaits).
            Task { @MainActor [viewModel] in
                let saved = await viewModel.terminateAfterSaving()
                sender.reply(toApplicationShouldTerminate: saved)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
