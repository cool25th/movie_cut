import Foundation
import Testing
@testable import MovieCutCore

@MainActor

@Suite("SpeedRampCurve critical and high coverage")
struct SpeedRampCurveCriticalHighTests {
    @Test("Linear speed ramp curve is identity")
    func testLinearCurveIsIdentity() {
        let outputTime = SpeedRampCurve.linear.timeMapping(sourceTime: 5.0)

        #expect(outputTime == 5.0)
    }

    @Test("Single speed ramp point returns scaled source time")
    func testSinglePointReturnsSourceTime() {
        let curve = SpeedRampCurve(points: [
            SpeedRampPoint(time: 0, rate: 2.0)
        ])

        #expect(curve.timeMapping(sourceTime: 5.0) == 2.5)
    }

    @Test("Two point speed ramp curve maps linearly varying rate")
    func testTwoPointLinear() {
        let curve = SpeedRampCurve(points: [
            unclampedSpeedRampPoint(time: 0, rate: 1.0),
            unclampedSpeedRampPoint(time: 10, rate: 2.0)
        ])

        let outputTime = curve.timeMapping(sourceTime: 5.0)

        #expect(abs(outputTime - 4.17) < 0.15)
    }

    @Test("Speed ramp inverse mapping returns original source time")
    func testInverseMapping() {
        let curve = SpeedRampCurve(points: [
            unclampedSpeedRampPoint(time: 0, rate: 1.0),
            unclampedSpeedRampPoint(time: 10, rate: 2.0)
        ])
        let sourceTime = 5.0
        let outputTime = curve.timeMapping(sourceTime: sourceTime)

        #expect(abs(curve.inverseMapping(outputTime: outputTime) - sourceTime) < 1.0e-9)
    }
}

@MainActor
@Suite("SnapEngine critical and high coverage")
struct SnapEngineCriticalHighTests {
    @Test("Snap engine snaps to nearest clip boundary")
    func testSnapToNearestBoundary() {
        let timeline = makeTimelineWithAdjacentClips()
        let snappedTime = SnapEngine().snap(time: 4.95, timeline: timeline)

        #expect(snappedTime == 5.0)
    }

    @Test("Snap engine returns nil when boundary is too far")
    func testNoSnapWhenFar() {
        let timeline = makeTimelineWithAdjacentClips()
        let snappedTime = SnapEngine().snap(time: 2.0, timeline: timeline)

        #expect(snappedTime == nil)
    }

    @Test("Snap engine honors custom threshold")
    func testCustomThreshold() {
        let timeline = makeTimelineWithAdjacentClips()
        let snappedTime = SnapEngine(threshold: 0.5).snap(time: 4.6, timeline: timeline)

        #expect(snappedTime == 5.0)
    }
}

@MainActor
@Suite("TimelineZoomLevel critical and high coverage")
struct TimelineZoomLevelCriticalHighTests {
    @Test("Timeline zoom presets exist with correct names")
    func testPresetsExist() {
        #expect(TimelineZoomLevel.compact.name == "Compact")
        #expect(TimelineZoomLevel.normal.name == "Normal")
        #expect(TimelineZoomLevel.comfortable.name == "Comfortable")
        #expect(TimelineZoomLevel.detailed.name == "Detailed")
    }

    @Test("Timeline zoom all returns four presets")
    func testAllReturnsFour() {
        #expect(TimelineZoomLevel.all.count == 4)
    }
}

private func unclampedSpeedRampPoint(time: TimeInterval, rate: Double) -> SpeedRampPoint {
    var point = SpeedRampPoint(time: time, rate: rate)
    point.time = time
    point.rate = rate
    return point
}

private func makeTimelineWithAdjacentClips() -> Timeline {
    let clips = [
        makeClip(timelineRange: TimeRange(start: 0, duration: 5)),
        makeClip(timelineRange: TimeRange(start: 5, duration: 5))
    ]
    let track = Track(kind: .video, name: "Video 1", clips: clips)

    return Timeline(tracks: [track])
}

private func makeClip(
    sourceRange: TimeRange = TimeRange(start: 0, duration: 5),
    timelineRange: TimeRange
) -> Clip {
    Clip(
        kind: .video,
        sourceRange: sourceRange,
        timelineRange: timelineRange
    )
}

