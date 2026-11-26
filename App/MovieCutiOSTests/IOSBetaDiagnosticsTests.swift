import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// CA-30 2차: the iOS opt-in export surface — the VM exposes the local
/// JSONL for the share sheet, and real funnel events land in it.
@MainActor
@Suite("iOS beta diagnostics export (CA-30)")
struct IOSBetaDiagnosticsTests {

    @Test("The diagnostics file exists and receives real funnel events")
    func exportURLAndEvents() async throws {
        let vm = IOSEditorViewModel(
            autosaveDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ca30-ios-\(UUID().uuidString)", isDirectory: true)
        )

        let url = try #require(await vm.betaDiagnosticsExportURL())
        #expect(FileManager.default.fileExists(atPath: url.path))

        // A real import writes the funnel's first event.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MovieCutiOSTests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // repo root
        let wav = repoRoot
            .appendingPathComponent("Tests/Fixtures/duck_voice_1000hz_1s_mono.wav")
        #expect(FileManager.default.fileExists(atPath: wav.path))
        await vm.importMedia(from: wav, kind: .audio)

        let contents = try #require(await vm.betaDiagnostics.fileContents())
        #expect(contents.contains("import_start"), "funnel event missing: \(contents)")
    }
}
