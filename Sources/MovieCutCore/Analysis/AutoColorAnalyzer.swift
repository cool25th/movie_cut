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
}
