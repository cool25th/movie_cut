import AppKit
import SwiftUI
import MovieCutCore

struct ContentView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var isCanvasSettingsPresented = false
    @State private var isExportPresetsPresented = false
    @State private var isTemplatePickerPresented = false

    var body: some View {
        Group {
            if viewModel.isCardEditorMode {
                CardEditorView(viewModel: viewModel)
            } else {
                timelineEditorSurface
            }
        }
        .frame(minWidth: 1024, minHeight: 720)
        .background(MovieCutTheme.editorBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(MovieCutTheme.accentCyan)
        .task {
            #if DEBUG
            await viewModel.runUITestHarnessIfRequested()
            #endif
            await presentRecoveryIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            Task { await viewModel.clearRecoveryAutosave() }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                projectStatusToolbarItem
            }

            // IA/menu-position contract: the top toolbar owns project, view,
            // sync, and export chrome. Clip editing actions are timeline-local.
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { Task { await viewModel.undo() } }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .topChromeSecondaryToolbarStyle()
                .help("Undo")
                .accessibilityLabel("Undo")
                .accessibilityHint("Undo the last edit.")

                Button(action: { Task { await viewModel.redo() } }) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .topChromeSecondaryToolbarStyle()
                .help("Redo")
                .accessibilityLabel("Redo")
                .accessibilityHint("Redo the last undone edit.")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if !viewModel.isCardEditorMode {
                    // P2 top chrome polish contract: compact secondary canvas/project
                    // helpers stay quiet so Export remains the primary toolbar action.
                    topChromeCompactCluster(accessibilityLabel: "Canvas view controls") {
                        Picker("Canvas", selection: $viewModel.canvasSelection) {
                            ForEach(toolbarCanvasPresets, id: \.self) { aspectRatio in
                                Text(aspectRatio.displayName).tag(aspectRatio)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                        .help("Choose the canvas aspect ratio")
                        .accessibilityLabel("Canvas")
                        .accessibilityHint("Choose the current canvas aspect ratio.")
                        .onChange(of: viewModel.canvasSelection) { _, newValue in
                            guard viewModel.currentProject.canvas.aspectRatio != newValue else { return }
                            Task {
                                await viewModel.updateCanvas(CanvasPreset(aspectRatio: newValue))
                            }
                        }

                        toolbarCanvasResolutionBadge

                        Button(action: { isCanvasSettingsPresented.toggle() }) {
                            Label("Canvas", systemImage: "rectangle.dashed")
                        }
                        .topChromeSecondaryToolbarStyle()
                        .help("Canvas settings")
                        .accessibilityLabel("Canvas")
                        .accessibilityHint("Open canvas settings for aspect ratio, frame rate, and background.")
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
                    }

                    topChromeCompactCluster(accessibilityLabel: "Project helper controls") {
                        Button(action: { isTemplatePickerPresented.toggle() }) {
                            Label("Templates", systemImage: "rectangle.stack.badge.plus")
                        }
                        .topChromeSecondaryToolbarStyle()
                        .help("Templates")
                        .accessibilityLabel("Templates")
                        .accessibilityHint("Open template picker.")

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
                        .topChromeSecondaryToolbarStyle()
                        .help("Export or import a self-contained .mctemplate project package")
                        .accessibilityLabel("Package")
                        .accessibilityHint("Export or import a self-contained .mctemplate project package.")

                        Button(action: { Task { await viewModel.syncToCloud() } }) {
                            if viewModel.isCloudSyncing {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 14, height: 14)
                            } else {
                                Label("Sync to Cloud", systemImage: "cloud.and.arrow.up")
                            }
                        }
                        .topChromeSecondaryToolbarStyle()
                        .help("Sync to Cloud")
                        .accessibilityLabel("Sync to Cloud")
                        .accessibilityHint("Sync the current project to Cloud.")
                    }

                    exportToolbarControl
                }
            }
        }
        .toolbarBackground(MovieCutTheme.panelBackgroundRaised, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
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

    private var timelineEditorSurface: some View {
        VSplitView {
            VStack(spacing: 0) {
                HSplitView {
                    MediaLibraryPanel(viewModel: viewModel)
                        .frame(minWidth: 360, idealWidth: 380, maxWidth: 430)

                    PreviewPanel(viewModel: viewModel)
                        .frame(minWidth: 400)

                    InspectorPanel(viewModel: viewModel)
                        .frame(minWidth: 240, maxWidth: 320)
                }
                .background(MovieCutTheme.editorBackground)

                Divider()
                    .overlay(MovieCutTheme.divider)

                statusBar
            }
            .frame(minHeight: 220, maxHeight: .infinity)
            .layoutPriority(1)

            TimelineView(viewModel: viewModel)
                .frame(minHeight: 210, idealHeight: 260, maxHeight: .infinity)
        }
    }

    private var projectStatusToolbarItem: some View {
        HStack(spacing: MovieCutSpacing.xSmall) {
            Text(viewModel.projectDisplayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Label {
                Text(viewModel.projectSaveStatusLabel)
            } icon: {
                Image(systemName: viewModel.projectSaveStatusSystemImage)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(MovieCutTheme.mutedText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Project save status", comment: ""))
        .accessibilityValue("\(viewModel.projectDisplayName), \(viewModel.projectSaveStatusLabel)")
        .accessibilityHint(NSLocalizedString("Shows the current project name and save or autosave status.", comment: ""))
    }

    private var toolbarCanvasResolutionBadge: some View {
        Label {
            Text(viewModel.canvasResolutionBadgeText)
                .lineLimit(1)
                .monospacedDigit()
        } icon: {
            Image(systemName: "rectangle.ratio")
                .accessibilityHidden(true)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(MovieCutTheme.mutedText)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(MovieCutTheme.controlSurface.opacity(0.32))
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Canvas and export resolution", comment: ""))
        .accessibilityValue(viewModel.canvasResolutionBadgeText)
        .accessibilityHint(NSLocalizedString("Shows the current canvas aspect ratio and computed export render size.", comment: ""))
    }

    private var exportToolbarControl: some View {
        ControlGroup {
            Button(action: { Task { await viewModel.exportProject() } }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(MovieCutTheme.accentCyan)
            .help(exportButtonHelpText)
            .accessibilityLabel("Export project")
            .accessibilityValue(exportButtonAccessibilityValue)
            .accessibilityHint(exportButtonHelpText)

            Button(action: { isExportPresetsPresented.toggle() }) {
                Image(systemName: "square.grid.2x2")
            }
            .help("Platform export presets")
            .accessibilityLabel("Platform export presets")
            .accessibilityValue(platformPresetToolbarAccessibilityValue)
            .accessibilityHint("Open platform presets for TikTok, Reels, Shorts, YouTube, and Instagram Post.")
            .popover(isPresented: $isExportPresetsPresented, arrowEdge: .bottom) {
                PlatformExportPresetPopover(viewModel: viewModel)
                    .frame(width: 380)
            }

            Menu {
                Button("Video (Explicit Bitrate)…") {
                    Task { await viewModel.exportWithExplicitBitrate() }
                }
                Button("ProRes Master…") {
                    Task { await viewModel.exportProResMaster() }
                }
                Button("HDR Master (HEVC 10-bit, HLG)…") {
                    Task { await viewModel.exportHDRMaster() }
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
        .controlSize(.regular)
        .disabled(viewModel.exportEngine.isExporting)
    }

    private func topChromeCompactCluster<Content: View>(
        accessibilityLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: MovieCutSpacing.xxSmall) {
            content()
        }
        .controlSize(.small)
        .padding(.horizontal, MovieCutSpacing.xSmall)
        .padding(.vertical, 1)
        .background(
            Capsule()
                .fill(MovieCutTheme.controlSurface.opacity(0.18))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString(accessibilityLabel, comment: ""))
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

    private var platformPresetToolbarAccessibilityValue: String {
        if let preset = PlatformExportPreset.allCases.first(where: isPlatformPresetApplied) {
            return "\(preset.name), \(preset.detail)"
        }

        return "Custom export settings"
    }

    private func isPlatformPresetApplied(_ preset: PlatformExportPreset) -> Bool {
        viewModel.currentProject.canvas == preset.canvas
            && viewModel.currentProject.exportSettings == preset.exportSettings
    }

    /// Offers crash recovery when an autosave from a non-clean session exists.
    /// Skipped in headless harness / bootstrap runs so the modal never blocks.
    private func presentRecoveryIfNeeded() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST"] != "1", env["MOVIECUT_BOOTSTRAP_PROJECT"] == nil else { return }
        guard let recovered = await viewModel.recoverableProject() else { return }

        let alert = NSAlert()
        alert.messageText = "Recover unsaved work?"
        alert.informativeText = "MovieCut found a project from a session that didn't close normally."
        alert.addButton(withTitle: "Recover")
        alert.addButton(withTitle: "Discard")
        if alert.runModal() == .alertFirstButtonReturn {
            await viewModel.adoptRecoveredProject(recovered)
        } else {
            await viewModel.clearRecoveryAutosave()
        }
    }

    private var statusBar: some View {
        HStack(spacing: MovieCutSpacing.medium) {
            Label(canvasSizeText, systemImage: "rectangle")
            Text(viewModel.currentProject.canvas.frameRate.statusDisplayName)
            Spacer()
            Text(viewModel.lastErrorMessage ?? viewModel.lastStatusMessage ?? "")
                .foregroundStyle(viewModel.lastErrorMessage != nil ? .red : .secondary)
                .lineLimit(1)
                .accessibilityIdentifier("moviecut.status")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, MovieCutSpacing.medium)
        .padding(.vertical, MovieCutSpacing.xSmall)
        .background(MovieCutTheme.panelBackgroundRaised)
    }

    private var canvasSizeText: String {
        let size = viewModel.currentProject.canvas.size
        return "\(Int(size.width)) x \(Int(size.height))"
    }
}

private extension View {
    func topChromeSecondaryToolbarStyle() -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
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
        .movieCutScrollBackground(MovieCutTheme.panelBackgroundRaised)
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

private struct PlatformExportPresetPopover: View {
    var viewModel: EditorViewModel

    private let columns = [
        GridItem(.flexible(minimum: 152), spacing: MovieCutSpacing.small),
        GridItem(.flexible(minimum: 152), spacing: MovieCutSpacing.small)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            HStack(spacing: MovieCutSpacing.small) {
                Text("Platform Presets")
                    .font(.headline)
                Spacer()
                Text(activePreset?.name ?? "Custom")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MovieCutTheme.mutedText)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: MovieCutSpacing.small) {
                ForEach(PlatformExportPreset.allCases) { preset in
                    platformPresetButton(preset)
                }
            }

            Divider()
                .overlay(MovieCutTheme.divider)

            HStack(spacing: MovieCutSpacing.small) {
                Label("Estimated Size", systemImage: "externaldrive")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(estimatedFileSizeLabel)
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(Color.primary)

            if let activePreset, timelineDuration > activePreset.maxDurationSeconds {
                Label("Timeline exceeds \(activePreset.maxDurationHint.lowercased())", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(MovieCutSpacing.medium)
        .background(MovieCutTheme.panelBackgroundRaised)
    }

    private func platformPresetButton(_ preset: PlatformExportPreset) -> some View {
        let selected = isApplied(preset)

        return Button {
            Task {
                await viewModel.applyPlatformExportPreset(preset)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: MovieCutSpacing.xSmall) {
                    Image(systemName: preset.systemImageName)
                        .font(.title3)
                        .foregroundStyle(selected ? MovieCutTheme.accentCyan : Color.primary)

                    Spacer(minLength: MovieCutSpacing.xSmall)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MovieCutTheme.accentCyan)
                    }
                }

                Text(preset.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(preset.detail)
                    .font(.caption2)
                    .foregroundStyle(MovieCutTheme.mutedText)
                    .lineLimit(2)

                Text(preset.maxDurationHint)
                    .font(.caption2)
                    .foregroundStyle(MovieCutTheme.mutedText)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? MovieCutTheme.accentCyan.opacity(0.18) : MovieCutTheme.controlSurface.opacity(0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? MovieCutTheme.accentCyan.opacity(0.72) : MovieCutTheme.border.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Apply export preset \(preset.name)")
        .accessibilityValue(platformPresetAccessibilityValue(for: preset))
        .accessibilityHint("Applies \(preset.detail) export and canvas settings. This does not start export.")
    }

    private var activePreset: PlatformExportPreset? {
        PlatformExportPreset.allCases.first(where: isApplied)
    }

    private func isApplied(_ preset: PlatformExportPreset) -> Bool {
        viewModel.currentProject.canvas == preset.canvas
            && viewModel.currentProject.exportSettings == preset.exportSettings
    }

    private func platformPresetAccessibilityValue(for preset: PlatformExportPreset) -> String {
        let state = isApplied(preset) ? "Selected" : "Not selected"
        return "\(state). \(preset.detail). \(preset.maxDurationHint). Estimated size \(estimatedFileSizeLabel)."
    }

    private var timelineDuration: TimeInterval {
        max(viewModel.currentProject.timeline.duration, 0)
    }

    private var estimatedFileSizeLabel: String {
        guard timelineDuration > 0 else {
            return "Timeline empty"
        }

        let audioMbps = viewModel.currentProject.exportSettings.audioCodec == .pcm ? 1.5 : 0.192
        let megabytes = timelineDuration * (estimatedVideoBitrateMbps + audioMbps) / 8
        return String(format: "~%.1f MB for %.1fs", megabytes, timelineDuration)
    }

    private var estimatedVideoBitrateMbps: Double {
        let settings = viewModel.currentProject.exportSettings
        return Double(settings.resolvedVideoBitrateMbps ?? 10)
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

private extension PlatformExportPreset {
    var systemImageName: String {
        switch self {
        case .tikTok:
            return "music.note"
        case .instagramReels:
            return "camera.aperture"
        case .youtubeShorts:
            return "play.square.fill"
        case .youtubeStandard:
            return "play.rectangle.fill"
        case .instagramPost:
            return "square.grid.2x2"
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
