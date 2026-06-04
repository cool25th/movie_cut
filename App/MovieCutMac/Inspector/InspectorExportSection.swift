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
                Text("High (20 Mbps)").tag("high")
                Text("Medium (10 Mbps)").tag("medium")
                Text("Low (5 Mbps)").tag("low")
            }
            Picker("Format", selection: $viewModel.exportFormat) {
                Text("MP4").tag("mp4")
                Text("MOV").tag("mov")
            }
        }
        .padding(12)
    }
}
