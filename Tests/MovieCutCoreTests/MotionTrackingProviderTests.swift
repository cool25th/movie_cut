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
}
