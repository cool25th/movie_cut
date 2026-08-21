import CoreMedia
import Foundation
import Testing
@testable import MovieCutCore

/// Code-review regressions for the graph timebase origin contract.
@Suite("Audio Graph Timebase Origin Regression")
struct AudioGraphTimebaseOriginRegressionTests {
    @Test("graph sample zero maps to the serialized non-zero timeline origin")
    func sampleZeroIsOrigin() {
        let origin = CMTime(value: 600, timescale: 600) // 1 second
        let timebase = AudioGraphTimebase(sampleRate: 48_000, origin: origin)

        #expect(timebase.samplePosition(at: origin) == 0)

        let sampleZeroTime = timebase.time(atSamplePosition: 0)
        #expect(CMTimeCompare(sampleZeroTime, origin) == 0)
    }

    @Test("non-zero origin participates in both conversion directions")
    func nonZeroOriginRoundTrip() {
        let origin = CMTime(value: 3, timescale: 600)
        let timebase = AudioGraphTimebase(sampleRate: 48_000, origin: origin)
        let position: Int64 = 172_800_000 // 60 minutes of graph samples

        let absoluteTime = timebase.time(atSamplePosition: position)
        #expect(timebase.samplePosition(at: absoluteTime) == position)
        #expect(CMTimeCompare(absoluteTime, origin) > 0)
    }

    @Test("pre-origin fractional times floor to the preceding sample")
    func negativeRelativeTimeUsesFloor() {
        let origin = CMTime(value: 1, timescale: 1)
        let timebase = AudioGraphTimebase(sampleRate: 48_000, origin: origin)

        // 1/100000 second before the origin = -0.48 sample. A symmetric
        // floor contract maps it to sample -1 rather than truncating to 0.
        let justBeforeOrigin = CMTime(value: 99_999, timescale: 100_000)
        #expect(timebase.samplePosition(at: justBeforeOrigin) == -1)
    }

    @Test("one second after a non-zero origin is exactly one rate worth of samples")
    func oneSecondAfterOrigin() {
        let origin = CMTime(value: 5, timescale: 2) // 2.5 seconds
        let timebase = AudioGraphTimebase(sampleRate: 44_100, origin: origin)
        let oneSecondLater = CMTime(value: 7, timescale: 2) // 3.5 seconds

        #expect(timebase.samplePosition(at: oneSecondLater) == 44_100)
        #expect(CMTimeCompare(timebase.time(atSamplePosition: 44_100), oneSecondLater) == 0)
    }
}
