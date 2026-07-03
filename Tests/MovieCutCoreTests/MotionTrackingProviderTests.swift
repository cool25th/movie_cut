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

    #if canImport(Vision)
    @Test("track follows the moving subject fixture by frame IoU")
    func trackFollowsMovingSubjectFixtureByFrameIoU() async throws {
        let provider = MotionTrackingProvider()
        #expect(provider.isAvailable)

        let sampleRate = 15.0
        let initialRect = Self.expectedMovingSubjectRect(at: 0)
        let results = try await provider.track(
            videoURL: MediaFixtures.movingSubjectVideo,
            initialRect: initialRect,
            timeRange: TimeRange(start: 0, duration: 2),
            frameRate: sampleRate
        )

        let ious = results.map { result in
            Self.iou(result.rect, Self.expectedMovingSubjectRect(at: result.timestamp))
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
    #else
    @Test("motion tracking reports Vision unavailable on this platform")
    func motionTrackingReportsVisionUnavailable() {
        #expect(!MotionTrackingProvider().isAvailable)
    }
    #endif

    private static func expectedMovingSubjectRect(at timestamp: TimeInterval) -> CGRect {
        let width = 320.0
        let height = 240.0
        let boxWidth = 72.0
        let boxHeight = 64.0
        let startX = 32.0
        let y = 88.0
        let pixelsPerSecond = 80.0
        let clampedTimestamp = min(max(timestamp, 0), 2)
        return CGRect(
            x: (startX + pixelsPerSecond * clampedTimestamp) / width,
            y: y / height,
            width: boxWidth / width,
            height: boxHeight / height
        )
    }

    private static func iou(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return 0
        }

        let intersectionArea = Double(intersection.width * intersection.height)
        let lhsArea = Double(lhs.width * lhs.height)
        let rhsArea = Double(rhs.width * rhs.height)
        let unionArea = lhsArea + rhsArea - intersectionArea
        guard unionArea > 0 else {
            return 0
        }

        return intersectionArea / unionArea
    }
}
