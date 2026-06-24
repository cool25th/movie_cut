import Foundation
import Testing
@testable import MovieCutCore

/// Covers the color-wheel position ↔ RGB-offset mapping (Phase 2A increment 5).
@Suite("Color Wheel Math")
struct ColorWheelMathTests {
    private func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

    @Test("center maps to no offset")
    func centerIsNeutral() {
        let offsets = ColorWheelMath.channelOffsets(x: 0, y: 0, scale: 0.5)
        #expect(close(offsets.red, 0) && close(offsets.green, 0) && close(offsets.blue, 0))
    }

    @Test("dragging up pushes red, away from green and blue")
    func upPushesRed() {
        let offsets = ColorWheelMath.channelOffsets(x: 0, y: 1, scale: 0.5)
        #expect(close(offsets.red, 0.5))
        #expect(offsets.red > offsets.green)
        #expect(offsets.red > offsets.blue)
        #expect(close(offsets.green, offsets.blue))
    }

    @Test("lower-right pushes blue more than green")
    func lowerRightPushesBlue() {
        let offsets = ColorWheelMath.channelOffsets(x: 0.8660254037844387, y: -0.5, scale: 1)
        #expect(offsets.blue > offsets.green)
        #expect(offsets.blue > offsets.red)
    }

    @Test("position is the exact inverse of channelOffsets")
    func roundTrips() {
        for (x, y) in [(0.0, 1.0), (-0.5, 0.3), (0.2, -0.7), (0.0, 0.0)] {
            let offsets = ColorWheelMath.channelOffsets(x: x, y: y, scale: 0.5)
            let back = ColorWheelMath.position(red: offsets.red, green: offsets.green, blue: offsets.blue, scale: 0.5)
            #expect(close(back.x, x) && close(back.y, y))
        }
    }

    @Test("positions outside the unit disk are clamped to its edge")
    func clampsToDisk() {
        let clamped = ColorWheelMath.clampedToDisk(x: 3, y: 4)
        #expect(close((clamped.x * clamped.x + clamped.y * clamped.y).squareRoot(), 1))
        let inside = ColorWheelMath.clampedToDisk(x: 0.3, y: 0.4)
        #expect(close(inside.x, 0.3) && close(inside.y, 0.4))
    }
}
