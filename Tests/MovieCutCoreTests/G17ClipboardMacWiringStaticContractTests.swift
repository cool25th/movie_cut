import Foundation
import Testing

@Suite("G-17 Clipboard Mac Wiring Static Contract")
struct G17ClipboardMacWiringStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("ViewModel uses one atomic cut and paste command dispatch path")
    func viewModelUsesAtomicClipboardCommands() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")

        #expect(source.components(separatedBy: "session.dispatch(CutClipsCommand(").count - 1 == 1)
        #expect(source.components(separatedBy: "session.dispatch(PasteClipsCommand(").count - 1 == 1)
        #expect(source.contains("ClipboardPayload(project: currentProject, clipIds: clipIds)"))
        #expect(source.contains("selectedClipIds = currentClipIds.subtracting(clipIdsBeforePaste)"))
    }

    @Test("Edit menu owns Cmd+C/X/V and forwards native text pasteboard actions")
    func editMenuPreservesNativeTextEditing() throws {
        let source = try source("App/MovieCutMac/MovieCutMacApp.swift")

        #expect(source.contains("CommandGroup(replacing: .pasteboard)"))
        #expect(source.contains("Button(\"Copy Clips\")"))
        #expect(source.contains(".keyboardShortcut(\"c\", modifiers: .command)"))
        #expect(source.contains("Button(\"Cut Clips\")"))
        #expect(source.contains(".keyboardShortcut(\"x\", modifiers: .command)"))
        #expect(source.contains("Button(\"Paste Clips\")"))
        #expect(source.contains(".keyboardShortcut(\"v\", modifiers: .command)"))
        #expect(source.contains("NSApp.sendAction(nativeAction, to: nil, from: nil)"))
        #expect(source.contains("#selector(NSText.copy(_:))"))
        #expect(source.contains("#selector(NSText.cut(_:))"))
        #expect(source.contains("#selector(NSText.paste(_:))"))
    }

    @Test("Timeline context menu routes copy cut and paste through ViewModel")
    func timelineContextMenuRoutesClipboardActions() throws {
        let source = try source("App/MovieCutMac/TimelineView.swift")

        #expect(source.contains("Button(NSLocalizedString(\"Copy\", comment: \"\"))"))
        #expect(source.contains("viewModel.copyClips(clipIds)"))
        #expect(source.contains("Button(NSLocalizedString(\"Cut\", comment: \"\"))"))
        #expect(source.contains("viewModel.cutClips(clipIds)"))
        #expect(source.contains("Button(NSLocalizedString(\"Paste\", comment: \"\"))"))
        #expect(source.contains("viewModel.pasteClipsAtPlayhead()"))
        #expect(source.contains("contextMenuClipIds(anchor: clip.id)"))
    }
}
