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

    /// Stages a repo fixture into Application Support — grant-free under App
    /// Sandbox, unlike the repository tree (task-511.log recorded sandbox
    /// read denials for repo paths). Every failure carries BOTH URLs so a
    /// permission denial is attributable to a concrete path. Entitlements
    /// are not broadened for tests.
    private static func stagedFixture(_ name: String) throws -> URL {
        let source = repoRoot.appendingPathComponent("Tests/Fixtures/\(name)")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw FixtureStagingError.missingSource(source)
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let stagingDir = support.appendingPathComponent("AIMontageE2EFixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let destination = stagingDir.appendingPathComponent(name)
        do {
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        } catch {
            throw FixtureStagingError.copyFailed(source: source, destination: destination, underlying: error.localizedDescription)
        }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw FixtureStagingError.copyFailed(source: source, destination: destination, underlying: "destination missing after copy")
        }
        return destination
    }

    @Test("Photos + Audio -> 15s Timeline Creation -> Undo/Redo -> Real MP4 Export")
    func photoMontageCreationAndExportEndToEnd() async throws {
        let photo1 = try Self.stagedFixture("swatch_blue_64x64.png")
        let photo2 = try Self.stagedFixture("swatch_green_64x64.heic")
        let photo3 = try Self.stagedFixture("exif_orient6_asym_320x240.jpg")
        let music = try Self.stagedFixture("duck_bgm_220hz_4s_mono.wav")

        let vm = EditorViewModel(project: Project(name: "AIVideoTest"))

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
        #expect(videoTracks.count == 1)
        let videoClips = videoTracks[0].clips
        try #require(videoClips.count == 3, "expected 3 photo clips, got \(videoClips.count)")

        for clip in videoClips {
            #expect(clip.timelineRange.duration == 5.0)
            #expect(!clip.keyframes.isEmpty)
        }

        // Audio: 4s music loops 4+4+4+3=15s
        let audioTracks = vm.currentProject.timeline.tracks.filter { $0.kind == .audio }
        #expect(audioTracks.count == 1)
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

        // 5. Real MP4 Export (the graph-mix path — separate from preview) & decode
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("ai_creation_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

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
        let tailLevels = try await Self.decodeLevels(of: exportedAsset, from: 13.0, to: 15.0)
        #expect(tailLevels != nil, "exported audio must be decodable over the final segment")
        if let tailLevels {
            #expect(tailLevels.rms > 0.001, "music must remain audible in the final segment (rms \(tailLevels.rms))")
            #expect(tailLevels.peak < 0.99, "final segment must not clip (peak \(tailLevels.peak))")
        }
        let junctionLevels = try await Self.decodeLevels(of: exportedAsset, from: 3.9, to: 4.1)
        #expect(junctionLevels != nil, "exported audio must be decodable across the first loop junction")
        if let junctionLevels {
            #expect(junctionLevels.peak < 0.99, "loop junction must not clip (peak \(junctionLevels.peak))")
            #expect(junctionLevels.rms > 0.001, "loop junction must not be silent (rms \(junctionLevels.rms))")
        }
    }

    /// Decodes a time window of the asset's first audio track to linear PCM
    /// and returns its RMS and peak (linear amplitude, 0…1).
    private static func decodeLevels(
        of asset: AVAsset, from startSeconds: Double, to endSeconds: Double
    ) async throws -> (rms: Double, peak: Double)? {
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
            }
        }
        guard sampleCount > 0, reader.status == .completed || reader.status == .reading else {
            return nil
        }
        return (rms: (squaredSum / sampleCount).squareRoot(), peak: peak)
    }
}
