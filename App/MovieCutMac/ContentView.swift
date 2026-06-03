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
