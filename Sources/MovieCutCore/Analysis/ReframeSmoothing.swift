import CoreGraphics
import Foundation

/// Smooths per-frame auto-reframe crop rectangles so the generated keyframes
/// do not jitter frame to frame (F-19 AC③). A centered moving average is
/// applied to each rect component, and the result is clamped so the crop never
/// reads outside the normalized source frame.
public enum ReframeSmoothing {
    /// Smooths crop frames with a centered moving average of the given radius.
    ///
    /// - Parameters:
    ///   - frames: Crop frames in normalized (0...1) source space, time-ordered.
    ///   - windowRadius: Frames averaged on each side (radius 2 → 5-frame window).
    public static func smooth(_ frames: [CropFrame], windowRadius: Int = 2) -> [CropFrame] {
        guard frames.count > 2, windowRadius > 0 else { return frames }

        let ordered = frames.sorted { $0.time < $1.time }
        var smoothed: [CropFrame] = []
        smoothed.reserveCapacity(ordered.count)

        for index in ordered.indices {
            let lower = max(0, index - windowRadius)
            let upper = min(ordered.count - 1, index + windowRadius)
            let window = ordered[lower...upper]
            let count = CGFloat(window.count)

            var sumX: CGFloat = 0, sumY: CGFloat = 0, sumW: CGFloat = 0, sumH: CGFloat = 0
            for frame in window {
                sumX += frame.rect.midX
                sumY += frame.rect.midY
                sumW += frame.rect.width
                sumH += frame.rect.height
            }

            let width = sumW / count
            let height = sumH / count
            let centerX = sumX / count
            let centerY = sumY / count
            let clamped = clampedRect(centerX: centerX, centerY: centerY, width: width, height: height)
            smoothed.append(CropFrame(time: ordered[index].time, rect: clamped))
        }

        return smoothed
    }

    /// The largest center movement between consecutive frames. Tests assert
    /// smoothing reduces this jitter metric.
    public static func maxCenterDelta(of frames: [CropFrame]) -> CGFloat {
        let ordered = frames.sorted { $0.time < $1.time }
        guard ordered.count > 1 else { return 0 }

        var maxDelta: CGFloat = 0
        for index in 1..<ordered.count {
            let previous = ordered[index - 1].rect
            let current = ordered[index].rect
            let dx = current.midX - previous.midX
            let dy = current.midY - previous.midY
            maxDelta = max(maxDelta, (dx * dx + dy * dy).squareRoot())
        }
        return maxDelta
    }

    /// Builds a rect from a center and size, clamped to the unit square so the
    /// crop never extends past the source frame.
    static func clampedRect(centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        let w = min(max(width, 0), 1)
        let h = min(max(height, 0), 1)
        let x = min(max(centerX - w / 2, 0), 1 - w)
        let y = min(max(centerY - h / 2, 0), 1 - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
