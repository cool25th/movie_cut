import SwiftUI
import MovieCutCore

@main
struct MovieCutMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {}
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open...") {}
                    .keyboardShortcut("o", modifiers: .command)
                Button("Save...") {}
                    .keyboardShortcut("s", modifiers: .command)
                Divider()
                Button("Import Media...") {}
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}
