import SwiftUI
import MovieCutCore

struct ContentView: View {
    var viewModel: EditorViewModel
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

                Button(action: { Task { await viewModel.deleteClip() } }) {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: .command)

                Divider()

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

                Button(action: { Task { await viewModel.exportProject() } }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.exportEngine.isExporting },
            set: { _ in }
        )) {
            ExportSheet(exportEngine: viewModel.exportEngine)
        }
        .sheet(isPresented: $isTemplatePickerPresented) {
            TemplatePickerView(viewModel: viewModel)
        }
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
}

struct ExportSheet: View {
    var exportEngine: ExportEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exporting")
                .font(.headline)
            ProgressView(value: exportEngine.exportProgress)
                .frame(width: 280)
            Text(String(format: "%.0f%%", exportEngine.exportProgress * 100))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let exportError = exportEngine.exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
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
