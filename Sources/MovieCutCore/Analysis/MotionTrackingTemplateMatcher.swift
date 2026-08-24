import CoreGraphics
import Foundation

/// Lightweight local appearance matcher used only while motion tracking is in
/// recovery. It downsamples frames before matching so cost is bounded by the
/// analysis surface rather than source resolution.
///
/// V1 deliberately keeps the initial selection's size fixed. This is a local
/// redetection aid for short occlusions, not a semantic detector or arbitrary
/// scale-invariant re-identification system.
struct MotionTrackingTemplateMatcher: Sendable {
    struct Match: Sendable, Equatable {
        var rect: CGRect
        var score: Double
    }

    private let frameWidth: Int
    private let frameHeight: Int
    private let templateWidth: Int
    private let templateHeight: Int
    private let templatePixels: [UInt8]
    private let minimumScore: Double

    init?(
        seedImage: CGImage,
        normalizedRect: CGRect,
        maximumFrameDimension: Int = 192,
        minimumScore: Double = 0.82
    ) {
        guard maximumFrameDimension >= 32,
              let dimensions = Self.downsampledDimensions(
                  sourceWidth: seedImage.width,
                  sourceHeight: seedImage.height,
                  maximumDimension: maximumFrameDimension
              ),
              let frame = Self.grayscale(
                  seedImage,
                  width: dimensions.width,
                  height: dimensions.height
              )
        else {
            return nil
        }

        let pixelRect = Self.pixelRect(
            for: normalizedRect,
            frameWidth: dimensions.width,
            frameHeight: dimensions.height
        )
        guard pixelRect.width >= 4, pixelRect.height >= 4 else { return nil }

        var pixels: [UInt8] = []
        pixels.reserveCapacity(pixelRect.width * pixelRect.height)
        for row in 0..<pixelRect.height {
            let start = (pixelRect.y + row) * dimensions.width + pixelRect.x
            let end = start + pixelRect.width
            pixels.append(contentsOf: frame[start..<end])
        }

        self.frameWidth = dimensions.width
        self.frameHeight = dimensions.height
        self.templateWidth = pixelRect.width
        self.templateHeight = pixelRect.height
        self.templatePixels = pixels
        self.minimumScore = min(max(minimumScore, 0), 1)
    }

    /// Finds the strongest fixed-size appearance match near the predicted box.
    /// Returns nil unless the appearance score clears the recovery gate.
    func bestMatch(in image: CGImage, around predictedRect: CGRect) -> Match? {
        guard let frame = Self.grayscale(image, width: frameWidth, height: frameHeight),
              templatePixels.count == templateWidth * templateHeight,
              templateWidth <= frameWidth,
              templateHeight <= frameHeight
        else {
            return nil
        }

        let predictedPixelRect = Self.pixelRect(
            for: predictedRect,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            forcedWidth: templateWidth,
            forcedHeight: templateHeight
        )
        let maxX = frameWidth - templateWidth
        let maxY = frameHeight - templateHeight
        let normalization = Double(255 * templatePixels.count)

        func score(atX x: Int, y: Int) -> Double {
            var absoluteDifference = 0
            for templateY in 0..<templateHeight {
                let templateBase = templateY * templateWidth
                let frameBase = (y + templateY) * frameWidth + x
                for templateX in 0..<templateWidth {
                    absoluteDifference += abs(
                        Int(templatePixels[templateBase + templateX]) -
                            Int(frame[frameBase + templateX])
                    )
                }
            }
            return 1 - (Double(absoluteDifference) / normalization)
        }

        func scan(
            minX: Int,
            maxX: Int,
            minY: Int,
            maxY: Int,
            step: Int
        ) -> (score: Double, x: Int, y: Int)? {
            guard minX <= maxX, minY <= maxY else { return nil }
            var bestScore = -Double.infinity
            var bestX = minX
            var bestY = minY
            var y = minY
            while y <= maxY {
                var x = minX
                while x <= maxX {
                    let candidateScore = score(atX: x, y: y)
                    if candidateScore > bestScore {
                        bestScore = candidateScore
                        bestX = x
                        bestY = y
                    }
                    x += step
                }
                y += step
            }
            return (bestScore, bestX, bestY)
        }

        let radiusX = max(Int((CGFloat(frameWidth) * 0.30).rounded()), templateWidth / 2)
        let radiusY = max(Int((CGFloat(frameHeight) * 0.20).rounded()), templateHeight / 2)
        let localMinX = max(0, predictedPixelRect.x - radiusX)
        let localMaxX = min(maxX, predictedPixelRect.x + radiusX)
        let localMinY = max(0, predictedPixelRect.y - radiusY)
        let localMaxY = min(maxY, predictedPixelRect.y + radiusY)

        if let local = scan(
            minX: localMinX,
            maxX: localMaxX,
            minY: localMinY,
            maxY: localMaxY,
            step: 2
        ), local.score >= minimumScore {
            return Match(
                rect: Self.normalizedDisplayRect(
                    x: local.x,
                    y: local.y,
                    width: templateWidth,
                    height: templateHeight,
                    frameWidth: frameWidth,
                    frameHeight: frameHeight
                ),
                score: local.score
            )
        }

        // Full occlusion can make the motion prediction stale. Search the
        // already-downsampled frame coarsely, then refine the best candidate.
        guard let coarse = scan(minX: 0, maxX: maxX, minY: 0, maxY: maxY, step: 4) else {
            return nil
        }
        let refineRadius = 4
        let refined = scan(
            minX: max(0, coarse.x - refineRadius),
            maxX: min(maxX, coarse.x + refineRadius),
            minY: max(0, coarse.y - refineRadius),
            maxY: min(maxY, coarse.y + refineRadius),
            step: 1
        ) ?? coarse

        guard refined.score >= minimumScore else { return nil }
        return Match(
            rect: Self.normalizedDisplayRect(
                x: refined.x,
                y: refined.y,
                width: templateWidth,
                height: templateHeight,
                frameWidth: frameWidth,
                frameHeight: frameHeight
            ),
            score: refined.score
        )
    }

