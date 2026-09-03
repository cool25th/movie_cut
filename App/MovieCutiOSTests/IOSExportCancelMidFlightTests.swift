import AVFoundation
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// BUG-ACC-09: the iOS writer path's cancellation plumbing had the SAME
/// mechanism the Mac STAB-02 cancel E2E measured as two product defects —
/// a cancelled writer never re-invokes requestMediaDataWhenReady (both
/// pumps leak their continuations → the export parks forever), and a
/// cancelled writer passed to finishWriting raises
/// NSInternalInconsistencyException (process death). This suite drives a
/// REAL export of a committed fixture with embedded audio (both pumps),
/// cancels it mid-flight, and measures the contract: the export FAILS
/// (not parks, not half-succeeds), the partial file is deleted, and the
/// engine resets.
@MainActor
@Suite("iOS export cancel mid-flight (BUG-ACC-09)")
struct IOSExportCancelMidFlightTests {
    /// Red + 440Hz tone in ONE asset — the composition carries both tracks
    /// so both writer pumps run (the video-pump-alone class is a different,
    /// already-fixed defect).
    private static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/solid_red_tone_320x240_2s_30fps.mp4")

    private func makeProject() throws -> Project {
        let url = Self.fixtureURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "ios-cancel-e2e", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "fixture missing"])
        }
        // The media library's dictionary key must be the asset's own id
        // (the import pipeline's invariant — the Mac STAB-02 test measured
        // that keying by an external UUID makes graph lookups die with
        // assetMissing; keep the explicit id here for the same reason).
        let assetId = UUID()
        let asset = MediaAsset(id: assetId, originalURL: url, kind: .video, duration: 2)
        var project = Project(
            name: "ios-cancel-e2e",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: [
                    Clip(
                        assetId: assetId,
                        kind: .video,
                        sourceRange: TimeRange(start: 0, duration: 2),
                        timelineRange: TimeRange(start: 0, duration: 2)
                    )
                ])
            ])
        )
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 320, customHeight: 240)
        return project
    }

    @Test("cancelling an export mid-flight fails cleanly and deletes the partial file")
    func cancelMidFlight() async throws {
        let engine = IOSExportEngine()
        let project = try makeProject()

        final class CompletionBox: @unchecked Sendable {
            var done = false
            var outputURL: URL?
        }
        let box = CompletionBox()
        let exportTask = Task {
            defer { box.done = true }
            return try await engine.exportProject(project)
        }

        // Wait for the engine to be live, then fire repeatedly until the
        // export ends — the Mac E2E measured that a single early shot lands
        // during the composition/render-plan phase BEFORE the writer session
        // is registered and cancels nothing.
        for _ in 0..<200 {
            if engine.isExporting { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        while !box.done {
            if box.outputURL == nil, let url = engine.activeOutputURL {
                box.outputURL = url
            }
            engine.cancelExport()
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        var threw = false
        do {
            _ = try await exportTask.value
        } catch {
            threw = true
        }
        #expect(threw, "a cancelled export must FAIL — parking (hang) or half-success are both contract violations")
        #expect(engine.lastExportURL == nil, "a cancelled export must not claim success state")
        #expect(engine.isExporting == false, "the engine must reset after cancellation")
        if let staged = box.outputURL {
            #expect(!FileManager.default.fileExists(atPath: staged.path),
                    "the partial output must be deleted by the cancel catch path")
        } else {
            Issue.record("the writer path never staged an output URL — the cancel window was missed entirely")
        }
    }

    @Test("an uncancelled export of the same project completes")
    func sanityUncancelledCompletes() async throws {
        let engine = IOSExportEngine()
        let project = try makeProject()

        let url = try await engine.exportProject(project)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(engine.isExporting == false)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - 2.0) < 0.15,
                "the sanity leg must produce a full 2s export; got \(duration)")
    }
}
