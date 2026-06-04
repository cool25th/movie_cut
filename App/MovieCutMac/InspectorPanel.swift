import SwiftUI
import MovieCutCore

struct InspectorPanel: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding(12)

            Divider()

            if let clip = viewModel.selectedClip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        InspectorBasicSection(viewModel: viewModel, clip: clip)
                        InspectorEffectsSection(viewModel: viewModel, clip: clip)
                        InspectorAnalysisSection(viewModel: viewModel, clip: clip)
                    }
                    .padding(12)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Select a clip to inspect")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            InspectorExportSection(viewModel: viewModel)
        }
        .frame(minWidth: 240)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
