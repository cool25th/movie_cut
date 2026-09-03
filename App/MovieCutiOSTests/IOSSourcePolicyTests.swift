import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// capcut-surpass stage-4: the render plan's SOURCE POLICY — the editing
/// preview may read a generated proxy (the user's explicit preference or the
/// thermal safety net), while exports ALWAYS read originals so a master never
/// bakes the proxy's downscale artifacts in. Mirrors Mac's
/// `PlaybackEngine.playbackURL(for:)` decision; the resolution (settings +
/// `ProxyDowngradePolicy`) lives with the CALLER, so the plan itself stays
/// settings-free and testable.
@MainActor
@Suite("iOS render plan source policy (stage-4)")
struct IOSSourcePolicyTests {
    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root

    /// The ORIGINAL: real red fixture (2s).
    private static let originalURL: URL = repoRoot
        .appendingPathComponent("Tests/Fixtures/solid_red_320x240_2s_30fps.mp4")

    /// A real SOLID BLUE video standing in for a generated proxy — a
    /// different color than the original so the behavioral export test can
    /// tell which source was read from the decoded frame.
    private func makeSolidBlueProxyStandIn() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("srcpolicy-\(UUID().uuidString).mov")
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
        for frame in 0..<60 { // 2s @ 30fps
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            var maybe: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, bufferPool, &maybe)
            guard let buffer = maybe else { throw NSError(domain: "srcpolicy", code: 1) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = CVPixelBufferGetBaseAddress(buffer)!
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let pixels = UnsafeMutableRawBufferPointer(start: base, count: bytesPerRow * 48)
            for offset in stride(from: 0, to: bytesPerRow * 48, by: 4) {
                pixels[offset + 0] = 235  // B
                pixels[offset + 1] = 30   // G
                pixels[offset + 2] = 30   // R
                pixels[offset + 3] = 255  // A
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
            throw writer.error ?? NSError(domain: "srcpolicy", code: 2)
        }
        return url
    }

    /// A one-video-clip project whose asset carries a proxy pointing at
    /// `proxyURL` (the plan only needs a readable media file there).
    private func project(proxyURL: URL) -> Project {
        var asset = MediaAsset(
            originalURL: Self.originalURL,
            kind: .video,
            duration: 2.0
        )
        asset.proxy = ProxyInfo(
            proxyURL: proxyURL,
            resolution: CGSize(width: 64, height: 48)
        )
        var project = Project(name: "source-policy")
        project.mediaLibrary.assets[asset.id] = asset
        var track = Track(kind: .video, name: "V", zIndex: 0)
        track.clips = [
            Clip(
                assetId: asset.id,
                kind: .video,
                sourceRange: TimeRange(start: 0, duration: 2.0),
                timelineRange: TimeRange(start: 0, duration: 2.0)
            )
        ]
        project.timeline.tracks = [track]
        return project
    }

    private func videoSegmentSources(_ plan: IOSExportEngine.IOSRenderPlan) -> [String] {
        plan.composition
            .tracks(withMediaType: .video)
            .flatMap(\.segments)
            .compactMap(\.sourceURL)
            .map(\.absoluteString)
    }

    @Test("preview policy (.proxyWhenAvailable) reads the asset's proxy")
    func previewPolicyReadsProxy() async throws {
        let proxy = try makeSolidBlueProxyStandIn()
        defer { try? FileManager.default.removeItem(at: proxy) }
        let engine = IOSExportEngine()
        let plan = try await engine.makeRenderPlan(
            for: project(proxyURL: proxy),
            sourcePolicy: .proxyWhenAvailable
        )
        let sources = videoSegmentSources(plan)
        #expect(!sources.isEmpty, "the clip must have inserted real segments")
        #expect(sources.allSatisfy { $0 == proxy.absoluteString },
                "every video segment must reference the proxy, got \(sources)")
    }

    @Test("default plan (export/harness mode) reads the original despite the proxy")
    func defaultPolicyReadsOriginal() async throws {
        let proxy = try makeSolidBlueProxyStandIn()
        defer { try? FileManager.default.removeItem(at: proxy) }
        let engine = IOSExportEngine()
        // No explicit policy: existing callers (export, harness) keep the
        // original-only contract by default.
        let plan = try await engine.makeRenderPlan(for: project(proxyURL: proxy))
        let sources = videoSegmentSources(plan)
        #expect(!sources.isEmpty)
        #expect(sources.allSatisfy { $0 == Self.originalURL.absoluteString },
                "the default policy must read the original, got \(sources)")
    }

    @Test("export reads the ORIGINAL even when a proxy exists (behavioral)")
    func exportAlwaysReadsOriginal() async throws {
        let proxy = try makeSolidBlueProxyStandIn()
        defer { try? FileManager.default.removeItem(at: proxy) }
        let engine = IOSExportEngine()
        let exportedURL = try await engine.exportProject(project(proxyURL: proxy))
        defer { try? FileManager.default.removeItem(at: exportedURL) }

        // Decode a mid-frame: the original is solid RED, the proxy stand-in
        // is solid BLUE — the delivery must be red-dominant.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: exportedURL))
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        let image = try generator.copyCGImage(at: time, actualTime: nil)
        let width = min(16, image.width)
        let height = min(16, image.height)
        var red = 0
        var blue = 0
        // Draw into a known RGBA layout and count dominant channels.
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try #require(context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4))
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = pixels[offset]
                let b = pixels[offset + 2]
                if r > 120 && Int(r) > Int(b) * 2 { red += 1 }
                if b > 120 && Int(b) > Int(r) * 2 { blue += 1 }
            }
        }
        #expect(red > width * height / 2,
                "the export must decode as the RED original (red=\(red) blue=\(blue))")
        #expect(blue < width * height / 10,
                "a blue-dominant frame means the export read the PROXY (red=\(red) blue=\(blue))")
    }

    @Test("preview policy resolution: user preference or thermal safety net (Core parity)")
    func previewPolicyResolutionTable() {
        // The view resolves useProxy = useProxyPlayback ||
        // ProxyDowngradePolicy.shouldAutoDowngrade(...) — pin the table the
        // SwiftUI layer consumes (the view wiring itself is the usual
        // unit-untestable SwiftUI surface, STAB-03 precedent).
        #expect(!ProxyDowngradePolicy.shouldAutoDowngrade(thermalState: .nominal, autoProxyOnThermalPressure: true))
        #expect(!ProxyDowngradePolicy.shouldAutoDowngrade(thermalState: .fair, autoProxyOnThermalPressure: true))
        #expect(ProxyDowngradePolicy.shouldAutoDowngrade(thermalState: .serious, autoProxyOnThermalPressure: true))
        #expect(ProxyDowngradePolicy.shouldAutoDowngrade(thermalState: .critical, autoProxyOnThermalPressure: true))
        // The user can refuse the safety net.
        #expect(!ProxyDowngradePolicy.shouldAutoDowngrade(thermalState: .critical, autoProxyOnThermalPressure: false))
    }
}
