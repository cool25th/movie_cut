import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

#if canImport(Vision)
/// T2-M — Motion Tracking Analysis performance (validation doc §3.2).
///
/// Opt-in: only runs with `MOVIECUT_T2M=1` (use scripts/run_t2m_motion_tracking.sh,
/// which pins the Release configuration and records the host environment the
/// measurement protocol requires). Repeats real Vision analysis N times
/// (`MOVIECUT_T2M_REPEATS`, default 5) and reports per-run and aggregate
/// metrics as machine-parseable `T2M_RUN` / `T2M_AGG` lines:
///
/// RTF (analysis time / media duration), total wall time, per-frame p50/p95/p99
/// (Vision+decode, seed frame excluded as warm-up), sample count, mean/median/
/// p10/min/final IoU vs the analytic ground truth, failure rate (lost
/// observation + decode failure), max consecutive failures, and physical
/// footprint peak/delta sampled on a 50ms monitor.
///
/// Occlusion-reacquisition is N/A on this fixture (the subject is never
/// occluded); it needs a dedicated fixture (follow-up).
@Suite("Motion Tracking Analysis Perf (T2-M)")
struct MotionTrackingAnalysisPerfTests {
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["MOVIECUT_T2M"] == "1",
        "opt-in: MOVIECUT_T2M=1 via scripts/run_t2m_motion_tracking.sh"
    ))
    func movingSubjectAnalysisMetrics() async throws {
        let environment = ProcessInfo.processInfo.environment
        let repeats = Int(environment["MOVIECUT_T2M_REPEATS"] ?? "") ?? 5
        let mediaDuration = 2.0
        let sampleRate = 15.0

        struct RunMetrics {
            var rtf = 0.0
            var totalMs = 0.0
            var p50Ms = 0.0
            var p95Ms = 0.0
            var p99Ms = 0.0
            var samples = 0
            var frames = 0
            var tracked = 0
            var lost = 0
            var decodeFailed = 0
            var failRate = 0.0
            var maxConsecutiveFailures = 0
            var iouMean = 0.0
            var iouMedian = 0.0
            var iouP10 = 0.0
            var iouMin = 0.0
            var iouFinal = 0.0
            var peakFootprintMb = 0.0
            var footprintDeltaMb = 0.0
        }

        var runs: [RunMetrics] = []

        for run in 1...max(repeats, 1) {
            MotionTrackingAnalysisProbe.arm()

            let footprintStart = Self.physFootprintBytes()
            let monitor = Task { () -> Int64 in
                var peak = footprintStart
                while !Task.isCancelled {
                    peak = max(peak, Self.physFootprintBytes())
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                return peak
            }

            let start = ContinuousClock.now
            let provider = MotionTrackingProvider()
            let results = try await provider.track(
                videoURL: MediaFixtures.movingSubjectVideo,
                initialRect: MotionTrackingGroundTruth.expectedMovingSubjectRect(at: 0),
                timeRange: TimeRange(start: 0, duration: mediaDuration),
                frameRate: sampleRate
            )
            let elapsed = start.duration(to: .now)
            // Cancel the monitor BEFORE awaiting its value — the task only
            // returns once cancelled, so awaiting first would deadlock.
            monitor.cancel()
            let peakFootprint = await monitor.value
            let frames = MotionTrackingAnalysisProbe.takeAndReset() ?? []

            var metrics = RunMetrics()
            metrics.totalMs = Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15
            metrics.rtf = metrics.totalMs / 1000 / mediaDuration
            metrics.samples = results.count
            metrics.frames = frames.count
            metrics.tracked = frames.filter { $0.status == .tracked }.count
            metrics.lost = frames.filter { $0.status == .lostObservation }.count
            metrics.decodeFailed = frames.filter { $0.status == .decodeFailure }.count
            metrics.failRate = frames.isEmpty
                ? 1.0
                : Double(metrics.lost + metrics.decodeFailed) / Double(frames.count)

            var consecutive = 0
            for frame in frames {
                if frame.status == .tracked || frame.status == .seed {
                    consecutive = 0
                } else {
                    consecutive += 1
                    metrics.maxConsecutiveFailures = max(metrics.maxConsecutiveFailures, consecutive)
                }
            }

            // Per-frame percentiles over tracked frames; the seed frame is the
            // warm-up sample (first-decode cost) and is excluded, matching
            // CompositorRenderProbe's first_ms policy.
            let trackedDurations = frames
                .filter { $0.status == .tracked }
                .map(\.durationMs)
                .sorted()
            if !trackedDurations.isEmpty {
                func percentile(_ p: Double) -> Double {
                    let index = min(Int((p / 100) * Double(trackedDurations.count - 1)), trackedDurations.count - 1)
                    return trackedDurations[index]
                }
                metrics.p50Ms = percentile(50)
                metrics.p95Ms = percentile(95)
                metrics.p99Ms = percentile(99)
            }

            let ious = results
                .map { MotionTrackingGroundTruth.iou($0.rect, MotionTrackingGroundTruth.expectedMovingSubjectRect(at: $0.timestamp)) }
                .sorted()
            if !ious.isEmpty {
                metrics.iouMin = ious.first ?? 0
                metrics.iouMedian = ious[ious.count / 2]
                metrics.iouP10 = ious[min(ious.count / 10, ious.count - 1)]
                metrics.iouMean = ious.reduce(0, +) / Double(ious.count)
                metrics.iouFinal = MotionTrackingGroundTruth.iou(
                    results[results.count - 1].rect,
                    MotionTrackingGroundTruth.expectedMovingSubjectRect(at: results[results.count - 1].timestamp)
                )
            }

            metrics.peakFootprintMb = Double(peakFootprint) / 1_048_576
            metrics.footprintDeltaMb = Double(peakFootprint - footprintStart) / 1_048_576

            runs.append(metrics)
            print(String(
                format: "T2M_RUN i=%d rtf=%.4f total_ms=%.1f frames=%d tracked=%d lost=%d decode_failed=%d p50_ms=%.2f p95_ms=%.2f p99_ms=%.2f iou_mean=%.4f iou_median=%.4f iou_p10=%.4f iou_min=%.4f iou_final=%.4f fail_rate=%.4f max_consec_fail=%d samples=%d peak_footprint_mb=%.1f footprint_delta_mb=%.1f",
                run, metrics.rtf, metrics.totalMs, metrics.frames, metrics.tracked, metrics.lost,
                metrics.decodeFailed, metrics.p50Ms, metrics.p95Ms, metrics.p99Ms,
                metrics.iouMean, metrics.iouMedian, metrics.iouP10, metrics.iouMin, metrics.iouFinal,
                metrics.failRate, metrics.maxConsecutiveFailures, metrics.samples,
                metrics.peakFootprintMb, metrics.footprintDeltaMb
            ))
        }

        func mean(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        func stddev(_ values: [Double]) -> Double {
            guard values.count > 1 else { return 0 }
            let avg = mean(values)
            return (values.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / Double(values.count - 1)).squareRoot()
        }
        print(String(
            format: "T2M_AGG repeats=%d fixture=moving_subject_320x240_2s_30fps.mp4 sample_rate=%.0f rtf_mean=%.4f rtf_stddev=%.4f p50_ms_mean=%.2f p95_ms_mean=%.2f iou_mean_avg=%.4f iou_min_min=%.4f fail_rate_max=%.4f peak_footprint_mb_max=%.1f",
            runs.count, sampleRate,
            mean(runs.map(\.rtf)), stddev(runs.map(\.rtf)),
            mean(runs.map(\.p50Ms)), mean(runs.map(\.p95Ms)),
            mean(runs.map(\.iouMean)), runs.map(\.iouMin).min() ?? 0,
            runs.map(\.failRate).max() ?? 1,
            runs.map(\.peakFootprintMb).max() ?? 0
        ))

        // The measurement itself must stay sane: tracking must complete well
        // under real time on a supported host and follow the subject.
        #expect(runs.allSatisfy { $0.rtf < 1.0 }, "analysis slower than real time")
        #expect(runs.allSatisfy { $0.samples >= 25 }, "too few samples for the fixture")
        #expect(runs.allSatisfy { $0.iouMean >= 0.75 }, "mean IoU below the integration-test floor")
    }

    /// Physical footprint of this process in bytes (task_vm_info), the same
    /// metric Memory graph / Instruments footprint uses.
    private static func physFootprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.phys_footprint)
    }
}
#endif
