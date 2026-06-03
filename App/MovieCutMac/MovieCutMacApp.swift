import SwiftUI
import MovieCutCore

@main
struct MovieCutMacApp: App {
    @State private var viewModel = EditorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {}
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open...") {}
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save...") {
                    Task { await viewModel.saveProject() }
                }
                    .keyboardShortcut("s", modifiers: .command)
                Divider()
                Button("Import Media...") {}
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("Export...") {
                    Task { await viewModel.exportProject() }
                }
                .keyboardShortcut("e", modifiers: .command)
            }
        }
    }
}
