import SwiftUI

/// The initial macOS editor shell shown before a project is opened.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("No Project Open")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Create or open a MovieCut project to begin editing.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}

#Preview {
    ContentView()
}
