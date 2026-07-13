import Testing
@testable import MovieCutCore

@Suite("Timeline Scrub Behavior")
struct TimelineScrubBehaviorTests {
    @Test("ruler coordinate converts to timeline time")
    func convertsCoordinateToTime() {
        #expect(TimelineScrubMath.time(forLocalX: 100, pixelsPerSecond: 80, duration: 3) == 1.25)
    }

    @Test("coordinate clamps to timeline boundaries")
    func clampsBoundaries() {
        #expect(TimelineScrubMath.time(forLocalX: -20, pixelsPerSecond: 80, duration: 3) == 0)
        #expect(TimelineScrubMath.time(forLocalX: 800, pixelsPerSecond: 80, duration: 3) == 3)
    }

    @Test("invalid inputs fail closed at zero")
    func rejectsInvalidInputs() {
        #expect(TimelineScrubMath.time(forLocalX: .nan, pixelsPerSecond: 80, duration: 3) == 0)
        #expect(TimelineScrubMath.time(forLocalX: 100, pixelsPerSecond: 0, duration: 3) == 0)
        #expect(TimelineScrubMath.time(forLocalX: 100, pixelsPerSecond: .infinity, duration: 3) == 0)
        #expect(TimelineScrubMath.time(forLocalX: 100, pixelsPerSecond: 80, duration: .infinity) == 0)
    }
}
