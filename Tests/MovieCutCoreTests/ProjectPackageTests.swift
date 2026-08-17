import Foundation
import Testing
@testable import MovieCutCore

/// F-23 project package: export/import round-trip with bundled media and the
/// media-replacement flow.
@Suite("Project Package")
struct ProjectPackageTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PkgTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Builds a project with one video clip referencing a real on-disk file.
    private func makeProject(mediaDir: URL) throws -> (Project, MediaAsset, URL) {
        let mediaFile = mediaDir.appendingPathComponent("clip.mp4")
        try Data("FAKE-MP4-BYTES".utf8).write(to: mediaFile)

        let asset = MediaAsset(
            originalURL: mediaFile,
            kind: .video,
            duration: 5,
            metadata: MediaMetadata(fileSize: 14)
        )
        var project = Project(name: "Packaged")
        project.mediaLibrary.assets[asset.id] = asset
        let clip = Clip(
            assetId: asset.id,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5)
        )
        var track = Track(kind: .video, name: "Video 1")
        track.clips = [clip]
        project.timeline.tracks = [track]
        return (project, asset, mediaFile)
    }

    @Test("export then load round-trips the project and bundles media (AC)")
    func roundTrip() throws {
        let work = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: work) }

        let (project, asset, _) = try makeProject(mediaDir: work)
        let packageURL = work.appendingPathComponent("Packaged.mctemplate")
        try ProjectPackage.export(project, to: packageURL)

        // Media file is copied into the package.
        let mediaInPackage = packageURL
            .appendingPathComponent("media")
            .appendingPathComponent("\(asset.id.uuidString).mp4")
        #expect(FileManager.default.fileExists(atPath: mediaInPackage.path))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("project.json").path))

        let loaded = try ProjectPackage.load(from: packageURL)
        #expect(loaded.name == "Packaged")
        #expect(loaded.timeline.tracks.first?.clips.first?.assetId == asset.id)

        // The loaded asset resolves to the bundled media file.
        let loadedAsset = try #require(loaded.mediaLibrary.assets[asset.id])
        #expect(loadedAsset.originalURL.path == mediaInPackage.path)
        #expect(FileManager.default.fileExists(atPath: loadedAsset.originalURL.path))
        #expect(try Data(contentsOf: loadedAsset.originalURL) == Data("FAKE-MP4-BYTES".utf8))
    }

    @Test("loaded package can have its media replaced (AC media-replacement flow)")
    func mediaReplacementFlow() throws {
        let work = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: work) }

        let (project, asset, _) = try makeProject(mediaDir: work)
        let packageURL = work.appendingPathComponent("Pkg.mctemplate")
        try ProjectPackage.export(project, to: packageURL)
        var loaded = try ProjectPackage.load(from: packageURL)

        // Replace the bundled media with a new external file via the asset library.
        let replacement = work.appendingPathComponent("replacement.mp4")
        try Data("NEW-MEDIA".utf8).write(to: replacement)
        let newAsset = MediaAsset(
            originalURL: replacement,
            kind: .video,
            duration: 8,
            metadata: MediaMetadata(fileSize: 9)
        )
        loaded.mediaLibrary.assets[asset.id] = MediaAsset(
            id: asset.id,
            originalURL: newAsset.originalURL,
            kind: .video,
            duration: 8,
            metadata: newAsset.metadata
        )

        let resolved = try #require(loaded.mediaLibrary.assets[asset.id])
        #expect(resolved.originalURL.lastPathComponent == "replacement.mp4")
        #expect(resolved.duration == 8)
        // The clip still references the same asset id, so the timeline is intact.
        #expect(loaded.timeline.tracks.first?.clips.first?.assetId == asset.id)
    }

    @Test("export overwrites an existing package directory")
    func exportOverwrites() throws {
        let work = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: work) }

        let (project, _, _) = try makeProject(mediaDir: work)
        let packageURL = work.appendingPathComponent("Pkg.mctemplate")
        try ProjectPackage.export(project, to: packageURL)
        // Plant a stale file that a second export should clear.
        let stale = packageURL.appendingPathComponent("stale.txt")
        try Data("x".utf8).write(to: stale)

        try ProjectPackage.export(project, to: packageURL)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("project.json").path))
    }

    @Test("loading a package without a manifest throws")
    func missingManifestThrows() throws {
        let work = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: work) }
        let empty = work.appendingPathComponent("Empty.mctemplate")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        #expect(throws: ProjectPackage.PackageError.manifestMissing) {
            _ = try ProjectPackage.load(from: empty)
        }
    }

    @Test("missing source media is skipped but still referenced")
    func missingSourceSkipped() throws {
        let work = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: work) }

        var project = Project(name: "Missing")
        let asset = MediaAsset(
            originalURL: work.appendingPathComponent("does-not-exist.mp4"),
            kind: .video,
            duration: 3,
            metadata: MediaMetadata(fileSize: nil)
        )
        project.mediaLibrary.assets[asset.id] = asset

        let packageURL = work.appendingPathComponent("Missing.mctemplate")
        try ProjectPackage.export(project, to: packageURL)
        let loaded = try ProjectPackage.load(from: packageURL)

        // The asset is still in the manifest, pointing into the (empty) media dir.
        let loadedAsset = try #require(loaded.mediaLibrary.assets[asset.id])
        #expect(loadedAsset.originalURL.lastPathComponent == "\(asset.id.uuidString).mp4")
        #expect(!FileManager.default.fileExists(atPath: loadedAsset.originalURL.path))
    }
}

/// Wiring visibility for the package UI (not a completion criterion by itself —
/// see spec DoD §1.3).
@Suite("Project Package Static Contract")
struct ProjectPackageStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("view model exports and imports packages")
    func viewModelWires() throws {
        // exportProjectPackage moved to the export boundary file;
        // importProjectPackage stayed in the main file.
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
            + source("App/MovieCutMac/EditorViewModel+Export.swift")
        #expect(viewModel.contains("func exportProjectPackage"))
        #expect(viewModel.contains("func importProjectPackage"))
        #expect(viewModel.contains("ProjectPackage.export"))
        #expect(viewModel.contains("ProjectPackage.load"))
    }

    @Test("content view exposes package export and import")
    func contentViewExposes() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        #expect(content.contains("Export Package"))
        #expect(content.contains("Import Package"))
        #expect(content.contains("exportProjectPackage"))
    }
}
