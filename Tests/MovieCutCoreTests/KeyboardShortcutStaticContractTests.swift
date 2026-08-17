import Foundation
import Testing

/// The macOS app target owns F-05 menu commands, while SwiftPM primarily builds
/// Core. These source-level checks keep the shortcut contract visible in the
/// faster package test loop.
@Suite("Keyboard Shortcut StaticContract")
struct KeyboardShortcutStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("macOS app menus register the F-05 playback and timeline shortcuts")
    func macAppMenusRegisterF05Shortcuts() throws {
        let source = try source("App/MovieCutMac/MovieCutMacApp.swift")

        #expect(source.contains("CommandGroup(replacing: .undoRedo)"))
        #expect(source.contains("CommandMenu(\"Playback\")"))
        #expect(source.contains("CommandMenu(\"Timeline\")"))

        #expect(source.contains("Button(\"Play/Pause\")"))
        #expect(source.contains(".keyboardShortcut(.space, modifiers: [])"))
        #expect(source.contains("Button(\"Split at Playhead\")"))
        #expect(source.contains(".keyboardShortcut(\"b\", modifiers: .command)"))
        #expect(source.contains("Button(\"Trim Start to Playhead\")"))
        #expect(source.contains(".keyboardShortcut(\"q\", modifiers: [])"))
        #expect(source.contains("Button(\"Trim End to Playhead\")"))
        #expect(source.contains(".keyboardShortcut(\"w\", modifiers: [])"))
        #expect(source.contains("Button(\"Delete Selected Clips\")"))
        #expect(source.contains(".keyboardShortcut(.delete, modifiers: [])"))
        #expect(source.contains("Button(\"Ripple Delete Selected Clip\")"))
        #expect(source.contains(".keyboardShortcut(.delete, modifiers: [.shift])"))
        #expect(source.contains("Button(\"Duplicate Selected Clips\")"))
        #expect(source.contains(".keyboardShortcut(\"d\", modifiers: .command)"))
        #expect(source.contains("Button(\"Step Back One Frame\")"))
        #expect(source.contains(".keyboardShortcut(.leftArrow, modifiers: [])"))
        #expect(source.contains("Button(\"Step Forward One Frame\")"))
        #expect(source.contains(".keyboardShortcut(.rightArrow, modifiers: [])"))
        #expect(source.contains("Button(\"Seek Back 1 Second\")"))
        #expect(source.contains(".keyboardShortcut(.leftArrow, modifiers: [.shift])"))
        #expect(source.contains("Button(\"Seek Forward 1 Second\")"))
        #expect(source.contains(".keyboardShortcut(.rightArrow, modifiers: [.shift])"))
        #expect(source.contains("Button(\"Jump to Previous Clip Boundary\")"))
        #expect(source.contains(".keyboardShortcut(.upArrow, modifiers: [])"))
        #expect(source.contains("Button(\"Jump to Next Clip Boundary\")"))
        #expect(source.contains(".keyboardShortcut(.downArrow, modifiers: [])"))
        #expect(source.contains("Button(\"Zoom In\")"))
        #expect(source.contains(".keyboardShortcut(\"+\", modifiers: [])"))
        #expect(source.contains("Button(\"Zoom Out\")"))
        #expect(source.contains(".keyboardShortcut(\"-\", modifiers: [])"))
        #expect(source.contains("Button(\"Add Marker\")"))
        #expect(source.contains(".keyboardShortcut(\"m\", modifiers: [])"))
        #expect(source.contains("Button(\"Undo\")"))
        #expect(source.contains(".keyboardShortcut(\"z\", modifiers: .command)"))
        #expect(source.contains("Button(\"Redo\")"))
        #expect(source.contains(".keyboardShortcut(\"z\", modifiers: [.command, .shift])"))
    }

    @Test("shortcut help lists the F-05 map")
    func shortcutHelpListsF05Map() throws {
        let source = try source("App/MovieCutMac/MovieCutMacApp.swift")

        #expect(source.contains("CommandGroup(after: .help)"))
        #expect(source.contains("Button(\"MovieCut Keyboard Shortcuts\")"))
        #expect(source.contains("Space: Play/Pause"))
        #expect(source.contains("Cmd+B: Split at Playhead"))
        #expect(source.contains("Q/W: Trim start/end to playhead"))
        #expect(source.contains("Shift+Delete: Ripple delete selected clip"))
        #expect(source.contains("Cmd+D: Duplicate selected clips"))
        #expect(source.contains("+/-: Zoom timeline"))
        #expect(source.contains("Cmd+Z / Shift+Cmd+Z: Undo/Redo"))
    }

    @Test("text-entry-sensitive shortcuts are centralized and guarded")
    func textEntrySensitiveShortcutsAreGuarded() throws {
        let source = try source("App/MovieCutMac/MovieCutMacApp.swift")
        let disabledCount = source
            .components(separatedBy: ".disabled(MovieCutShortcutGuard.isTextInputFirstResponder)")
            .count - 1

        #expect(source.contains("private enum MovieCutShortcutGuard"))
        #expect(source.contains("performTextEntrySensitiveShortcut"))
        #expect(source.contains("NSApp.keyWindow?.firstResponder"))
        #expect(source.contains("firstResponder is NSTextView || firstResponder is NSTextField"))
        #expect(disabledCount >= 12)
    }

    @Test("ContentView no longer owns F-05 duplicate shortcut registration")
    func contentViewNoLongerOwnsDuplicateShortcutRegistration() throws {
        let source = try source("App/MovieCutMac/ContentView.swift")

        #expect(!source.contains(".background(shortcutButtons)"))
        #expect(!source.contains("private var shortcutButtons"))
        #expect(!source.contains("keyboardShortcut(.space, modifiers: .command)"))
        #expect(!source.contains(".keyboardShortcut(\"b\", modifiers: .command)"))
        #expect(!source.contains(".keyboardShortcut(\"m\", modifiers: .command)"))
        #expect(!source.contains(".keyboardShortcut(.delete"))
    }

    @Test("EditorViewModel exposes command-backed F-05 actions")
    func editorViewModelExposesCommandBackedF05Actions() throws {
        // The timeline-editing boundary extraction (EXECUTION_PLAN Inc 2) moved
        // the selection/cursor slice into EditorViewModel+TimelineEditing.swift
        // and the transport slice (seek/zoom) into EditorViewModel+Transport.swift,
        // so the contract reads the view model across all boundary files.
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
            + source("App/MovieCutMac/EditorViewModel+TimelineEditing.swift")
            + source("App/MovieCutMac/EditorViewModel+Transport.swift")

        #expect(source.contains("func trimSelectedClipStartToPlayhead() async"))
        #expect(source.contains("func trimSelectedClipEndToPlayhead() async"))
        #expect(source.contains("TrimClipCommand("))
        #expect(source.contains("func rippleDeleteSelectedClip() async"))
        #expect(source.contains("RippleDeleteCommand(clipId: clipId)"))
        #expect(source.contains("func duplicateSelectedClips() async"))
        #expect(source.contains("DuplicateClipCommand(clipId: clipId)"))
        #expect(source.contains("func seekBySeconds(_ seconds: TimeInterval)"))
        #expect(source.contains("func jumpToPreviousClipBoundary()"))
        #expect(source.contains("func jumpToNextClipBoundary()"))
        #expect(source.contains("private func timelineNavigationPoints()"))
        #expect(source.contains("func zoomTimelineIn()"))
        #expect(source.contains("func zoomTimelineOut()"))
        #expect(source.contains("minimumTimelineZoom"))
        #expect(source.contains("maximumTimelineZoom"))
    }
}
