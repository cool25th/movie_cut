#if os(iOS)
import SwiftUI

/// The iOS entry point for MovieCut.
@main
struct MovieCutiOSApp: App {
    var body: some Scene {
        WindowGroup {
            IOSContentView()
        }
    }
}
#endif
