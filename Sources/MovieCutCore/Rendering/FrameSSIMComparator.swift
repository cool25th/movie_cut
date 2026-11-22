import CoreGraphics
import CoreImage
import Foundation

/// Quantitative visual parity comparator (`CA-38`) for verifying frame-level structural
/// similarity (SSIM) and PSNR between preview and export rendering pipelines.
public enum FrameSSIMComparator {

    /// Result of comparing two RGBA8 frames of identical dimensions.
    public struct ComparisonMetrics: Sendable, Equatable {
        /// Mean Structural Similarity Index (MSSIM) across luminance windows in `[-1.0, 1.0]`.
        public let ssim: Double
        /// Peak Signal-to-Noise Ratio in dB (`Double.infinity` when frames are byte-identical).
        public let psnrDecibels: Double
        /// Maximum absolute per-channel difference in `0...255`.
        public let maxChannelDelta: Int

        public init(ssim: Double, psnrDecibels: Double, maxChannelDelta: Int) {
            self.ssim = ssim
            self.psnrDecibels = psnrDecibels
            self.maxChannelDelta = maxChannelDelta
        }
    }

    public enum ComparisonError: Error, Sendable, Equatable {
        case invalidDimensions(width: Int, height: Int)
        case bufferSizeMismatch(expected: Int, actualA: Int, actualB: Int)
        case rasterizationFailed
    }

    /// Computes MSSIM, PSNR, and max channel delta between two RGBA8 byte buffers.
    public static func compareRGBA8(
        _ bufferA: [UInt8],
        _ bufferB: [UInt8],
        width: Int,
        height: Int,
        windowSize: Int = 8
    ) throws -> ComparisonMetrics {
        guard width > 0, height > 0 else {
            throw ComparisonError.invalidDimensions(width: width, height: height)
        }
        let expectedBytes = width * height * 4
        guard bufferA.count == expectedBytes, bufferB.count == expectedBytes else {
            throw ComparisonError.bufferSizeMismatch(
                expected: expectedBytes,
                actualA: bufferA.count,
                actualB: bufferB.count
            )
        }

        let pixelCount = width * height
        var lumaA = [Double](repeating: 0, count: pixelCount)
        var lumaB = [Double](repeating: 0, count: pixelCount)
        var sumSquaredError: Double = 0
        var maxDelta = 0

        for i in 0..<pixelCount {
            let base = i * 4
            let rA = Int(bufferA[base])
            let gA = Int(bufferA[base + 1])
            let bA = Int(bufferA[base + 2])
            let aA = Int(bufferA[base + 3])

            let rB = Int(bufferB[base])
            let gB = Int(bufferB[base + 1])
            let bB = Int(bufferB[base + 2])
            let aB = Int(bufferB[base + 3])

            let dr = abs(rA - rB)
            let dg = abs(gA - gB)
            let db = abs(bA - bB)
            let da = abs(aA - aB)
            maxDelta = max(maxDelta, dr, dg, db, da)

            sumSquaredError += Double(dr * dr + dg * dg + db * db)

            // BT.709 luma
            lumaA[i] = 0.2126 * Double(rA) + 0.7152 * Double(gA) + 0.0722 * Double(bA)
            lumaB[i] = 0.2126 * Double(rB) + 0.7152 * Double(gB) + 0.0722 * Double(bB)
        }

        let mse = sumSquaredError / Double(pixelCount * 3)
        let psnr: Double = mse == 0 ? .infinity : (10.0 * log10((255.0 * 255.0) / mse))

        let effectiveWin = max(1, min(windowSize, min(width, height)))
        let step = max(1, effectiveWin / 2)
        var ssimSum: Double = 0
        var windowCount = 0

        var y = 0
        while y <= height - effectiveWin {
            var x = 0
            while x <= width - effectiveWin {
                ssimSum += windowSSIM(
                    lumaA: lumaA,
                    lumaB: lumaB,
                    stride: width,
                    startX: x,
                    startY: y,
                    windowSize: effectiveWin
                )
                windowCount += 1
                x += step
            }
            y += step
        }

        let meanSSIM: Double
        if windowCount > 0 {
            meanSSIM = ssimSum / Double(windowCount)
        } else {
            meanSSIM = windowSSIM(
                lumaA: lumaA,
                lumaB: lumaB,
                stride: width,
                startX: 0,
                startY: 0,
                windowSize: effectiveWin
            )
        }

        return ComparisonMetrics(
            ssim: meanSSIM,
            psnrDecibels: psnr,
            maxChannelDelta: maxDelta
        )
    }

    /// Renders two `CIImage` frames over `extent` into RGBA8 buffers using a software
    /// sRGB `CIContext` and computes their `ComparisonMetrics`.
    public static func compare(
        _ imageA: CIImage,
        _ imageB: CIImage,
        extent: CGRect
    ) throws -> ComparisonMetrics {
        let width = Int(extent.width.rounded())
        let height = Int(extent.height.rounded())
        guard width > 0, height > 0 else {
            throw ComparisonError.invalidDimensions(width: width, height: height)
        }
        let bufferA = try rasterizeRGBA8(imageA, extent: extent, width: width, height: height)
        let bufferB = try rasterizeRGBA8(imageB, extent: extent, width: width, height: height)
        return try compareRGBA8(bufferA, bufferB, width: width, height: height)
    }

    private static func rasterizeRGBA8(
        _ image: CIImage,
        extent: CGRect,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ComparisonError.rasterizationFailed
        }
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace,
        ])
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            context.render(
                image,
                toBitmap: baseAddress,
                rowBytes: width * 4,
                bounds: extent,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return bytes
    }

    private static func windowSSIM(
        lumaA: [Double],
        lumaB: [Double],
        stride: Int,
        startX: Int,
        startY: Int,
        windowSize: Int
    ) -> Double {
        let count = Double(windowSize * windowSize)
        var sumA: Double = 0
        var sumB: Double = 0
        for dy in 0..<windowSize {
            let rowOffset = (startY + dy) * stride + startX
            for dx in 0..<windowSize {
                let idx = rowOffset + dx
                sumA += lumaA[idx]
                sumB += lumaB[idx]
            }
        }
        let meanA = sumA / count
        let meanB = sumB / count

        var varA: Double = 0
        var varB: Double = 0
        var covAB: Double = 0
        for dy in 0..<windowSize {
            let rowOffset = (startY + dy) * stride + startX
            for dx in 0..<windowSize {
                let idx = rowOffset + dx
                let da = lumaA[idx] - meanA
                let db = lumaB[idx] - meanB
                varA += da * da
                varB += db * db
                covAB += da * db
            }
        }
        let denom = max(1.0, count - 1.0)
        varA /= denom
        varB /= denom
        covAB /= denom

        // Wang et al. (2004) stability constants for 8-bit dynamic range L = 255
        let c1 = (0.01 * 255.0) * (0.01 * 255.0)
        let c2 = (0.03 * 255.0) * (0.03 * 255.0)

        let numerator = (2.0 * meanA * meanB + c1) * (2.0 * covAB + c2)
        let denominator = (meanA * meanA + meanB * meanB + c1) * (varA + varB + c2)
        return numerator / denominator
    }
}
