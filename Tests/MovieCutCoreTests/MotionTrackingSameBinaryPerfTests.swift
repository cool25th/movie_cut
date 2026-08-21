import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

#if canImport(Vision)
import Vision

@Suite("Motion Tracking same-binary perf probe", .serialized)
struct MotionTrackingSameBinaryPerfTests {
    private struct Metrics {
        var rtf: Double
        var p95Ms: Double
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["MOVIECUT_T2M_AB"] == "1",
        "opt-in same-binary T2-M comparison"
    ))
    func legacyVersusRecoveryPath() async throws {
        let url = MediaFixtures.movingSubjectVideo
        let initialRect = MotionTrackingGroundTruth.expectedMovingSubjectRect(at: 0)

        // Warm both implementations before measuring so Vision/framework
        // one-time initialization is not attributed to either path.
        _ = try await runLegacy(url: url, initialRect: initialRect)
        _ = try await runRecovery(url: url, initialRect: initialRect)

        var legacy: [Metrics] = []
        var recovery: [Metrics] = []
        // Balanced order controls linear host drift while both paths execute in
        // one process and one already-built test binary.
        for label in ["L", "R", "R", "L", "R", "L", "L", "R"] {
            if label == "L" {
                legacy.append(try await runLegacy(url: url, initialRect: initialRect))
            } else {
                recovery.append(try await runRecovery(url: url, initialRect: initialRect))
            }
        }

        func mean(_ values: [Double]) -> Double {
            values.reduce(0, +) / Double(values.count)
        }
        let legacyRTF = mean(legacy.map(\.rtf))
        let recoveryRTF = mean(recovery.map(\.rtf))
        let legacyP95 = mean(legacy.map(\.p95Ms))
        let recoveryP95 = mean(recovery.map(\.p95Ms))
        let rtfDelta = ((recoveryRTF / legacyRTF) - 1) * 100
        let p95Delta = ((recoveryP95 / legacyP95) - 1) * 100

        print(String(
            format: "T2M_SAME_BINARY legacy_rtf=%.4f recovery_rtf=%.4f rtf_delta_pct=%+.2f legacy_p95_ms=%.2f recovery_p95_ms=%.2f p95_delta_pct=%+.2f",
            legacyRTF, recoveryRTF, rtfDelta, legacyP95, recoveryP95, p95Delta
        ))
        for (index, metrics) in legacy.enumerated() {
            print(String(format: "T2M_SAME_BINARY_RUN role=legacy i=%d rtf=%.4f p95_ms=%.2f", index + 1, metrics.rtf, metrics.p95Ms))
        }
        for (index, metrics) in recovery.enumerated() {
            print(String(format: "T2M_SAME_BINARY_RUN role=recovery i=%d rtf=%.4f p95_ms=%.2f", index + 1, metrics.rtf, metrics.p95Ms))
        }
    }

    private func runRecovery(url: URL, initialRect: CGRect) async throws -> Metrics {
        MotionTrackingAnalysisProbe.arm()
        let start = ContinuousClock.now
        _ = try await MotionTrackingProvider().track(
            videoURL: url,
            initialRect: initialRect,
            timeRange: TimeRange(start: 0, duration: 2.0),
            frameRate: 15.0
        )
        let totalMs = elapsedMs(start)
        let frames = MotionTrackingAnalysisProbe.takeAndReset() ?? []
        let durations = frames
            .filter { $0.status == .tracked || $0.status == .reacquired }
            .map(\.durationMs)
            .sorted()
        return Metrics(rtf: totalMs / 2_000, p95Ms: percentile95(durations))
    }

    private func runLegacy(url: URL, initialRect: CGRect) async throws -> Metrics {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        guard tracks.contains(where: { $0.mediaType == .video }) else {
            throw MotionTrackingError.videoTrackUnavailable
        }

        let endTime = min(2.0, duration.seconds)
        let frameDuration = 1.0 / 15.0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let request = VNTrackObjectRequest(
            detectedObjectObservation: VNDetectedObjectObservation(
                boundingBox: MotionTrackingProvider.visionBoundingBox(fromDisplayRect: initialRect)
            )
        )
        request.trackingLevel = .accurate
        let sequenceHandler = VNSequenceRequestHandler()

        var time = 0.0
        var didSeed = false
        var durations: [Double] = []
        let totalStart = ContinuousClock.now

        while time <= endTime + (frameDuration * 0.5) {
            let frameStart = DispatchTime.now()
            var actualTime = CMTime.invalid
            let requestedTime = CMTime(seconds: time, preferredTimescale: 600)
            guard let image = try? generator.copyCGImage(at: requestedTime, actualTime: &actualTime) else {
                time += frameDuration
                continue
            }

            if !didSeed {
                didSeed = true
                time += frameDuration
                continue
            }

            try sequenceHandler.perform([request], on: image)
            guard let observation = request.results?.first as? VNDetectedObjectObservation,
                  MotionTrackingProvider.clampedNormalizedRect(
                    MotionTrackingProvider.displayRect(fromVisionBoundingBox: observation.boundingBox)
                  ) != nil
            else {
                time += frameDuration
                continue
            }
            request.inputObservation = observation
            let nanos = DispatchTime.now().uptimeNanoseconds - frameStart.uptimeNanoseconds
            durations.append(Double(nanos) / 1_000_000)
            time += frameDuration
        }

        return Metrics(rtf: elapsedMs(totalStart) / 2_000, p95Ms: percentile95(durations.sorted()))
    }

    private func elapsedMs(_ start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1e15
    }

    private func percentile95(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(Int(0.95 * Double(sorted.count - 1)), sorted.count - 1)
        return sorted[index]
    }
}
#endif
