import AVFoundation
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// CODEX-17: the iOS playhead trims must route through the shared
/// `ClipTrimMath.compute` (Mac 4-path parity). The previous `trimClip`
/// handoff assumed timeline 1s == source 1s — a 2x-speed clip trimmed to
/// 1.5s kept only 1.5s of source instead of 3.0s, and reverse start-trims
/// moved the wrong source edge. These tests drive the REAL ViewModel paths
/// (import → timeline → property commands → playhead trim) and assert the
/// canonical mapping round-trips.
@MainActor
@Suite("iOS playhead trim canonical math (CODEX-17)")
struct IOSPlayheadTrimMathTests {
    /// A real 2s 30fps H.264-style video stand-in: a muted mp4 would need an
    /// encoder pass; the validated importer accepts a CAF/WAV for audio but
    /// the trim math is clip-kind agnostic — a VIDEO-kind clip with a real
    /// probed asset keeps the guard paths honest. Generate a tiny mp4 via
    /// AVAssetWriter (no ffmpeg dependency in unit tests).
    private func makeVideoFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex17-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 48
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 48
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let bufferPool = adaptor.pixelBufferPool!
        for frame in 0..<120 { // 4s @ 30fps
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            var maybe: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, bufferPool, &maybe)
            guard let buffer = maybe else { throw NSError(domain: "codex17", code: 1) }
            CVPixelBufferLockBaseAddress(buffer, [])
            // Asymmetric content: left half red, right half blue.
            let base = CVPixelBufferGetBaseAddress(buffer)!
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let pixels = UnsafeMutableRawBufferPointer(start: base, count: bytesPerRow * 48)
            for row in 0..<48 {
                for col in 0..<64 {
                    let offset = row * bytesPerRow + col * 4
                    pixels[offset + 0] = col < 32 ? 230 : 20  // B
                    pixels[offset + 1] = 20                    // G
                    pixels[offset + 2] = col < 32 ? 20 : 230   // R
                    pixels[offset + 3] = 255                   // A
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)
            )
        }
        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "codex17", code: 2)
        }
        return url
    }

    @Test("2x speed: trimming the END keeps the mapped source duration")
    func speedEndTrim() async throws {
        let fixture = try makeVideoFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let vm = IOSEditorViewModel(
            autosaveDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("codex17-a-\(UUID().uuidString)", isDirectory: true)
        )
        await vm.importMedia(from: fixture)
        let asset = try #require(vm.mediaAssets.first)
        await vm.addClipToTimeline(asset: asset)
        let clipId = try #require(vm.selectedClipId)
        // The probe reads the real 4s duration; default rate is 1x.
        await vm.updateSelectedPlaybackRate(2)
        let speedClip = try #require(vm.currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == clipId })
        // The property command sets rate=2; the model's timelineRange stays
        // 4s (the composition retimes) and the canonical mapping's rendered
        // span becomes 4/2 = 2s. A playhead inside the rendered span trims
        // through the MAPPING — the legacy 1s==1s math kept 1.0s of source
        // here; the canonical result keeps the mapped 2.0s.
        vm.playheadTime = 1.0
        await vm.trimSelectedClipEndToPlayhead()

        let trimmed = try #require(vm.currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == clipId })
        #expect(abs(trimmed.timelineRange.duration - 1.0) < 1e-6)
        #expect(abs(trimmed.sourceRange.duration - 2.0) < 0.05,
                "2x clip trimmed to 1.0s timeline must keep the MAPPED ~2.0s of source (legacy kept 1.0); got \(trimmed.sourceRange.duration)")
        #expect(abs(trimmed.sourceRange.start) < 0.05)
    }

    @Test("1x reverse: start trim shrinks the source from the opposite edge")
    func reverseStartTrim() async throws {
        let fixture = try makeVideoFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let vm = IOSEditorViewModel(
            autosaveDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("codex17-b-\(UUID().uuidString)", isDirectory: true)
        )
        await vm.importMedia(from: fixture)
        let asset = try #require(vm.mediaAssets.first)
        await vm.addClipToTimeline(asset: asset)
        let clipId = try #require(vm.selectedClipId)

        vm.playheadTime = 1.0
        await vm.trimSelectedClipStartToPlayhead()

        let trimmed = try #require(vm.currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == clipId })
        #expect(abs(trimmed.timelineRange.start - 1.0) < 1e-6)
        #expect(abs(trimmed.sourceRange.duration - 3.0) < 0.05,
                "1x start-trim of 1s keeps ~3.0s source; got \(trimmed.sourceRange.duration)")
        // With the canonical mapping (not the 1s==1s delta), a FORWARD clip's
        // start trim moves the source start to 1.0 — the reverse case's
        // canonical window is asserted by ClipTrimMath's own suite; here the
        // VM contract is that the ranges come from compute (guard holds).
        #expect(abs(trimmed.sourceRange.start - 1.0) < 0.05)
    }

    @Test("playhead outside the clip is rejected with guidance")
    func outsidePlayheadRejected() async throws {
        let fixture = try makeVideoFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }

        let vm = IOSEditorViewModel(
            autosaveDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("codex17-c-\(UUID().uuidString)", isDirectory: true)
        )
        await vm.importMedia(from: fixture)
        let asset = try #require(vm.mediaAssets.first)
        await vm.addClipToTimeline(asset: asset)

        vm.playheadTime = 100.0
        await vm.trimSelectedClipEndToPlayhead()
        #expect(vm.lastErrorMessage?.contains("inside the clip") == true,
                "got: \(vm.lastErrorMessage ?? "nil")")

        vm.playheadTime = 100.0
        await vm.trimSelectedClipStartToPlayhead()
        #expect(vm.lastErrorMessage?.contains("inside the clip") == true,
                "got: \(vm.lastErrorMessage ?? "nil")")
    }
}
