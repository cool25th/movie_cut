import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

@MainActor
@Suite("AI Photo Montage E2E Integration Tests")
struct AIPhotoMontageE2ETests {

    private static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            let candidate = url.appendingPathComponent("Tests/Fixtures")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        fatalError("Could not locate repo root from \(#filePath)")
    }()

    private enum FixtureStagingError: Error, CustomStringConvertible {
        case missingSource(URL)
        case copyFailed(source: URL, destination: URL, underlying: String)

        var description: String {
            switch self {
            case .missingSource(let url):
                return "Fixture missing at \(url.path)"
            case .copyFailed(let source, let destination, let underlying):
                return "Could not stage fixture \(source.path) → \(destination.path): \(underlying)"
            }
        }
    }

    /// Stages a repo fixture into the test's per-run storage directory (under
    /// the sandboxed app's own temporaryDirectory — grant-free, deleted with
    /// the storage root at test end). The repository tree itself is not
    /// grant-free under App Sandbox (task-511.log recorded read denials).
    /// Every failure carries BOTH URLs so a permission denial is attributable
    /// to a concrete path. Entitlements are not broadened for tests.
    private static func stagedFixture(_ name: String, in directory: URL) throws -> URL {
        let source = repoRoot.appendingPathComponent("Tests/Fixtures/\(name)")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw FixtureStagingError.missingSource(source)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        do {
            try FileManager.default.removeItem(at: destination)
        } catch {
            // First copy of the run — nothing to remove.
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw FixtureStagingError.copyFailed(source: source, destination: destination, underlying: error.localizedDescription)
        }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw FixtureStagingError.copyFailed(source: source, destination: destination, underlying: "destination missing after copy")
        }
        return destination
    }

    /// Snapshot of the REAL app-container storage the test must not touch:
    /// the crash-recovery file and the named-autosave directory
    /// (CRASH_DIAGNOSIS_20261005 §3 — a previous run left `AIVideoTest` in
    /// the real app's recovery prompt).
    private struct ContainerStorageFootprint: Equatable {
        var recoveryExists: Bool
        var recoverySize: Int64
        var autosaveEntryCount: Int

        static func capture() -> Self {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("MovieCut", isDirectory: true)
            let recovery = support?.appendingPathComponent("recovery.moviecut")
            let autosave = support?.appendingPathComponent("Autosave", isDirectory: true)
            let recoveryExists = recovery.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let recoverySize = recovery
                .flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path) }
                .flatMap { ($0[.size] as? NSNumber)?.int64Value } ?? 0
            let autosaveEntryCount = autosave
                .map { (try? FileManager.default.contentsOfDirectory(atPath: $0.path))?.count ?? 0 } ?? 0
            return Self(
                recoveryExists: recoveryExists,
                recoverySize: recoverySize,
                autosaveEntryCount: autosaveEntryCount
            )
        }
    }

    @Test("Photos + Audio -> 15s Timeline Creation -> Undo/Redo -> Real MP4 Export")
    func photoMontageCreationAndExportEndToEnd() async throws {
        // Per-run storage root: fixtures, ISOLATED autosave, and export all
        // live under one grant-free temporary directory the test removes on
        // exit. The ViewModel's autosave directory is injected so BOTH write
        // paths (rolling recovery + named 30 s autosave) stay out of the
        // real app container.
        let storageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai_e2e_storage_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storageRoot) }

        let fixturesDir = storageRoot.appendingPathComponent("fixtures", isDirectory: true)
        let photo1 = try Self.stagedFixture("swatch_blue_64x64.png", in: fixturesDir)
        let photo2 = try Self.stagedFixture("swatch_green_64x64.heic", in: fixturesDir)
        let photo3 = try Self.stagedFixture("exif_orient6_asym_320x240.jpg", in: fixturesDir)
        let music = try Self.stagedFixture("duck_bgm_220hz_4s_mono.wav", in: fixturesDir)

        let footprintBefore = ContainerStorageFootprint.capture()

        let vm = EditorViewModel(
            project: Project(name: "AIVideoTest"),
            autosaveDirectory: storageRoot.appendingPathComponent("autosave", isDirectory: true)
        )

        let initialCanvas = vm.currentProject.canvas
        let initialCanvasSize = vm.currentProject.timeline.canvasSize
        let initialTrackCount = vm.currentProject.timeline.tracks.count
        let initialAssetCount = vm.currentProject.mediaLibrary.assets.count

        // 1. Generate 15s photo montage (preview composition builds here —
        // this is where the overlapping-ramp exception used to fire).
        let preparedPlan = try await vm.applyPhotoMontage(
            photoURLs: [photo1, photo2, photo3],
            musicURL: music,
            targetDuration: 15.0,
            targetCanvas: .portrait9x16
        )

        #expect(preparedPlan.expectedDuration == 15.0)
        #expect(vm.currentProject.timeline.duration == 15.0)
        #expect(vm.currentProject.canvas == .portrait9x16)

        // Verify bookmarks are captured for all imported assets
        for asset in vm.currentProject.mediaLibrary.assets.values {
            #expect(asset.originalBookmark != nil, "Asset \(asset.originalURL.lastPathComponent) must carry a bookmark")
        }

        let videoTracks = vm.currentProject.timeline.tracks.filter { $0.kind == .video }
        try #require(videoTracks.count == 1, "expected exactly 1 video track, got \(videoTracks.count)")
        let videoClips = videoTracks[0].clips
        try #require(videoClips.count == 3, "expected 3 photo clips, got \(videoClips.count)")

        for clip in videoClips {
            #expect(clip.timelineRange.duration == 5.0)
            #expect(!clip.keyframes.isEmpty)
        }

        // Audio: 4s music loops 4+4+4+3=15s
        let audioTracks = vm.currentProject.timeline.tracks.filter { $0.kind == .audio }
        try #require(audioTracks.count == 1, "expected exactly 1 audio track, got \(audioTracks.count)")
        let audioClips = audioTracks[0].clips
        try #require(audioClips.count == 4, "4s music should loop 4 times to fill 15s, got \(audioClips.count)")

        for clip in audioClips {
            #expect(clip.sourceRange.duration <= 4.0 + 0.001, "Clip sourceRange must never exceed raw asset duration")
            #expect(clip.sourceRange.end <= 4.0 + 0.001)
            // No phantom ducking: photo clips are not voice, and live
            // auto-ducking is retired (preview/export parity).
            #expect(clip.duckingLevel == nil, "montage music must not be ducked")
            #expect(clip.duckingRanges.isEmpty)
        }
        let junction = PhotoMontagePlanner.Limits.junctionFadeDuration
        #expect(audioClips[0].timelineRange == TimeRange(start: 0, duration: 4))
        #expect(audioClips[0].fadeInDuration == 0.5)
        #expect(audioClips[0].fadeOutDuration == junction)

        #expect(audioClips[1].timelineRange == TimeRange(start: 4, duration: 4))
        #expect(audioClips[1].fadeInDuration == junction)
        #expect(audioClips[2].timelineRange == TimeRange(start: 8, duration: 4))
        #expect(audioClips[2].fadeOutDuration == junction)

        #expect(audioClips[3].timelineRange == TimeRange(start: 12, duration: 3))
        #expect(audioClips[3].sourceRange == TimeRange(start: 0, duration: 3))
        #expect(audioClips[3].fadeInDuration == junction)
        #expect(audioClips[3].fadeOutDuration == 1.5)

        // 2. Exact single Undo restores the initial project state COMPLETELY
        await vm.undo()
        let undone = vm.currentProject
        #expect(undone.timeline.tracks.flatMap(\.clips).isEmpty, "Single undo must restore empty timeline")
        #expect(undone.timeline.duration == 0)
        #expect(undone.timeline.tracks.count == initialTrackCount)
        #expect(undone.canvas == initialCanvas, "Single undo must restore initial canvas")
        #expect(undone.timeline.canvasSize == initialCanvasSize, "Single undo must restore initial canvas size")
        #expect(undone.mediaLibrary.assets.count == initialAssetCount, "Single undo must restore the media library")

        // 3. Exact single Redo restores the full montage (preview composition
        // rebuilds — the ramp fix must hold on the redo path too)
        await vm.redo()
        let redone = vm.currentProject
        #expect(redone.timeline.tracks.flatMap(\.clips).count == 7, "Single redo must restore all 7 clips (3 video + 4 audio)")
        #expect(redone.timeline.duration == 15.0)
        #expect(redone.canvas == .portrait9x16)
        #expect(redone.mediaLibrary.assets.count == initialAssetCount + 4, "3 photos + 1 music")

        // 4. Persistence roundtrip: project JSON serialization & bookmark retention
        let encoder = JSONEncoder()
        let projectData = try encoder.encode(vm.currentProject)
        let decoder = JSONDecoder()
        let reloadedProject = try decoder.decode(Project.self, from: projectData)
        #expect(reloadedProject.timeline.tracks.count == redone.timeline.tracks.count)
        #expect(reloadedProject.timeline.tracks.flatMap(\.clips).count == 7)
        #expect(reloadedProject.canvas == .portrait9x16)
        #expect(reloadedProject.mediaLibrary.assets.count == 4)
        for asset in reloadedProject.mediaLibrary.assets.values {
            #expect(asset.originalBookmark != nil, "Reloaded asset must retain its bookmark")
        }

        // 4.5 Storage isolation (CRASH_DIAGNOSIS_20261005 §3): BOTH autosave
        // write paths land in the injected directory, and the real app
        // container is byte-for-byte untouched.
        await vm.flushAutosave()
        let isolatedRecovery = storageRoot.appendingPathComponent("autosave/recovery.moviecut")
        #expect(FileManager.default.fileExists(atPath: isolatedRecovery.path), "recovery autosave must land in the injected directory")

        vm.saveCurrentProject()
        let isolatedAutosaveDir = storageRoot.appendingPathComponent("autosave/Autosave", isDirectory: true)
        var namedAutosaveAppeared = false
        for _ in 0..<20 where namedAutosaveAppeared == false {
            namedAutosaveAppeared = (try? FileManager.default.contentsOfDirectory(atPath: isolatedAutosaveDir.path))?
                .contains(where: { $0.hasPrefix("AIVideoTest-") }) == true
            if namedAutosaveAppeared == false {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        #expect(namedAutosaveAppeared, "named autosave must land in the injected directory (Autosave/AIVideoTest-*.moviecut)")

        let footprintAfter = ContainerStorageFootprint.capture()
        #expect(footprintAfter == footprintBefore, "the real app container must be untouched: \(footprintBefore) → \(footprintAfter)")

        // 5. Real MP4 Export (the graph-mix path — separate from preview) & decode
        let outputDir = storageRoot.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let exportURL = outputDir.appendingPathComponent("photo_video_15s.mp4")
        await vm.exportProject(to: exportURL)

        #expect(vm.lastErrorMessage == nil, "Export should succeed without error: \(vm.lastErrorMessage ?? "")")
        #expect(vm.lastExportURL != nil)
        #expect(FileManager.default.fileExists(atPath: exportURL.path))

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: exportURL.path)
        let fileSize = (fileAttributes[.size] as? NSNumber)?.int64Value ?? 0
        #expect(fileSize > 1000, "Exported MP4 must contain valid media data")

        let exportedAsset = AVAsset(url: exportURL)
        let durationSeconds: Double
        if #available(macOS 13.0, *) {
            let cmDuration = try await exportedAsset.load(.duration)
            durationSeconds = CMTimeGetSeconds(cmDuration)
            let videoTracks = try await exportedAsset.loadTracks(withMediaType: .video)
            let audioTracks = try await exportedAsset.loadTracks(withMediaType: .audio)
            #expect(!videoTracks.isEmpty, "Exported file must contain a video track")
            #expect(!audioTracks.isEmpty, "Exported file must contain an audio track")
        } else {
            durationSeconds = CMTimeGetSeconds(exportedAsset.duration)
            #expect(!exportedAsset.tracks(withMediaType: .video).isEmpty)
            #expect(!exportedAsset.tracks(withMediaType: .audio).isEmpty)
        }
        #expect(abs(durationSeconds - 15.0) < 0.2, "Exported video duration should be approximately 15.0s, got \(durationSeconds)")

        // 5a. All three photo segments are visibly distinct (each decodes and
        // differs from its neighbors — one frame at 1s proved too weak).
        let generator = AVAssetImageGenerator(asset: exportedAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        var frameBytes: [Data] = []
        for time in [2.5, 7.5, 12.5] {
            let frame = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
            #expect(frame.width > 0 && frame.height > 0)
            frameBytes.append(NSBitmapImageRep(cgImage: frame).tiffRepresentation ?? Data())
        }
        #expect(frameBytes[0] != frameBytes[1], "segments 1 and 2 must render different photos")
        #expect(frameBytes[1] != frameBytes[2], "segments 2 and 3 must render different photos")
        #expect(frameBytes[0] != frameBytes[2], "segments 1 and 3 must render different photos")

        // 5b. Music is audible through the LAST segment (audio-track presence
        // alone proved too weak) and the junction carries no excessive peak.
        let tailLevels = try await Self.decodeStats(of: exportedAsset, from: 13.0, to: 15.0)
        #expect(tailLevels != nil, "exported audio must be decodable over the final segment")
        if let tailLevels {
            #expect(tailLevels.rms > 0.001, "music must remain audible in the final segment (rms \(tailLevels.rms))")
            #expect(tailLevels.peak < 0.99, "final segment must not clip (peak \(tailLevels.peak))")
        }
        let junctionLevels = try await Self.decodeStats(of: exportedAsset, from: 3.9, to: 4.1)
        #expect(junctionLevels != nil, "exported audio must be decodable across the first loop junction")
        if let junctionLevels {
            #expect(junctionLevels.peak < 0.99, "loop junction must not clip (peak \(junctionLevels.peak))")
            #expect(junctionLevels.rms > 0.001, "loop junction must not be silent (rms \(junctionLevels.rms))")
        }

        // 5c. Junction click measurement on the RENDERED PREVIEW audio
        // (M5 2차): the export-side numbers go through AAC; this renders the
        // preview composition itself (the audioMix envelope) and bounds the
        // junction's sample-level discontinuity against a mid-chunk baseline.
        let previewAudioURL = outputDir.appendingPathComponent("preview_audio.m4a")
        try await vm.playbackEngine.renderCurrentPreviewAudio(to: previewAudioURL)
        let previewAsset = AVAsset(url: previewAudioURL)
        let junctionDelta = try await Self.decodeStats(of: previewAsset, from: 3.85, to: 4.15)?.maxDelta
        let baselineDelta = try await Self.decodeStats(of: previewAsset, from: 2.0, to: 2.3)?.maxDelta
        #expect(junctionDelta != nil, "preview audio must render and decode across the junction")
        #expect(baselineDelta != nil, "preview audio must decode mid-chunk")
        if let junctionDelta, let baselineDelta {
            // A 220 Hz sine's natural inter-sample slope at this rate is
            // ≈ amplitude×0.029; the 12 ms junction micro-fades keep the
            // splice discontinuity on that order. A butt-splice click would
            // approach full-scale. Absolute bound + relative-to-baseline
            // bound (AAC quantization gets headroom).
            #expect(junctionDelta < 0.25, "junction click detected (maxDelta \(junctionDelta))")
            #expect(junctionDelta < baselineDelta * 12, "junction is discontinuous vs baseline (\(junctionDelta) vs \(baselineDelta))")
        }

        // 5d. Preview ↔ export loudness comparison: the two engines are
        // separate implementations (audioMix envelope vs render graph) — the
        // claim verified is "comparable levels", never bit equality.
        if let previewTail = try await Self.decodeStats(of: previewAsset, from: 13.0, to: 15.0),
           let exportTail = tailLevels {
            let ratio = previewTail.rms / max(exportTail.rms, 1e-9)
            #expect(
                ratio > 0.5 && ratio < 2.0,
                "preview and export levels must be comparable over the final segment (preview rms \(previewTail.rms) vs export rms \(exportTail.rms), ratio \(ratio))"
            )
        } else {
            Issue.record("preview/export comparison windows must decode")
        }

        // 6. Save → fresh-session reopen (M3b-lite): persist the montage
        // project, load it into a NEW view model, resolve every asset's
        // bookmark, READ the media through it, and rebuild the preview
        // composition. (Process-level restart remains unverified — a test
        // host cannot relaunch itself; documented in the repair plan.)
        let savedURL = storageRoot.appendingPathComponent("saved/MontageSaved.moviecut")
        try FileManager.default.createDirectory(
            at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let store = ProjectStore(autosaveDirectory: nil)
        try await store.save(vm.currentProject, to: savedURL)
        let reopenedProject = try await store.load(from: savedURL)
        #expect(reopenedProject.timeline.tracks.flatMap(\.clips).count == 7)
        #expect(reopenedProject.canvas == .portrait9x16)

        let reopenedVM = EditorViewModel(
            project: reopenedProject,
            autosaveDirectory: storageRoot.appendingPathComponent("autosave2", isDirectory: true)
        )
        for asset in reopenedVM.currentProject.mediaLibrary.assets.values {
            try #require(asset.originalBookmark != nil, "reopened asset must retain its bookmark")
            let scopedURL = SecurityScopedAccess.beginScope(for: asset)
            defer { SecurityScopedAccess.endScope(for: scopedURL) }
            try #require(
                FileManager.default.fileExists(atPath: scopedURL.path),
                "reopened asset must resolve to an existing file: \(scopedURL.path)"
            )
            if asset.kind == .image {
                let image = NSImage(contentsOf: scopedURL)
                try #require(image != nil && image!.isValid, "reopened image must decode: \(scopedURL.path)")
            } else if asset.kind == .audio {
                let probed = AVAsset(url: scopedURL)
                let seconds: Double
                if #available(macOS 13.0, *) {
                    seconds = CMTimeGetSeconds(try await probed.load(.duration))
                } else {
                    seconds = CMTimeGetSeconds(probed.duration)
                }
                #expect(seconds.isFinite && seconds > 0, "reopened audio must decode (duration \(seconds)): \(scopedURL.path)")
            }
        }

        await MainActor.run {
            reopenedVM.rebuildPreviewComposition(preservingPlayback: false)
        }
        var reopenedReady = false
        for _ in 0..<50 where reopenedReady == false {
            reopenedReady = reopenedVM.playbackEngine.playerItem != nil
                || reopenedVM.playbackEngine.lastCompositionError != nil
            if reopenedReady == false {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        #expect(reopenedReady, "reopened preview composition must settle")
        #expect(
            reopenedVM.playbackEngine.lastCompositionError == nil,
            "reopened preview must build without error: \(reopenedVM.playbackEngine.lastCompositionError ?? "")"
        )
        #expect(reopenedVM.playbackEngine.playerItem != nil)
    }

    /// Decodes a time window of the asset's first audio track to linear PCM
    /// and returns its RMS, peak, and maximum consecutive-sample delta
    /// (linear amplitude, 0…1). maxDelta is the click detector: a butt-splice
    /// discontinuity is an order of magnitude above a 220 Hz sine's natural
    /// inter-sample slope.
    private static func decodeStats(
        of asset: AVAsset, from startSeconds: Double, to endSeconds: Double
    ) async throws -> (rms: Double, peak: Double, maxDelta: Double)? {
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        let durationSeconds = CMTimeGetSeconds(try await asset.load(.duration))
        let end = min(endSeconds, durationSeconds)
        guard end > startSeconds else { return nil }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: end - startSeconds, preferredTimescale: 600)
        )
        guard reader.startReading() else {
            return nil
        }

        var squaredSum: Double = 0
        var sampleCount: Double = 0
        var peak: Double = 0
        var maxDelta: Double = 0
        var previous: Double?
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            let copied = data.withUnsafeMutableBytes { buffer -> OSStatus in
                guard let base = buffer.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
            }
            guard copied == kCMBlockBufferNoErr else { continue }
            for index in stride(from: 0, to: length - 1, by: 2) {
                let raw = Int16(littleEndian: data[index...].withUnsafeBytes { $0.load(as: Int16.self) })
                let amplitude = Double(raw) / 32768.0
                squaredSum += amplitude * amplitude
                sampleCount += 1
                peak = max(peak, abs(amplitude))
                if let previous {
                    maxDelta = max(maxDelta, abs(amplitude - previous))
                }
                previous = amplitude
            }
        }
        guard sampleCount > 0, reader.status == .completed || reader.status == .reading else {
            return nil
        }
        return (rms: (squaredSum / sampleCount).squareRoot(), peak: peak, maxDelta: maxDelta)
    }
}
