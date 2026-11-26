import Foundation

/// On-device automatic color balance. Uses the gray-world assumption — a frame's
/// average should be neutral — to suggest a per-channel ``ColorGrade`` gain that
/// removes a color cast, with no cloud round-trip.
public enum AutoColorAnalyzer {
    /// Gray-world auto white balance: per-channel gain so the frame average moves
    /// toward neutral. A warm image (R > G > B) gets gain.red < 1 and gain.blue > 1.
    public static func autoWhiteBalanceGrade(rgba: [UInt8]) -> ColorGrade {
        let count = rgba.count / 4
        guard count > 0 else { return ColorGrade() }

        var sumRed = 0.0
        var sumGreen = 0.0
        var sumBlue = 0.0
        for index in 0..<count {
            let offset = index * 4
            sumRed += Double(rgba[offset])
            sumGreen += Double(rgba[offset + 1])
            sumBlue += Double(rgba[offset + 2])
        }

        let averageRed = sumRed / Double(count)
        let averageGreen = sumGreen / Double(count)
        let averageBlue = sumBlue / Double(count)
        guard averageRed > 0, averageGreen > 0, averageBlue > 0 else { return ColorGrade() }

        let averageGray = (averageRed + averageGreen + averageBlue) / 3
        func gain(for channelAverage: Double) -> Double {
            Swift.min(Swift.max(averageGray / channelAverage, 0.5), 2.0)
        }

        return ColorGrade(
            gain: ColorGrade.RGB(
                red: gain(for: averageRed),
                green: gain(for: averageGreen),
                blue: gain(for: averageBlue)
            )
        )
    }

    /// Auto levels: stretches the luma range so the `lowPercentile` darkest and
    /// `highPercentile` brightest pixels map to black/white, suggesting a uniform
    /// gain (slope) + lift (offset). Outlier percentiles avoid letting a few
    /// extreme pixels dictate the stretch.
    public static func autoLevelsGrade(
        rgba: [UInt8],
        lowPercentile: Double = 0.02,
        highPercentile: Double = 0.98
    ) -> ColorGrade {
        let count = rgba.count / 4
        guard count > 0 else { return ColorGrade() }

        var histogram = [Int](repeating: 0, count: 256)
        for index in 0..<count {
            let offset = index * 4
            let luma = ScopeAnalyzer.luma(red: rgba[offset], green: rgba[offset + 1], blue: rgba[offset + 2])
            histogram[Swift.min(255, Swift.max(0, luma))] += 1
        }

        let lowTarget = Swift.max(1, Int(Double(count) * lowPercentile))
        let highTarget = Swift.max(1, Int(Double(count) * highPercentile))
        var cumulative = 0
        var black = 0
        for value in 0..<256 {
            cumulative += histogram[value]
            if cumulative >= lowTarget { black = value; break }
        }
        cumulative = 0
        var white = 255
        for value in 0..<256 {
            cumulative += histogram[value]
            if cumulative >= highTarget { white = value; break }
        }

        guard white > black + 5 else { return ColorGrade() }

        let blackNormalized = Double(black) / 255.0
        let whiteNormalized = Double(white) / 255.0
        let slope = 1.0 / (whiteNormalized - blackNormalized)
        let offset = -blackNormalized * slope

        return ColorGrade(
            lift: ColorGrade.RGB(red: offset, green: offset, blue: offset),
            gamma: 1,
            gain: ColorGrade.RGB(red: slope, green: slope, blue: slope)
        )
    }

    /// One-tap auto enhance: composes white balance (per-channel color gain) with
    /// auto levels (uniform contrast lift/gain) into a single grade — color cast
    /// removed and contrast stretched at once.
    ///
    /// Single pass: the channel sums (white balance) and the 256-bin luma
    /// histogram (levels) are accumulated over the SAME loop instead of
    /// walking the buffer once per sub-analyzer. Every downstream formula,
    /// guard, and fallback is byte-identical to composing the two standalone
    /// reducers.
    public static func autoEnhanceGrade(rgba: [UInt8]) -> ColorGrade {
        let count = rgba.count / 4
        guard count > 0 else { return ColorGrade() }

        var sumRed = 0.0
        var sumGreen = 0.0
        var sumBlue = 0.0
        var histogram = [Int](repeating: 0, count: 256)
        for index in 0..<count {
            let offset = index * 4
            let red = rgba[offset]
            let green = rgba[offset + 1]
            let blue = rgba[offset + 2]
            sumRed += Double(red)
            sumGreen += Double(green)
            sumBlue += Double(blue)
            let luma = ScopeAnalyzer.luma(red: red, green: green, blue: blue)
            histogram[Swift.min(255, Swift.max(0, luma))] += 1
        }

        // White-balance stage — math identical to ``autoWhiteBalanceGrade``.
        let averageRed = sumRed / Double(count)
        let averageGreen = sumGreen / Double(count)
        let averageBlue = sumBlue / Double(count)
        var balanceGainRed = 1.0
        var balanceGainGreen = 1.0
        var balanceGainBlue = 1.0
        if averageRed > 0, averageGreen > 0, averageBlue > 0 {
            let averageGray = (averageRed + averageGreen + averageBlue) / 3
            func gain(for channelAverage: Double) -> Double {
                Swift.min(Swift.max(averageGray / channelAverage, 0.5), 2.0)
            }
            balanceGainRed = gain(for: averageRed)
            balanceGainGreen = gain(for: averageGreen)
            balanceGainBlue = gain(for: averageBlue)
        }

        // Levels stage — math identical to ``autoLevelsGrade`` at the default
        // 0.02/0.98 percentiles.
        let lowTarget = Swift.max(1, Int(Double(count) * 0.02))
        let highTarget = Swift.max(1, Int(Double(count) * 0.98))
        var cumulative = 0
        var black = 0
        for value in 0..<256 {
            cumulative += histogram[value]
            if cumulative >= lowTarget { black = value; break }
        }
        cumulative = 0
        var white = 255
        for value in 0..<256 {
            cumulative += histogram[value]
            if cumulative >= highTarget { white = value; break }
        }

        var levelsLift = 0.0
        var levelsSlope = 1.0
        if white > black + 5 {
            let blackNormalized = Double(black) / 255.0
            let whiteNormalized = Double(white) / 255.0
            levelsSlope = 1.0 / (whiteNormalized - blackNormalized)
            levelsLift = -blackNormalized * levelsSlope
        }

        return ColorGrade(
            lift: ColorGrade.RGB(red: levelsLift, green: levelsLift, blue: levelsLift),
            gamma: 1,
            gain: ColorGrade.RGB(
                red: balanceGainRed * levelsSlope,
                green: balanceGainGreen * levelsSlope,
                blue: balanceGainBlue * levelsSlope
            )
        )
    }
}
