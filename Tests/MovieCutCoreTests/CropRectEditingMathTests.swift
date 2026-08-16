import Foundation
import MovieCutCore
import Testing

/// Gesture-math coverage for the G-23 crop canvas editor (Inc 2). The view
/// layer only translates view points into normalized deltas; every behavioral
/// guarantee — anchoring, frame clamping, no inversion, the minimum-size
/// floor, and aspect locking — lives here and is pinned by these tests.
@Suite("Crop Rect Editing Math")
struct CropRectEditingMathTests {
    private func rect(
        _ x: Double, _ y: Double, _ width: Double, _ height: Double
    ) -> NormalizedRect {
        NormalizedRect(x: x, y: y, width: width, height: height)!
    }

    // MARK: move

    @Test("Move keeps the window inside the unit frame on every side")
    func moveClampsToFrame() {
        let window = rect(0.25, 0.25, 0.5, 0.5)

        let left = CropRectEditingMath.move(window, dx: -1, dy: 0)
        #expect(left.x == 0)

        let right = CropRectEditingMath.move(window, dx: 1, dy: 0)
        #expect(right.x == 0.5)

        let up = CropRectEditingMath.move(window, dx: 0, dy: -1)
        #expect(up.y == 0)

        let down = CropRectEditingMath.move(window, dx: 0, dy: 1)
        #expect(down.y == 0.5)

        // Untouched axis and size are preserved.
        #expect(right.width == 0.5 && right.height == 0.5)
    }

    // MARK: resize anchoring

    @Test("Bottom-right resize anchors the top-left corner")
    func bottomRightAnchor() {
        let window = rect(0.2, 0.1, 0.4, 0.3)
        let resized = CropRectEditingMath.resize(window, from: .bottomRight, dx: 0.1, dy: 0.2)

        #expect(resized.x == 0.2)
        #expect(resized.y == 0.1)
        #expect(resized.width == 0.5)
        #expect(resized.height == 0.5)
    }

    @Test("Top-left resize anchors the bottom-right corner")
    func topLeftAnchor() {
        let window = rect(0.4, 0.4, 0.4, 0.4)
        let resized = CropRectEditingMath.resize(window, from: .topLeft, dx: -0.4, dy: -0.4)

        // Both moving edges clamp at the frame; the anchor edges are fixed.
        #expect(resized.x == 0)
        #expect(resized.y == 0)
        #expect(resized.width == 0.8)
        #expect(resized.height == 0.8)
    }

    @Test("Edge handles move only their own axis")
    func edgeHandlesSingleAxis() {
        let window = rect(0.2, 0.2, 0.4, 0.4)

        let byRight = CropRectEditingMath.resize(window, from: .right, dx: 0.2, dy: 0.9)
        #expect(abs(byRight.width - 0.6) < 1.0e-9)
        #expect(byRight.height == 0.4)
        #expect(byRight.x == 0.2 && byRight.y == 0.2)

        let byTop = CropRectEditingMath.resize(window, from: .top, dx: 0.9, dy: -0.1)
        #expect(byTop.height == 0.5)
        #expect(byTop.width == 0.4)
        #expect(abs(byTop.y - 0.1) < 1.0e-9)
    }

    // MARK: clamping guarantees

    @Test("Resize never leaves the unit frame or inverts the window")
    func resizeClampsAndNeverInverts() {
        let window = rect(0.2, 0.2, 0.4, 0.4)

        // Drag each corner far past the frame in every direction: the result
        // must stay a valid, non-inverted rect inside 0...1.
        for handle in [CropRectEditingMath.Handle.topLeft, .topRight, .bottomRight, .bottomLeft] {
            for (dx, dy) in [(-5.0, -5.0), (5.0, -5.0), (-5.0, 5.0), (5.0, 5.0)] {
                let resized = CropRectEditingMath.resize(window, from: handle, dx: dx, dy: dy)
                #expect(resized.x >= 0 && resized.y >= 0)
                #expect(resized.maxX <= 1.0 && resized.maxY <= 1.0)
                #expect(resized.width > 0 && resized.height > 0)
            }
        }
    }

    @Test("Resize enforces the minimum-size floor")
    func minimumSizeFloor() {
        let window = rect(0.3, 0.3, 0.4, 0.4)
        let collapsed = CropRectEditingMath.resize(window, from: .bottomRight, dx: -0.39, dy: -0.39)

        #expect(collapsed.width >= CropRectEditingMath.minimumEdge - 1.0e-9)
        #expect(collapsed.height >= CropRectEditingMath.minimumEdge - 1.0e-9)
    }

    // MARK: aspect locking

    @Test("Aspect-locked corner resize derives the cross axis")
    func aspectLockCorner() {
        let full = rect(0, 0, 1, 1)
        // Drag bottom-right 0.25 left with a 1:1 lock: width drives, height
        // follows, anchor stays at the top-left corner.
        let resized = CropRectEditingMath.resize(full, from: .bottomRight, dx: -0.25, dy: 0, aspect: 1)

        #expect(resized.x == 0 && resized.y == 0)
        #expect(abs(resized.width - 0.75) < 1.0e-9)
        #expect(abs(resized.height - 0.75) < 1.0e-9)
    }

    @Test("Aspect-locked edge resize clamps to the frame's room")
    func aspectLockEdgeClamp() {
        let full = rect(0, 0, 1, 1)
        // 9:16 window from a right-edge drag: width wants 1.5 (clamped to 1)
        // but the height that ratio needs exceeds the frame, so both shrink
        // to the largest 9:16 rect that fits anchored at the left edge.
        let resized = CropRectEditingMath.resize(full, from: .right, dx: 0.5, dy: 0, aspect: 9.0 / 16.0)

        #expect(resized.x == 0 && resized.y == 0)
        #expect(abs(resized.width - 9.0 / 16.0) < 1.0e-9)
        #expect(abs(resized.height - 1.0) < 1.0e-9)
    }

    @Test("Aspect lock keeps the pixel ratio for a tall target")
    func aspectLockTallRatio() {
        let window = rect(0.1, 0.1, 0.8, 0.8)
        let resized = CropRectEditingMath.resize(window, from: .bottomRight, dx: 0, dy: -0.3, aspect: 0.5)

        #expect(abs(resized.height - 0.5) < 1.0e-9)
        #expect(abs(resized.width - 0.25) < 1.0e-9)
        #expect(resized.x == 0.1 && resized.y == 0.1)
    }

    // MARK: interior

    @Test("Interior handle behaves as a move")
    func interiorActsAsMove() {
        let window = rect(0.25, 0.25, 0.5, 0.5)
        let resized = CropRectEditingMath.resize(window, from: .interior, dx: 0.1, dy: -0.1)
        let moved = CropRectEditingMath.move(window, dx: 0.1, dy: -0.1)

        #expect(resized == moved)
        #expect(resized.x == 0.35 && resized.y == 0.15)
    }
}
