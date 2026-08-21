import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

@Suite("Motion Tracking Provider")
struct MotionTrackingProviderTests {
    @Test("normalized rect clamps to the unit square")
    func normalizedRectClampsToUnitSquare() throws {
        let rect = try #require(MotionTrackingProvider.clampedNormalizedRect(
            CGRect(x: -0.1, y: 0.2, width: 0.5, height: 1.2)
        ))

        #expect(rect.minX == 0)
        #expect(rect.minY == 0.2)
        #expect(rect.maxX == 0.4)
        #expect(rect.maxY == 1)
    }

    @Test("empty or non-finite rects are rejected")
    func invalidRectsAreRejected() {
        #expect(MotionTrackingProvider.clampedNormalizedRect(CGRect(x: 0.2, y: 0.2, width: 0, height: 0.2)) == nil)
        #expect(MotionTrackingProvider.clampedNormalizedRect(CGRect(x: .nan, y: 0.2, width: 0.2, height: 0.2)) == nil)
    }

    @Test("display and Vision rect conversion round-trips")
    func displayVisionRoundTrip() throws {
        let displayRect = CGRect(x: 0.25, y: 0.10, width: 0.40, height: 0.30)
        let visionRect = MotionTrackingProvider.visionBoundingBox(fromDisplayRect: displayRect)
        let roundTrip = MotionTrackingProvider.displayRect(fromVisionBoundingBox: visionRect)

        #expect(abs(roundTrip.minX - displayRect.minX) < 0.0001)
        #expect(abs(roundTrip.minY - displayRect.minY) < 0.0001)
        #expect(abs(roundTrip.width - displayRect.width) < 0.0001)
        #expect(abs(roundTrip.height - displayRect.height) < 0.0001)
    }

    @Test("track validates inputs before touching the video")
    func trackValidatesInputsFirst() async {
        let provider = MotionTrackingProvider()
        await #expect(throws: MotionTrackingError.invalidInitialRect) {
            _ = try await provider.track(
                videoURL: URL(fileURLWithPath: "/tmp/missing.mov"),
                initialRect: CGRect(x: 0.2, y: 0.2, width: 0, height: 0.2),
                timeRange: TimeRange(start: 0, duration: 1)
            )
        }

        await #expect(throws: MotionTrackingError.invalidTimeRange) {
            _ = try await provider.track(
                videoURL: URL(fileURLWithPath: "/tmp/missing.mov"),
                initialRect: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
                timeRange: TimeRange(start: 0, duration: 0)
            )
        }
    }

    // MARK: - Recovery planner

    @Test("recovery planner predicts the trusted constant-velocity trajectory")
    func recoveryPlannerPredictsConstantVelocity() throws {
        let seed = TrackingResult(
            timestamp: 0,
            rect: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.20),
            confidence: 1
        )
        var planner = MotionTrackingRecoveryPlanner(seed: seed)

        let first = planner.evaluate(
            timestamp: 0.1,
            candidateRect: CGRect(x: 0.12, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.9
        )
        guard case .accept = first else {
            Issue.record("first confident candidate should establish velocity")
            return
        }

        let predicted = planner.predictedRect(at: 0.6)
        #expect(abs(predicted.minX - 0.22) < 0.0001)
        #expect(abs(predicted.minY - 0.20) < 0.0001)
        #expect(abs(predicted.width - 0.20) < 0.0001)
        #expect(abs(predicted.height - 0.20) < 0.0001)
    }

    @Test("low confidence reseeds and the next appearance-verified candidate is reacquired")
    func lowConfidenceReseedsThenReacquires() throws {
        let seed = TrackingResult(
            timestamp: 0,
            rect: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.20),
            confidence: 1
        )
        var planner = MotionTrackingRecoveryPlanner(seed: seed)

        _ = planner.evaluate(
            timestamp: 0.1,
            candidateRect: CGRect(x: 0.12, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.9
        )

        let lost = planner.evaluate(
            timestamp: 0.2,
            candidateRect: CGRect(x: 0.14, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.1
        )
        guard case .reseed(let predicted, let reason) = lost else {
            Issue.record("low-confidence candidate should trigger a reseed")
            return
        }
        #expect(reason == .lowConfidence)
        #expect(abs(predicted.minX - 0.14) < 0.0001)
        #expect(planner.isRecovering)

        let recovered = planner.evaluate(
            timestamp: 0.3,
            candidateRect: CGRect(x: 0.16, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.95,
            appearanceVerified: true
        )
        guard case .accept(let result, let reacquired) = recovered else {
            Issue.record("appearance-verified candidate should reacquire")
            return
        }
        #expect(reacquired)
        #expect(abs(result.rect.minX - 0.16) < 0.0001)
        #expect(!planner.isRecovering)
    }

    @Test("recovery never accepts an unverified candidate")
    func recoveryRejectsUnverifiedCandidate() {
        let seed = TrackingResult(
            timestamp: 0,
            rect: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.20),
            confidence: 1
        )
        var planner = MotionTrackingRecoveryPlanner(seed: seed)
        _ = planner.evaluate(
            timestamp: 0.1,
            candidateRect: CGRect(x: 0.12, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.9
        )
        _ = planner.evaluate(timestamp: 0.2, candidateRect: nil, confidence: nil)

        let unverified = planner.evaluate(
            timestamp: 0.3,
            candidateRect: CGRect(x: 0.16, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.95
        )
        guard case .reseed(_, let reason) = unverified else {
            Issue.record("recovery must fail closed without appearance verification")
            return
        }
        #expect(reason == .motionInconsistent)
        #expect(planner.isRecovering)
    }

    @Test("appearance-verified recovery can re-anchor outside a stale trajectory")
    func appearanceVerifiedRecoveryCanReanchor() {
        let seed = TrackingResult(
            timestamp: 0,
            rect: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.20),
            confidence: 1
        )
        var planner = MotionTrackingRecoveryPlanner(seed: seed)
        _ = planner.evaluate(
            timestamp: 0.1,
            candidateRect: CGRect(x: 0.12, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.9
        )
        _ = planner.evaluate(timestamp: 0.2, candidateRect: nil, confidence: nil)

        let unverified = planner.evaluate(
            timestamp: 0.8,
            candidateRect: CGRect(x: 0.55, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.95
        )
        guard case .reseed(_, let reason) = unverified else {
            Issue.record("trajectory-distant unverified candidate should stay rejected")
            return
        }
        #expect(reason == .motionInconsistent)

        let verified = planner.evaluate(
            timestamp: 0.8,
            candidateRect: CGRect(x: 0.55, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.95,
            appearanceVerified: true
        )
        guard case .accept(let result, let reacquired) = verified else {
            Issue.record("appearance-verified candidate should re-anchor recovery")
            return
        }
        #expect(reacquired)
        #expect(abs(result.rect.minX - 0.55) < 0.0001)
        #expect(!planner.isRecovering)
    }

    @Test("confident but motion-inconsistent candidate is not emitted as trusted")
    func inconsistentCandidateReseeds() {
        let seed = TrackingResult(
            timestamp: 0,
            rect: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.20),
            confidence: 1
        )
        var planner = MotionTrackingRecoveryPlanner(seed: seed)
        _ = planner.evaluate(
            timestamp: 0.1,
            candidateRect: CGRect(x: 0.12, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.9
        )

        let decision = planner.evaluate(
            timestamp: 0.2,
            candidateRect: CGRect(x: 0.65, y: 0.20, width: 0.20, height: 0.20),
            confidence: 0.99
        )
        guard case .reseed(_, let reason) = decision else {
            Issue.record("trajectory-inconsistent observation should be rejected")
            return
        }
        #expect(reason == .motionInconsistent)
    }

    @Test("recovery duration is bounded and cannot reseed forever")
    func recoveryEventuallyExhausts() {
        let seed = TrackingResult(
            timestamp: 0,
            rect: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.20),
            confidence: 1
        )
        let configuration = MotionTrackingRecoveryPlanner.Configuration(
            minimumTrustedConfidence: 0.25,
            minimumPredictionIoU: 0.30,
            maximumRecoveryDuration: 0.20,
            maximumNormalizedVelocityPerSecond: 1.5
        )
        var planner = MotionTrackingRecoveryPlanner(seed: seed, configuration: configuration)

        let firstLoss = planner.evaluate(timestamp: 0.10, candidateRect: nil, confidence: nil)
        guard case .reseed = firstLoss else {
            Issue.record("first loss should enter bounded recovery")
            return
        }

        let exhausted = planner.evaluate(timestamp: 0.31, candidateRect: nil, confidence: nil)
        #expect(exhausted == .exhausted)
    }

    @Test("recovery timeout wins over a valid appearance-verified candidate")
    func recoveryTimeoutPreventsLateReacquisition() {
        let seed = TrackingResult(
            timestamp: 0,
            rect: CGRect(x: 0.10, y: 0.20, width: 0.20, height: 0.20),
            confidence: 1
        )
        let configuration = MotionTrackingRecoveryPlanner.Configuration(
            minimumTrustedConfidence: 0.25,
            minimumPredictionIoU: 0.30,
            maximumRecoveryDuration: 0.20,
            maximumNormalizedVelocityPerSecond: 1.5
        )
        var planner = MotionTrackingRecoveryPlanner(seed: seed, configuration: configuration)

        let firstLoss = planner.evaluate(timestamp: 0.10, candidateRect: nil, confidence: nil)
        guard case .reseed = firstLoss else {
            Issue.record("first loss should enter bounded recovery")
            return
        }

        let lateCandidate = planner.evaluate(
            timestamp: 0.31,
            candidateRect: seed.rect,
            confidence: 0.99,
            appearanceVerified: true
        )
        #expect(lateCandidate == .exhausted)
        #expect(planner.isRecovering)
    }

    @Test("prediction clamps at the frame edge while preserving trusted box size")
    func recoveryPredictionClampsAtFrameEdge() {
        let seed = TrackingResult(
            timestamp: 0,
            rect: CGRect(x: 0.65, y: 0.20, width: 0.25, height: 0.20),
            confidence: 1
        )
        var planner = MotionTrackingRecoveryPlanner(seed: seed)
        _ = planner.evaluate(
            timestamp: 0.1,
            candidateRect: CGRect(x: 0.70, y: 0.20, width: 0.25, height: 0.20),
            confidence: 0.9
        )

        let predicted = planner.predictedRect(at: 1.0)
        #expect(abs(predicted.width - 0.25) < 0.0001)
        #expect(abs(predicted.height - 0.20) < 0.0001)
        #expect(abs(predicted.maxX - 1.0) < 0.0001)
        #expect(predicted.minX >= 0)
        #expect(predicted.minY >= 0)
        #expect(predicted.maxY <= 1)
    }

    #if canImport(Vision)
    @Test("track follows the moving subject fixture by frame IoU")
    func trackFollowsMovingSubjectFixtureByFrameIoU() async throws {
        let provider = MotionTrackingProvider()
        #expect(provider.isAvailable)

        let sampleRate = 15.0
        let initialRect = MotionTrackingGroundTruth.expectedMovingSubjectRect(at: 0)
        let results = try await provider.track(
            videoURL: MediaFixtures.movingSubjectVideo,
            initialRect: initialRect,
            timeRange: TimeRange(start: 0, duration: 2),
            frameRate: sampleRate
        )

        let ious = results.map { result in
            MotionTrackingGroundTruth.iou(
                result.rect,
                MotionTrackingGroundTruth.expectedMovingSubjectRect(at: result.timestamp)
            )
        }
        let sampleCount = ious.count
        let meanIoU = ious.reduce(0, +) / Double(max(sampleCount, 1))
        let minIoU = ious.min() ?? 0

        print(
            String(
                format: "Motion tracking IoU fixture=moving_subject_320x240_2s_30fps.mp4 samples=%d mean=%.4f min=%.4f",
                sampleCount,
                meanIoU,
                minIoU
            )
        )

        #expect(sampleCount >= 25, "expected at least 25 tracked samples, got \(sampleCount)")
        #expect(meanIoU >= 0.75, "mean IoU \(meanIoU) fell below 0.75")
        #expect(minIoU >= 0.65, "minimum IoU \(minIoU) fell below 0.65")
    }

    @Test("tracking reacquires the moving subject after the full occlusion fixture")
    func trackReacquiresAfterFullOcclusion() async throws {
        let provider = MotionTrackingProvider()
        let duration = 3.0
        let results = try await provider.track(
            videoURL: MediaFixtures.movingSubjectOccludedVideo,
            initialRect: MotionTrackingGroundTruth.expectedMovingSubjectRect(at: 0, duration: duration),
            timeRange: TimeRange(start: 0, duration: duration),
            frameRate: 15
        )

        let samples = results.map { result in
            (
                time: result.timestamp,
                iou: MotionTrackingGroundTruth.iou(
                    result.rect,
                    MotionTrackingGroundTruth.expectedMovingSubjectRect(at: result.timestamp, duration: duration)
                )
            )
        }
        let before = samples.filter {
            $0.time < 1.1 && MotionTrackingGroundTruth.occlusionCoverageFraction(at: $0.time) == 0
        }
        let during = samples.filter {
            MotionTrackingGroundTruth.occlusionCoverageFraction(at: $0.time) >= 0.99
        }
        let afterExit = samples.filter { $0.time >= 1.4 }.sorted { $0.time < $1.time }
        let reacquired = afterExit.first { $0.iou >= 0.60 }
        let sustained = samples.filter { $0.time >= 2.3 }

        let beforeMean = before.isEmpty ? 0 : before.map(\.iou).reduce(0, +) / Double(before.count)
        let duringMin = during.map(\.iou).min() ?? 1
        let sustainedMean = sustained.isEmpty ? 0 : sustained.map(\.iou).reduce(0, +) / Double(sustained.count)
        let latency = reacquired.map { $0.time - 1.4 }

        print(String(
            format: "Motion tracking recovery samples=%d before_mean=%.4f occluded_min=%.4f reacquire_at=%@ latency=%@ sustained_mean=%.4f",
            results.count,
            beforeMean,
            duringMin,
            reacquired.map { String(format: "%.3f", $0.time) } ?? "none",
            latency.map { String(format: "%.3f", $0) } ?? "none",
            sustainedMean
        ))

        #expect(beforeMean >= 0.75, "pre-occlusion mean IoU \(beforeMean) below 0.75")
        let degradationObserved = during.isEmpty || duringMin < 0.50
        #expect(
            degradationObserved,
            "full occlusion neither suppressed trusted results nor degraded their IoU"
        )
        #expect(reacquired != nil, "subject was never reacquired after the occlusion")
        if let latency {
            // The fixture is only fully emerged at t=2.3 (0.9s after the full
            // occlusion window ends), so 1.0s is the first evidence-based gate.
            #expect(latency <= 1.0, "reacquisition latency \(latency)s exceeded 1.0s")
        }
        #expect(!sustained.isEmpty, "no samples after the subject fully emerged")
        #expect(sustainedMean >= 0.65, "post-emergence sustained IoU \(sustainedMean) below 0.65")
    }
    #else
    @Test("motion tracking reports Vision unavailable on this platform")
    func motionTrackingReportsVisionUnavailable() {
        #expect(!MotionTrackingProvider().isAvailable)
    }
    #endif
}
