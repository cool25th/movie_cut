import Foundation
import Testing
import MovieCutCore
@testable import MovieCutMac

/// CA-25: the bundled sample project (W1-mini `.mctemplate`) must ship in the
/// app bundle and load cleanly — it is the first-run onboarding entry ("Open
/// the sample project"), so a build that loses it breaks the welcome card.
///
/// Regeneration (explicit, never in CI): generate media with
/// `swift scripts/gen_sample_media.swift /tmp/sample_media.mov`, then run this
/// suite with `MOVIECUT_GEN_SAMPLE_TEMPLATE=1
/// MOVIECUT_SAMPLE_MEDIA=/tmp/sample_media.mov` to re-export the package into
/// `App/MovieCutMac/Resources/SampleProject.mctemplate`, then commit it.
@MainActor
@Suite("Bundled sample project")
struct SampleProjectTemplateTests {
    @Test("bundled sample template loads with a vertical clip and real media")
    func bundledSampleLoads() throws {
        let url = try #require(
            Bundle.main.url(forResource: "SampleProject", withExtension: ProjectPackage.fileExtension),
            "SampleProject.mctemplate must ship in the app bundle (project.yml resources)"
        )
        let project = try ProjectPackage.load(from: url)

        #expect(project.canvas.aspectRatio == .portrait9x16, "sample is a 9:16 short")
        #expect(project.mediaLibrary.assets.count == 1, "exactly one sample asset")
        let clips = project.timeline.tracks.flatMap(\.clips)
        #expect(clips.count == 1, "one clip placed on the timeline")
        #expect(clips.first?.kind == .video)

        // The resolved media file must exist inside the package.
        let asset = try #require(project.mediaLibrary.assets.values.first)
        #expect(asset.kind == .video)
        #expect(asset.duration ?? 0 > 0, "sample duration should be known")
        #expect(FileManager.default.fileExists(atPath: asset.originalURL.path), "packaged media file exists")
    }

    @Test("sample opens through the view-model adoption path with writable staged media")
    func sampleOpensThroughViewModel() async throws {
        let viewModel = EditorViewModel(project: Project(name: "Sample Host"))

        let opened = await viewModel.openBundledSampleProject()
        #expect(opened, "sample must open in the test host: \(viewModel.lastErrorMessage ?? "no error")")

        // Adoption contract: clean baseline, no error surfaced.
        #expect(viewModel.isDirty == false)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(viewModel.currentProject.timeline.tracks.flatMap(\.clips).count == 1)

        // P2 fix pinned: media must NOT point into the read-only app bundle —
        // the open path stages copies into the managed imports root and
        // records the managed-relative path (SURV-01 convention).
        let asset = try #require(viewModel.currentProject.mediaLibrary.assets.values.first)
        #expect(!asset.originalURL.path.contains(".app/"), "media must be staged outside the bundle")
        #expect(asset.managedImportPath != nil, "staged copy records its managed-relative path")
        #expect(FileManager.default.fileExists(atPath: asset.originalURL.path))
    }

    /// Regeneration lives in Core tests (`SampleProjectTemplateGenerationTests`)
    /// — `swift test` inherits the generator env reliably; the hosted runner
    /// does not, which silently skipped the test here (0-tests fake green).
}
