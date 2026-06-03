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
    private let context = CIContext()

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
            providerName: "SceneChange"
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
    private func computeHistogram(for image: CIImage) -> [Float] {
        let filter = CIFilter(name: "CIAreaHistogram", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: image.extent),
            "inputCount": 64
        ])!

        guard let outputImage = filter.outputImage else {
            return [Float](repeating: 0, count: 64)
        }

        // Read histogram data
        let bitmap = [UInt8](repeating: 0, count: 256) // 64 bins * 4 bytes
        var mutableBitmap = bitmap
        context.render(
            outputImage,
            toBitmap: &mutableBitmap,
            rowBytes: 256,
            bounds: CGRect(x: 0, y: 0, width: 64, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        // Use luminance channel (average of R, G, B for each bin)
        var histogram = [Float](repeating: 0, count: 64)
        let totalPixels = Float(image.extent.width * image.extent.height)
        guard totalPixels > 0 else { return histogram }

        for i in 0..<64 {
            let r = Float(mutableBitmap[i * 4])
            let g = Float(mutableBitmap[i * 4 + 1])
            let b = Float(mutableBitmap[i * 4 + 2])
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            histogram[i] = luminance / totalPixels
        }

        return histogram
    }

    /// Computes chi-squared difference between two histograms.
    private func histogramDifference(_ a: [Float], _ b: [Float]) -> Float {
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
