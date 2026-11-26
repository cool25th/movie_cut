import Foundation
import MovieCutCore
import Testing

/// AI-03a storage isolation (CRASH_DIAGNOSIS_20261005 §3): an injected
/// autosave directory must be the root for BOTH autosave write paths — the
/// rolling recovery file and the named periodic autosaves — so tests never
/// leave projects in the real app's recovery list.
@Suite("ProjectStore named autosave directory")
struct ProjectStoreNamedAutosaveDirectoryTests {

    @Test("injected directory is the named-autosave root")
    func injectedDirectoryWins() throws {
        let injected = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-isolation-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectStore(autosaveDirectory: injected)

        #expect(store.namedAutosaveDirectory == injected)
    }

    @Test("default store keeps the production MovieCut root")
    func defaultStoreKeepsProductionRoot() throws {
        let store = ProjectStore()
        let expected = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MovieCut", isDirectory: true)

        #expect(store.namedAutosaveDirectory == expected)
    }

    @Test("recovery-disabled store still names the production root for named autosaves")
    func disabledRecoveryKeepsNamedRoot() throws {
        let store = ProjectStore(autosaveDirectory: nil)
        let expected = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MovieCut", isDirectory: true)

        #expect(store.namedAutosaveDirectory == expected)
    }
}
