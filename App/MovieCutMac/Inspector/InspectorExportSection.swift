import SwiftUI

struct InspectorExportSection: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        Section("Export Settings") {
            Picker("Resolution", selection: $viewModel.exportResolution) {
                Text("4K (3840x2160)").tag("4k")
                Text("1080p (1920x1080)").tag("1080p")
                Text("720p (1280x720)").tag("720p")
                Text("480p (854x480)").tag("480p")
            }
            Picker("Quality", selection: $viewModel.exportQuality) {
                Text("High").tag("high")
                Text("Medium").tag("medium")
                Text("Low").tag("low")
            }
        }
        .padding(12)
    }
}
