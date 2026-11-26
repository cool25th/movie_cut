import Foundation
import AVFoundation
import CoreImage
import os

private struct SceneChangeConfiguration: Sendable {
    var samplingFPS: Double
    var changeThreshold: Float
}

/// Detects scene changes in a video asset by comparing consecutive frames.
public final class SceneChangeProvider: AnalysisProvider {
    private let configuration: OSAllocatedUnfairLock<SceneChangeConfiguration>
    // CIContext is documented thread-safe but is not declared Sendable on the
    // macOS 15 SDK (it is on later SDKs), which strict-concurrency=complete
    // rejects for a stored property of a Sendable-conforming class. The same
    // `nonisolated(unsafe)` annotation the test harness uses for its shared
    // CIContext; the reference is immutable so this is sound.
    nonisolated(unsafe) private let context = CIContext(options: RenderColorConfiguration.contextOptions)

    /// User-visible provider name used consistently in provider lists and analysis results.
    public let providerName = "SceneChange"

    /// Frames per second to sample for comparison (default: 2).
    public var samplingFPS: Double {
        get {
            configuration.withLock { $0.samplingFPS }
        }
        set {
            configuration.withLock { $0.samplingFPS = newValue }
        }
    }

    /// Difference ratio threshold for scene change (0.0–1.0, default: 0.3).
    public var changeThreshold: Float {
        get {
            configuration.withLock { $0.changeThreshold }
        }
        set {
            configuration.withLock { $0.changeThreshold = newValue }
        }
    }

    /// Creates a scene change detection provider.
    public init(
        samplingFPS: Double = 2.0,
        changeThreshold: Float = 0.3
    ) {
        self.configuration = OSAllocatedUnfairLock(initialState: SceneChangeConfiguration(
            samplingFPS: samplingFPS,
            changeThreshold: changeThreshold
        ))
    }

    /// Analyzes the asset video track and returns scene-change timestamps.
    public func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult {
        let url = asset.originalURL
        let avAsset = AVAsset(url: url)

        let changeTimes = try await detectSceneChanges(in: avAsset)

        let suggestions: [AnalysisSuggestion]
        if changeTimes.isEmpty {
            suggestions = []
        } else {
            suggestions = [.sceneChanges(times: changeTimes)]
        }

        return AnalysisResult(
            suggestions: suggestions,
            sourceAssetID: asset.id.uuidString,
            providerName: providerName
        )
    }

    // MARK: - Private

    private func detectSceneChanges(in avAsset: AVAsset) async throws -> [TimeInterval] {
        let duration = try await avAsset.load(.duration)
        guard duration.isValid && duration.seconds > 0 else { return [] }

        let tracks = try await avAsset.load(.tracks)
        let videoTracks = tracks.filter { $0.mediaType == .video }
        guard !videoTracks.isEmpty else { return [] }

        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true

        let totalDuration = duration.seconds
        let configuration = configuration.withLock { $0 }
        let interval = 1.0 / configuration.samplingFPS
        var times: [NSValue] = []
        var t = interval
        while t < totalDuration {
            times.append(NSValue(time: CMTime(seconds: t, preferredTimescale: 600)))
            t += interval
        }

        guard !times.isEmpty else { return [] }

        var changeTimes: [TimeInterval] = []
        var previousHistogram: [Float]?

        for timeValue in times {
            let cmTime = timeValue.timeValue

            guard let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) else {
                continue
            }

            let ciImage = CIImage(cgImage: cgImage)
            let histogram = computeHistogram(for: ciImage)

            if let prev = previousHistogram {
                let difference = histogramDifference(prev, histogram)
                if difference > configuration.changeThreshold {
                    changeTimes.append(cmTime.seconds)
                }
            }

            previousHistogram = histogram
        }

        return changeTimes
    }

    /// Computes a 64-bin luminance histogram for an image.
    ///
    /// CA-21 measurement (2026-09-04) found the previous implementation —
    /// CIAreaHistogram rendered to an RGBA8 bitmap — returned ALL ZEROS for
    /// every frame (the filter's output extent/scale does not line up with
    /// the 64×1 region read here), so the chi-squared difference was always
    /// 0 and the provider NEVER detected a scene change. This counts the
    /// histogram directly from rendered pixels instead: no CIFilter
    /// coordinate semantics to drift, and the math is unit-testable.
    func computeHistogram(for image: CIImage) -> [Float] {
        // Downscale for histogram purposes (shape is scale-invariant) so
        // 4K frames don't pay full-resolution pixel walks at the sampling
        // rate.
        let maxDim = max(image.extent.width, image.extent.height)
        var working = image
        if maxDim > 256, maxDim.isFinite, maxDim > 0 {
            let scale = 256 / maxDim
            working = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let width = Int(working.extent.width.rounded())
        let height = Int(working.extent.height.rounded())
        guard width > 0, height > 0 else { return [Float](repeating: 0, count: 64) }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            working,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        var histogram = [Float](repeating: 0, count: 64)
        let totalPixels = Float(width * height)
        for i in 0..<(width * height) {
            let r = Float(pixels[i * 4])
            let g = Float(pixels[i * 4 + 1])
            let b = Float(pixels[i * 4 + 2])
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            let bin = min(63, Int(luminance / 4))
            histogram[bin] += 1
        }
        for i in 0..<64 {
            histogram[i] /= totalPixels
        }
        return histogram
    }

    /// Computes chi-squared difference between two histograms.
    func histogramDifference(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 1.0 }

        var difference: Float = 0
        for i in 0..<a.count {
            let sum = a[i] + b[i]
            if sum > 0 {
                let diff = a[i] - b[i]
                difference += (diff * diff) / sum
            }
        }

        return difference * 0.5
    }
}
