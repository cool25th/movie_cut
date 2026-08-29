#if os(iOS)
import AVFoundation
import CoreMedia
import Foundation
import MovieCutCore

/// G-27 simulator E2E (development plan §3-11 ①) — the iOS counterpart of
/// the Mac DEBUG harness: an env-gated flow (`MOVIECUT_UITEST=1`, launched
/// via `simctl` with `SIMCTL_CHILD_` prefixed variables) that drives the
/// REAL app paths — import, the shared preview composition builder, the
/// export engine, AVAudioSession routing, and ProjectStore persistence
/// across a process boundary — and appends structured result lines to
/// `Documents/g27-result.txt` for the driving script to assert. The app
/// never exits itself; the script terminates it after reading the result.
@MainActor
enum IOSUITestHarness {
    static func runIfRequested(viewModel: IOSEditorViewModel) async {
        let env = ProcessInfo.processInfo.environment
        guard env["MOVIECUT_UITEST"] == "1" else { return }
        await run(environment: env, viewModel: viewModel)
    }

    /// The per-execution run ID that scopes every result line this launch
    /// writes, so a driving script can wait on / assert against ONLY this
    /// run's rows even when `g27-result.txt` still carries rows from older
    /// executions. The driver passes `MOVIECUT_G27_RUN_ID`; when absent
    /// (e.g. the simulator gate, which resets the container itself) a
    /// process-unique ID is generated so each launch still self-isolates.
    static func resolvedRunID(environment: [String: String]) -> String {
        if let passed = environment["MOVIECUT_G27_RUN_ID"], !passed.isEmpty {
            return passed
        }
        return "g27-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
    }

    /// Tags one result row with the run scope. Every line the harness emits
    /// goes through here — `run=<id> g27_import …` — which keeps driver-side
    /// `grep "run=$RUN_ID "` filtering exact (space-terminated, no prefix
    /// collisions between similar IDs).
    static func taggedLine(runID: String, line: String) -> String {
        "run=\(runID) \(line)"
    }

    private static func resultURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("g27-result.txt")
    }

    private static func report(_ line: String, runID: String) {
        guard let url = resultURL() else { return }
        let stamped = taggedLine(runID: runID, line: line) + "\n"
        // Appends across phases (the reopen launch must extend phase 1's
        // file, not replace it).
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.closeFile() }
            _ = try? handle.seekToEnd()
            if let data = stamped.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        } else {
            try? stamped.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func run(environment: [String: String], viewModel: IOSEditorViewModel) async {
        let runID = resolvedRunID(environment: environment)
        report("g27_start", runID: runID)
        do {
            if environment["MOVIECUT_UITEST_REOPEN"] == "1" {
                try await reopenPhase(runID: runID)
            } else {
                try await mainPhase(viewModel: viewModel, runID: runID)
            }
            report("g27_done error=none", runID: runID)
        } catch {
            report("g27_done error=\(error.localizedDescription)", runID: runID)
        }
    }

    // MARK: - Phase 1: import → preview → export → audio routing → save

    private static func mainPhase(viewModel: IOSEditorViewModel, runID: String) async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        // 1. IMPORT — fixtures the script staged in Documents/in/.
        guard let documents else {
            throw NSError(domain: "G27", code: 1, userInfo: [NSLocalizedDescriptionKey: "no Documents"])
        }
        let fixture = documents.appendingPathComponent("in/fixture.mp4")
        let tone = documents.appendingPathComponent("in/tone.wav")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw NSError(domain: "G27", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing staged fixture"])
        }
        // The app's import flow: probe → register → add to the timeline
        // (importMedia alone only registers the asset in the library).
        let videoAsset = MediaImporter.probe(url: fixture)
        await viewModel.importMedia(from: fixture)
        await viewModel.addClipToTimeline(asset: videoAsset)
        if FileManager.default.fileExists(atPath: tone.path) {
            let toneAsset = MediaImporter.probe(url: tone)
            await viewModel.importMedia(from: tone, kind: .audio)
            await viewModel.addClipToTimeline(asset: toneAsset)
        }
        let importedClips = viewModel.currentProject.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        guard importedClips >= 1 else {
            throw NSError(domain: "G27", code: 3, userInfo: [NSLocalizedDescriptionKey: "import produced no clips"])
        }
        report("g27_import imported_clips=\(importedClips)", runID: runID)

        // 2. PREVIEW — the SAME composition the app's PreviewView builds,
        // plus one rendered frame through AVAssetImageGenerator.
        let composition = AVMutableComposition()
        let hasPlayableMedia = IOSPreviewCompositionBuilder.populate(composition, from: viewModel.currentProject)
        let duration = composition.duration.seconds.isFinite ? composition.duration.seconds : 0
        var frameRendered = false
        if hasPlayableMedia, duration > 0 {
            let generator = AVAssetImageGenerator(asset: composition)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            frameRendered = (try? generator.copyCGImage(at: CMTime(seconds: min(0.5, duration / 2), preferredTimescale: 600), actualTime: nil)) != nil
        }
        report("g27_preview playable=\(hasPlayableMedia ? 1 : 0) duration=\(String(format: "%.3f", duration)) frame=\(frameRendered ? 1 : 0)", runID: runID)
        guard hasPlayableMedia, duration > 0, frameRendered else {
            throw NSError(domain: "G27", code: 4, userInfo: [NSLocalizedDescriptionKey: "preview composition not playable/renderable"])
        }

        // 3. EXPORT — the real iOS export engine.
        let exportURL = try await viewModel.exportProject()
        let size = (try? FileManager.default.attributesOfItem(atPath: exportURL.path)[.size] as? Int) ?? 0
        report("g27_export file=\(exportURL.lastPathComponent) bytes=\(size ?? 0)", runID: runID)
        guard (size ?? 0) > 0 else {
            throw NSError(domain: "G27", code: 5, userInfo: [NSLocalizedDescriptionKey: "export produced empty file"])
        }

        // 4. AUDIO ROUTING — configure the playback session and report the
        // active category + route (the SFX picker's category pattern).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        let route = session.currentRoute.outputs.first?.portType.rawValue ?? "none"
        report("g27_audio category=\(session.category.rawValue) route=\(route)", runID: runID)
        guard session.category == .playback else {
            throw NSError(domain: "G27", code: 6, userInfo: [NSLocalizedDescriptionKey: "audio session not playback"])
        }

        // 5. SAVE — ProjectStore persistence the reopen phase verifies.
        let projectURL = documents.appendingPathComponent("g27-project.moviecut")
        try await ProjectStore().save(viewModel.currentProject, to: projectURL)
        report("g27_save saved=1 path=\(projectURL.lastPathComponent)", runID: runID)
    }

    // MARK: - Phase 2: reopen the saved project in a fresh process

    private static func reopenPhase(runID: String) async throws {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "G27", code: 7, userInfo: [NSLocalizedDescriptionKey: "no Documents"])
        }
        let projectURL = documents.appendingPathComponent("g27-project.moviecut")
        let project = try await ProjectStore().load(from: projectURL)
        let clips = project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        report("g27_reopen reopened_clips=\(clips)", runID: runID)
        guard clips >= 1 else {
            throw NSError(domain: "G27", code: 8, userInfo: [NSLocalizedDescriptionKey: "reopened project has no clips"])
        }
    }
}
#endif
