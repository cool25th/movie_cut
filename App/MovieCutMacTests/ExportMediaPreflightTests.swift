import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// BUG-04 (CA-03 audit): missing-media detection and the relink prompt only
/// ran at project OPEN — an external disk ejected mid-session failed the
/// export minutes into the render. These tests pin the export pre-flight on
/// the real ViewModel paths: unreachable media refuses BEFORE any render
/// work with relink guidance; reachable media passes the gate.
@MainActor
@Suite("Export media pre-flight (BUG-04)")
struct ExportMediaPreflightTests {
    private func clip(assetId: UUID) -> Clip {
        Clip(
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1)
        )
    }

    private func makeViewModel(mediaURL: URL) -> EditorViewModel {
        let assetId = UUID()
        return EditorViewModel(project: Project(
            name: "preflight",
            mediaLibrary: MediaLibrary(assets: [
                assetId: MediaAsset(originalURL: mediaURL, kind: .video, duration: 1)
            ]),
            timeline: Timeline(canvasSize: CGSize(width: 100, height: 100), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip(assetId: assetId)])
            ])
        ))
    }

    @Test("unreachable media fails the pre-flight with relink guidance, not mid-render")
    func missingMediaRefusesBeforeRender() {
        // A path that cannot exist: creation refuses, directory listing fails.
        let vm = makeViewModel(mediaURL: URL(fileURLWithPath: "/nonexistent-volume-abc/media.mp4"))
        #expect(vm.missingMediaAssets.isEmpty, "baseline: not yet evaluated")

        let passed = vm.ensureAllMediaReachableForExport()

        #expect(passed == false, "export must refuse when source media is unreachable")
        #expect(vm.missingMediaAssets.count == 1)
        #expect(vm.lastErrorMessage != nil, "the refusal must tell the user why")
        #expect(vm.lastExportURL == nil)
        // Locale-agnostic: the localized sentence embeds the count and names
        // the relink command; assert via the re-evaluated missing list +
        // non-nil error rather than English text.
    }

    @Test("reachable media passes the pre-flight cleanly")
    func reachableMediaPasses() throws {
        let media = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca03-bug04-\(UUID().uuidString).mp4")
        try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]).write(to: media)
        defer { try? FileManager.default.removeItem(at: media) }

        let vm = makeViewModel(mediaURL: media)
        let passed = vm.ensureAllMediaReachableForExport()

        #expect(passed == true)
        #expect(vm.lastErrorMessage == nil)
    }

    @Test("exportProject(to:) refuses before touching the export engine")
    func exportEntryRefusesBeforeEngine() async {
        let vm = makeViewModel(mediaURL: URL(fileURLWithPath: "/nonexistent-volume-abc/media.mp4"))
        await vm.exportProject(to: FileManager.default.temporaryDirectory
            .appendingPathComponent("should-not-exist-\(UUID().uuidString).mov"))

        #expect(vm.lastErrorMessage != nil, "missing media must refuse with guidance")
        #expect(vm.lastExportURL == nil)
        // The pre-flight fired before the engine: the refusal message is the
        // pre-flight's (missing-media count), not an encoder error.
        #expect(vm.missingMediaAssets.count == 1)
    }
}
