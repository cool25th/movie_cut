import SwiftUI
import MovieCutCore

struct ContentView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var isCanvasSettingsPresented = false
    @State private var isTemplatePickerPresented = false

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                MediaLibraryPanel(viewModel: viewModel)
                    .frame(minWidth: 200, maxWidth: 300)

                PreviewPanel(viewModel: viewModel)
                    .frame(minWidth: 400)

                InspectorPanel(viewModel: viewModel)
                    .frame(minWidth: 240, maxWidth: 320)
            }

            Divider()

            QuickToolsPanel(viewModel: viewModel)

            Divider()

            statusBar

            Divider()

            TimelineView(viewModel: viewModel)
        }
        .frame(minWidth: 1024, minHeight: 640)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { Task { await viewModel.undo() } }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .keyboardShortcut("z", modifiers: .command)

                Button(action: { Task { await viewModel.redo() } }) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Divider()

                Button(action: { Task { await viewModel.splitClip() } }) {
                    Label("Split", systemImage: "scissors")
                }
                .keyboardShortcut("b", modifiers: .command)

                Button(action: { viewModel.addMarkerAtPlayhead() }) {
                    Label("Add Marker", systemImage: "flag.fill")
                }
                .keyboardShortcut("m", modifiers: .command)

                Button(action: { Task { await viewModel.deleteClip() } }) {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

                Picker("Canvas", selection: $viewModel.canvasSelection) {
                    ForEach(toolbarCanvasPresets, id: \.self) { aspectRatio in
                        Text(aspectRatio.displayName).tag(aspectRatio)
                    }
                }
                .onChange(of: viewModel.canvasSelection) { _, newValue in
                    guard viewModel.currentProject.canvas.aspectRatio != newValue else { return }
                    Task {
                        await viewModel.updateCanvas(CanvasPreset(aspectRatio: newValue))
                    }
                }

                Button(action: { isCanvasSettingsPresented.toggle() }) {
                    Label("Canvas", systemImage: "rectangle.dashed")
                }
                .popover(isPresented: $isCanvasSettingsPresented) {
                    CanvasSettingsView(canvas: viewModel.currentProject.canvas) { canvas in
                        Task { await viewModel.updateCanvas(canvas) }
                    }
                }

                Button(action: { isTemplatePickerPresented.toggle() }) {
                    Label("Templates", systemImage: "rectangle.stack.badge.plus")
                }

                Divider()

                Button(action: { Task { await viewModel.syncToCloud() } }) {
                    if viewModel.isCloudSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "cloud.and.arrow.up")
                    }
                }
                .help("Sync to Cloud")

                Divider()

                Button(action: { Task { await viewModel.exportProject() } }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: .command)

                if let exportURL = viewModel.lastExportURL {
                    ShareLink(item: exportURL) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .background(shortcutButtons)
        .sheet(isPresented: Binding(
            get: { viewModel.exportEngine.isExporting },
            set: { _ in }
        )) {
            ExportSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isTemplatePickerPresented) {
            TemplatePickerView(viewModel: viewModel)
        }
    }

    private var toolbarCanvasPresets: [AspectRatio] {
        [
            .landscape16x9,
            .portrait9x16,
            .portrait4x5,
            .square1x1,
            .wide21x9,
            .ultrawide21x9
        ]
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(canvasSizeText, systemImage: "rectangle")
            Text(viewModel.currentProject.canvas.frameRate.statusDisplayName)
            Spacer()
            if let error = viewModel.lastErrorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if let message = viewModel.lastStatusMessage {
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var canvasSizeText: String {
        let size = viewModel.currentProject.canvas.size
        return "\(Int(size.width)) x \(Int(size.height))"
    }

    private var shortcutButtons: some View {
        Group {
            Button("Play/Pause") {
                viewModel.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: .command)

            Button("Save Project") {
                Task { await viewModel.saveProject() }
            }
            .keyboardShortcut("s", modifiers: .command)

            Button("Delete Selected Clip") {
                Task { await viewModel.deleteClip() }
            }
            .keyboardShortcut(.delete, modifiers: [])

            Button("Forward Delete Selected Clip") {
                Task { await viewModel.deleteClip() }
            }
            .keyboardShortcut(.deleteForward, modifiers: [])

            Button("Seek Back One Frame") {
                viewModel.seekByFrames(-1)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("Seek Forward One Frame") {
                viewModel.seekByFrames(1)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

private struct QuickToolsPanel: View {
    var viewModel: EditorViewModel

    @State private var runningTool: QuickTool?
    @State private var isStickerBrowserPresented = false

    private var textTemplates: [MovieCutCore.TextTemplate] {
        MovieCutCore.TextTemplate.builtIn
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Quick Tools")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 20)

                textTemplateMenu
                stickerBrowserButton
                markerControls

                Divider()
                    .frame(height: 20)

                quickButton(
                    .autoCut,
                    title: "Auto Cut",
                    systemImage: "speaker.slash",
                    isEnabled: viewModel.canRunAutoCutOnSelection
                ) {
                    await viewModel.runAutoCutOnSelection()
                }

                quickButton(
                    .sceneDetect,
                    title: "Detect Scenes",
                    systemImage: "film.stack",
                    isEnabled: viewModel.canDetectSceneChangesForSelection
                ) {
                    await viewModel.detectSceneChangesForSelection()
                }

                quickButton(
                    .reframe,
                    title: "Auto Reframe",
                    systemImage: "viewfinder",
                    isEnabled: viewModel.canAutoReframeSelection
                ) {
                    await viewModel.autoReframeSelection()
                }

                quickButton(
                    .noiseReduction,
                    title: "Noise Reduce",
                    systemImage: "waveform.badge.minus",
                    isEnabled: viewModel.canApplyNoiseReductionToSelection
                ) {
                    await viewModel.applyNoiseReductionToSelection()
                }

                quickButton(
                    .extractAudio,
                    title: "Extract Audio",
                    systemImage: "waveform",
                    isEnabled: viewModel.canExtractAudioFromSelection
                ) {
                    await viewModel.extractAudioFromSelection()
                }

                feedbackView
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var textTemplateMenu: some View {
        Menu {
            Section("Titles") {
                templateButtons(named: ["Title", "Subtitle"])
            }
            Section("Social") {
                templateButtons(named: ["Caption", "Lower Third"])
            }
            Section("End Card") {
                templateButtons(named: ["Credits"])
            }
        } label: {
            Label("Text", systemImage: "textformat")
        }
        .disabled(runningTool != nil)
        .help("Add Text from Template")
    }

    @ViewBuilder
    private func templateButtons(named names: [String]) -> some View {
        ForEach(textTemplates.filter { names.contains($0.name) }) { template in
            Button(template.name) {
                run(.textTemplate) {
                    await viewModel.addTextTemplateClip(template)
                }
            }
        }
    }

    private var stickerBrowserButton: some View {
        Button {
            isStickerBrowserPresented.toggle()
        } label: {
            Label("Sticker", systemImage: "face.smiling")
        }
        .disabled(runningTool != nil)
        .help("Open Sticker Browser")
        .popover(isPresented: $isStickerBrowserPresented) {
            StickerPickerView { sticker in
                isStickerBrowserPresented = false
                run(.sticker) {
                    await viewModel.addStickerClip(sticker)
                }
            }
            .frame(width: 280, height: 360)
        }
    }

    private var markerControls: some View {
        HStack(spacing: 2) {
            Button {
                viewModel.goToPreviousMarker()
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.borderless)
            .disabled(runningTool != nil || viewModel.previousMarker == nil)
            .help("Previous Marker")

            markerButton

            Button {
                viewModel.goToNextMarker()
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.borderless)
            .disabled(runningTool != nil || viewModel.nextMarker == nil)
            .help("Next Marker")
        }
    }

    private var markerButton: some View {
        Button {
            viewModel.addMarkerAtPlayhead()
        } label: {
            Label("Marker (\(viewModel.currentProject.markers.count))", systemImage: "flag.fill")
        }
        .disabled(runningTool != nil)
        .help("Add Marker at Playhead")
    }

    private var feedbackView: some View {
        Group {
            if let message = viewModel.quickToolProgressMessage {
                feedbackLabel(message, systemImage: "hourglass", color: .secondary)
            } else if let message = viewModel.lastStatusMessage {
                feedbackLabel(message, systemImage: "checkmark.circle", color: .secondary)
            } else if let message = viewModel.lastErrorMessage {
                feedbackLabel(message, systemImage: "exclamationmark.triangle", color: .red)
            }
        }
    }

    private func feedbackLabel(_ message: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Divider()
                .frame(height: 20)
            Label(message, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }

    private func quickButton(
        _ tool: QuickTool,
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            run(tool, action: action)
        } label: {
            HStack(spacing: 5) {
                if runningTool == tool {
                    ProgressView()
                        .controlSize(.small)
                }
                Label(title, systemImage: systemImage)
            }
        }
        .disabled(!isEnabled || (runningTool != nil && runningTool != tool))
        .help(title)
    }

    private func run(_ tool: QuickTool, action: @escaping @MainActor () async -> Void) {
        guard runningTool == nil else { return }
        runningTool = tool
        viewModel.quickToolProgressMessage = tool.progressMessage
        Task { @MainActor in
            await action()
            if viewModel.quickToolProgressMessage == tool.progressMessage {
                viewModel.quickToolProgressMessage = nil
            }
            runningTool = nil
        }
    }

}

private enum QuickTool: Equatable {
    case textTemplate
    case sticker
    case autoCut
    case sceneDetect
    case reframe
    case noiseReduction
    case extractAudio

    var progressMessage: String {
        switch self {
        case .textTemplate:
            return "Adding text template..."
        case .sticker:
            return "Adding sticker..."
        case .autoCut:
            return "Analyzing silence..."
        case .sceneDetect:
            return "Detecting scene changes..."
        case .reframe:
            return "Tracking crop frames..."
        case .noiseReduction:
            return "Rendering denoised audio..."
        case .extractAudio:
            return "Extracting audio..."
        }
    }
}

struct ExportSheet: View {
    var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exporting")
                .font(.headline)
            ProgressView(value: viewModel.exportEngine.exportProgress)
                .frame(width: 280)
            Text(String(format: "%.0f%%", viewModel.exportEngine.exportProgress * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let exportError = viewModel.exportEngine.exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button("Cancel") {
                viewModel.cancelExport()
            }
        }
        .padding(16)
    }
}

private extension ExportFrameRate {
    var statusDisplayName: String {
        switch self {
        case .fps24:
            return "24 fps"
        case .fps30:
            return "30 fps"
        case .fps60:
            return "60 fps"
        }
    }
}
