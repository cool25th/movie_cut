import SwiftUI

/// The initial iOS editor shell shown before a project is opened.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("No Project Open")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Create or open a MovieCut project to begin editing.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