    private static func downsampledDimensions(
        sourceWidth: Int,
        sourceHeight: Int,
        maximumDimension: Int
    ) -> (width: Int, height: Int)? {
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let scale = min(
            CGFloat(maximumDimension) / CGFloat(max(sourceWidth, sourceHeight)),
            1
        )
        return (
            max(1, Int((CGFloat(sourceWidth) * scale).rounded())),
            max(1, Int((CGFloat(sourceHeight) * scale).rounded()))
        )
    }

    /// Renders one-channel pixels. CGBitmapContext rows use the Core Graphics
    /// bottom-left image space, so normalized top-left display Y is converted
    /// explicitly in `pixelRect` / `normalizedDisplayRect` below.
    private static func grayscale(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  )
            else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? pixels : nil
    }

    private static func pixelRect(
        for rect: CGRect,
        frameWidth: Int,
        frameHeight: Int,
        forcedWidth: Int? = nil,
        forcedHeight: Int? = nil
    ) -> (x: Int, y: Int, width: Int, height: Int) {
        let standardized = rect.standardized
        let width = forcedWidth ?? max(1, Int((standardized.width * CGFloat(frameWidth)).rounded()))
        let height = forcedHeight ?? max(1, Int((standardized.height * CGFloat(frameHeight)).rounded()))
        let centerX = standardized.midX * CGFloat(frameWidth)
        let bottomCenterY = (1 - standardized.midY) * CGFloat(frameHeight)
        let maxX = max(frameWidth - width, 0)
        let maxY = max(frameHeight - height, 0)
        let x = min(max(Int((centerX - CGFloat(width) * 0.5).rounded()), 0), maxX)
        let y = min(max(Int((bottomCenterY - CGFloat(height) * 0.5).rounded()), 0), maxY)
        return (x, y, min(width, frameWidth), min(height, frameHeight))
    }

    private static func normalizedDisplayRect(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        frameWidth: Int,
        frameHeight: Int
    ) -> CGRect {
        CGRect(
            x: CGFloat(x) / CGFloat(frameWidth),
            y: 1 - CGFloat(y + height) / CGFloat(frameHeight),
            width: CGFloat(width) / CGFloat(frameWidth),
            height: CGFloat(height) / CGFloat(frameHeight)
        )
    }
}
