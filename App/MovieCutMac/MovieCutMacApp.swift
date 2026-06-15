import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

@main
struct MovieCutMacApp: App {
    @State private var viewModel = EditorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    viewModel.newProject()
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
            }

            CommandMenu("Timeline") {
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
