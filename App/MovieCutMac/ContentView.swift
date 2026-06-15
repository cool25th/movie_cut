import SwiftUI
import MovieCutCore

struct ContentView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var isCanvasSettingsPresented = false
    @State private var isTemplatePickerPresented = false

    var body: some View {
        VSplitView {
            VStack(spacing: 0) {
                HSplitView {
                    MediaLibraryPanel(viewModel: viewModel)
                        .frame(minWidth: 320, idealWidth: 340, maxWidth: 380)

                    PreviewPanel(viewModel: viewModel)
                        .frame(minWidth: 400)

                    InspectorPanel(viewModel: viewModel)
                        .frame(minWidth: 240, maxWidth: 320)
                }

                Divider()
                    .overlay(MovieCutTheme.divider)

                statusBar
            }
            .frame(minHeight: 220, maxHeight: .infinity)
            .layoutPriority(1)

            TimelineView(viewModel: viewModel)
                .frame(minHeight: 210, idealHeight: 260, maxHeight: .infinity)
        }
        .frame(minWidth: 1024, minHeight: 720)
        .toolbar {
            ToolbarItem(placement: .principal) {
                projectStatusToolbarItem
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { Task { await viewModel.undo() } }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }

                Button(action: { Task { await viewModel.redo() } }) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }

                Divider()

                Button(action: { Task { await viewModel.splitClip() } }) {
                    Label("Split", systemImage: "scissors")
                }

                Button(action: { viewModel.addMarkerAtPlayhead() }) {
                    Label("Add Marker", systemImage: "flag.fill")
                }

                Button(action: { Task { await viewModel.deleteClip() } }) {
                    Label("Delete", systemImage: "trash")
                }

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
                    CanvasSettingsView(
                        canvas: viewModel.currentProject.canvas,
                        background: viewModel.currentProject.canvasBackground,
                        onBackgroundChange: { background in
                            Task { await viewModel.updateCanvasBackground(background) }
                        }
                    ) { canvas in
                        Task { await viewModel.updateCanvas(canvas) }
                    }
                }

                Button(action: { isTemplatePickerPresented.toggle() }) {
                    Label("Templates", systemImage: "rectangle.stack.badge.plus")
                }

                Menu {
                    Button("Export Package…") {
                        Task { await viewModel.exportProjectPackage() }
                    }
                    Button("Import Package…") {
                        Task { await viewModel.importProjectPackage() }
                    }
                } label: {
                    Label("Package", systemImage: "shippingbox")
                }
                .help("Export or import a self-contained .mctemplate project package")

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

                exportToolbarControl
            }
        }
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

    private var projectStatusToolbarItem: some View {
        HStack(spacing: MovieCutSpacing.small) {
            Text(viewModel.projectDisplayName)
                .font(.headline.weight(.semibold))
                .lineLimit(1)

            Label {
                Text(viewModel.projectSaveStatusLabel)
            } icon: {
                Image(systemName: viewModel.projectSaveStatusSystemImage)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Project save status", comment: ""))
        .accessibilityValue("\(viewModel.projectDisplayName), \(viewModel.projectSaveStatusLabel)")
        .accessibilityHint(NSLocalizedString("Shows the current project name and save or autosave status.", comment: ""))
    }

    private var exportToolbarControl: some View {
        ControlGroup {
            Button(action: { Task { await viewModel.exportProject() } }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help(exportButtonHelpText)
            .accessibilityLabel("Export project")
            .accessibilityValue(exportButtonAccessibilityValue)
            .accessibilityHint(exportButtonHelpText)

            Menu {
                Button("Video (Explicit Bitrate)…") {
                    Task { await viewModel.exportWithExplicitBitrate() }
                }
                Button("ProRes Master…") {
                    Task { await viewModel.exportProResMaster() }
                }
                Divider()
                Button("Audio Only (M4A)…") {
                    Task { await viewModel.exportAudioOnly() }
                }
                Button("Animated GIF…") {
                    Task { await viewModel.exportAnimatedGIF() }
                }
                Button("Still Frame (PNG)…") {
                    Task { await viewModel.exportStillFrame() }
                }

                if let exportURL = viewModel.lastExportURL {
                    Divider()
                    ShareLink(item: exportURL) {
                        Label("Share latest export", systemImage: "square.and.arrow.up")
                    }
                    .help("Share the most recent export file")
                    .accessibilityLabel("Share latest export")
                    .accessibilityValue(exportURL.lastPathComponent)
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .help("Choose an export format or share the latest export.")
            .accessibilityLabel("Export formats")
            .accessibilityHint("Choose explicit-bitrate video, ProRes, audio-only, animated GIF, still frame, or share the latest export.")
        }
        .disabled(viewModel.exportEngine.isExporting)
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

    private var exportButtonHelpText: String {
        if viewModel.exportEngine.isExporting {
            return "Export is already running. Review progress in the export sheet or cancel it before starting another export."
        }

        return "Export the current project using the selected container, codec, quality, and resolution settings."
    }

    private var exportButtonAccessibilityValue: String {
        let settings = viewModel.currentProject.exportSettings
        let quality = settings.quality == .custom
            ? "Custom \(settings.resolvedVideoBitrateMbps ?? 0) Mbps"
            : settings.quality.displayName

        return "\(settings.containerFormat.displayName), \(settings.codec.accessibilityDisplayName), \(settings.resolution.accessibilityDisplayName), \(settings.frameRate.statusDisplayName), \(quality) quality"
    }

    private var statusBar: some View {
        HStack(spacing: MovieCutSpacing.medium) {
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
        .padding(.horizontal, MovieCutSpacing.medium)
        .padding(.vertical, MovieCutSpacing.xSmall)
        .background(MovieCutTheme.panelBackground)
    }

    private var canvasSizeText: String {
        let size = viewModel.currentProject.canvas.size
        return "\(Int(size.width)) x \(Int(size.height))"
    }
}

struct QuickToolsPanel: View {
    var viewModel: EditorViewModel

    @State private var runningTool: QuickTool?
    @State private var isStickerBrowserPresented = false

    private var textTemplates: [MovieCutCore.TextTemplate] {
        MovieCutCore.TextTemplate.builtIn
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MovieCutSpacing.small) {
                Text("Quick Tools")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Divider()
                    .frame(height: 20)
                    .overlay(MovieCutTheme.divider)

                textTemplateMenu
                stickerBrowserButton
                markerControls

                Divider()
                    .frame(height: 20)
                    .overlay(MovieCutTheme.divider)

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
                    .beatDetect,
                    title: "Detect Beats",
                    systemImage: "metronome",
                    isEnabled: viewModel.canDetectBeats
                ) {
                    await viewModel.detectBeats()
                }

                if viewModel.hasBeatMarkers {
                    quickButton(
                        .beatClear,
                        title: "Clear Beats",
                        systemImage: "metronome.fill",
                        isEnabled: true
                    ) {
                        await viewModel.clearBeatMarkers()
                    }
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
            .padding(.horizontal, MovieCutSpacing.small)
            .padding(.vertical, MovieCutSpacing.xSmall)
        }
        .background(Color.clear)
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
        HStack(spacing: MovieCutSpacing.xSmall) {
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
        HStack(spacing: MovieCutSpacing.small) {
            Divider()
                .frame(height: 20)
                .overlay(MovieCutTheme.divider)
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
            HStack(spacing: MovieCutSpacing.xSmall) {
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
    case beatDetect
    case beatClear
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
        case .beatDetect:
            return "Detecting beats..."
        case .beatClear:
            return "Removing beat markers..."
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
        VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
            Text("Exporting")
                .font(.headline)
            ProgressView(value: viewModel.exportEngine.exportProgress)
                .frame(width: 280)
                .accessibilityLabel("Export progress")
                .accessibilityValue(exportProgressAccessibilityValue)
                .accessibilityHint("Shows the current export percentage. This progress alone is not an export golden or playback verification.")
            Text(String(format: "%.0f%%", viewModel.exportEngine.exportProgress * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let exportError = viewModel.exportEngine.exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Export error")
            }
            Button("Cancel") {
                viewModel.cancelExport()
            }
            .help("Cancel the current export")
            .accessibilityHint("Stops the running export. It does not delete previously exported files.")
        }
        .padding(MovieCutSpacing.large)
    }

    private var exportProgressAccessibilityValue: String {
        String(format: "%.0f percent", viewModel.exportEngine.exportProgress * 100)
    }
}

private extension ExportResolution {
    var accessibilityDisplayName: String {
        switch self {
        case .p720:
            return "720p"
        case .p1080:
            return "1080p"
        case .p4K:
            return "4K"
        }
    }
}

private extension ExportCodec {
    var accessibilityDisplayName: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        }
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
