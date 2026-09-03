import AVFoundation
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// STAB-02's remaining leg: the writer path's cancellation plumbing
/// (cancelExport → reader.cancelReading/writer.cancelWriting → pumps fail
/// into the catch path → partial output removed) had no live-export test —
/// the "live export test infrastructure" gap recorded in the ledger. This
/// drives a REAL ProRes export of a committed fixture, cancels it
/// mid-flight, and measures the contract: the export fails (not
/// half-succeeds), the partial file is deleted, and the engine resets.
/// CI gate: GitHub's macOS runners have no functional audio HAL — the first
/// CI exposure of this suite (PR #24, 2026-09-04) crashed the test host
/// mid-export (AudioFileObject open failures → AudioQueue start error −4 →
/// "Restarting after unexpected exit"); the retry passes, but the launch
/// crash still fails the step. Live coverage stays on local/loop runs where
/// the audio stack works.
@MainActor
@Suite(
    "Export cancel mid-flight (STAB-02 E2E)",
    .enabled(if: ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != "1")
)
struct ExportCancelMidFlightTests {
    private static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutMacTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/solid_red_1440x1080_2s_30fps.mp4")

    /// The video fixture has NO audio track — renderGraphAudio throws noAudio
    /// before any pumping, which would make both legs pass for the WRONG
    /// reason (graph error, not cancellation). The tone clip gives the graph
    /// a real mix so the writer path reaches its pumps.
    private static let toneURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tests/Fixtures/tone_440hz_2s_mono.wav")

    private func makeProject() throws -> Project {
        let url = Self.fixtureURL
        let tone = Self.toneURL
        guard FileManager.default.fileExists(atPath: url.path),
              FileManager.default.fileExists(atPath: tone.path) else {
            throw NSError(domain: "cancel-e2e", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "fixture missing"])
        }
        // The media library's dictionary key MUST be the asset's own id
        // (the import pipeline's contract): AudioGraphProjectBuilder puts
        // asset.id — the STRUCT field, which defaults to a fresh random
        // UUID — into the plan, and GraphMixRenderer resolves plan sources
        // through the dictionary KEY. Keying by an external UUID (my first
        // attempt) made every export die with assetMissing(<random>) before
        // the pumps — the exact failure that blocked this suite.
        let assetId = UUID()
        let asset = MediaAsset(id: assetId, originalURL: url, kind: .video, duration: 2)
        let toneId = UUID()
        let toneAsset = MediaAsset(id: toneId, originalURL: tone, kind: .audio, duration: 2)
        var project = Project(
            name: "cancel-e2e",
            mediaLibrary: MediaLibrary(assets: [assetId: asset, toneId: toneAsset]),
            timeline: Timeline(canvasSize: CGSize(width: 1440, height: 1080), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: [
                    Clip(
                        assetId: assetId,
                        kind: .video,
                        sourceRange: TimeRange(start: 0, duration: 2),
                        timelineRange: TimeRange(start: 0, duration: 2)
                    )
                ]),
                Track(kind: .audio, name: "A", zIndex: 1, clips: [
                    Clip(
                        assetId: toneId,
                        kind: .audio,
                        sourceRange: TimeRange(start: 0, duration: 2),
                        timelineRange: TimeRange(start: 0, duration: 2)
                    )
                ])
            ])
        )
        // The fixture is 4:3 — a 16:9 canvas letterboxes; a 4:3 canvas keeps
        // every pixel active so the ProRes encode has real work per frame.
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 1440, customHeight: 1080)
        return project
    }

    @Test("cancelling a ProRes export mid-flight fails cleanly and deletes the partial file")
    func cancelMidFlightProRes() async throws {
        let engine = ExportEngine()
        let project = try makeProject()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancel-e2e-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: output) }

        // ProRes 422 at 1440x1080 encodes slowly enough that a cancel issued
        // after the first frames are written lands mid-flight, not after
        // completion (the wall-clock for the full export is seconds).
        final class CompletionBox: @unchecked Sendable { var done = false }
        let box = CompletionBox()
        let exportTask = Task {
            defer { box.done = true }
            return try await engine.exportVideoWithExplicitBitrate(
                project: project,
                to: output,
                profileOverride: .proRes422
            )
        }

        // Wait until the engine registers the live session (the writer path
        // sets isExporting synchronously before the pumps start).
        for _ in 0..<200 {
            if engine.isExporting { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        // Repeated firing until the export ends — the harness E2E measured
        // that a single early shot lands during the audio-graph phase BEFORE
        // the writer session is registered and cancels nothing (the export
        // then completes normally and the test would false-fail).
        while !box.done {
            engine.cancelExport()
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        var threw = false
        do {
            _ = try await exportTask.value
        } catch {
            threw = true
        }
        #expect(threw, "a cancelled export must FAIL — a half-succeeded file is the silent-quality bug class")
        #expect(engine.exportError?.contains("RenderError") != true,
                "the failure must be the cancellation path, not the graph mix dying first (the no-audio trap)")
        #expect(!FileManager.default.fileExists(atPath: output.path),
                "the partial output must be deleted by the cancel catch path")
        #expect(engine.isExporting == false, "the engine must reset after cancellation")
        #expect(engine.lastExportURL == nil, "a cancelled export must not claim success state")
    }

    @Test("an uncancelled explicit-bitrate export of the same project completes")
    func sanityUncancelledCompletes() async throws {
        let engine = ExportEngine()
        let project = try makeProject()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancel-e2e-ok-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: output) }

        let url = try await engine.exportVideoWithExplicitBitrate(
            project: project,
            to: output,
            profileOverride: .proRes422
        )
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(engine.isExporting == false)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        #expect(abs(duration - 2.0) < 0.15,
                "the sanity leg must produce a full 2s export; got \(duration)")
    }
}
