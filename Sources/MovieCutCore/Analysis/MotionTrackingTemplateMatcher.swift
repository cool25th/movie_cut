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
        let radiusX = max(Int((CGFloat(frameWidth) * 0.30).rounded()), templateWidth / 2)
        let radiusY = max(Int((CGFloat(frameHeight) * 0.20).rounded()), templateHeight / 2)
        let maxX = frameWidth - templateWidth
        let maxY = frameHeight - templateHeight
        let minSearchX = max(0, predictedPixelRect.x - radiusX)
        let maxSearchX = min(maxX, predictedPixelRect.x + radiusX)
        let minSearchY = max(0, predictedPixelRect.y - radiusY)
        let maxSearchY = min(maxY, predictedPixelRect.y + radiusY)
        guard minSearchX <= maxSearchX, minSearchY <= maxSearchY else { return nil }

        let step = 2
        var bestScore = -Double.infinity
        var bestX = predictedPixelRect.x
        var bestY = predictedPixelRect.y
        let normalization = Double(255 * templatePixels.count)

        var y = minSearchY
        while y <= maxSearchY {
            var x = minSearchX
            while x <= maxSearchX {
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

                let score = 1 - (Double(absoluteDifference) / normalization)
                if score > bestScore {
                    bestScore = score
                    bestX = x
                    bestY = y
                }
                x += step
            }
            y += step
        }

        guard bestScore >= minimumScore else { return nil }
        return Match(
            rect: Self.normalizedDisplayRect(
                x: bestX,
                y: bestY,
                width: templateWidth,
                height: templateHeight,
                frameWidth: frameWidth,
                frameHeight: frameHeight
            ),
            score: bestScore
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
