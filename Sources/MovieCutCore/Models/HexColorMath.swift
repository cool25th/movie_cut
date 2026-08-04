import Foundation

/// Pure hex-string ↔ RGB math shared across core processors and both app targets.
///
/// Several call sites previously kept private copies of this parsing
/// (ChromaKeyPixelProcessor, TextOverlayPixelProcessor,
/// CanvasBackgroundPixelProcessor, Clip, and the Mac/iOS ChromaKey views).
/// All of them reduce to the same UInt64 bit-shift over "#RRGGBB"; this type
/// owns that rule once and hands back `Double` components each caller adapts.
public enum HexColorMath {
    /// Parses "#RRGGBB" or "RRGGBB" into normalized (red, green, blue) in 0...1.
    public static func rgb(fromHex hex: String) -> (red: Double, green: Double, blue: Double)? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else {
            return nil
        }

        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Formats normalized RGB components (0...1) as "#RRGGBB".
    public static func hexRGB(red: Double, green: Double, blue: Double) -> String {
        String(
            format: "#%02X%02X%02X",
            byteValue(red),
            byteValue(green),
            byteValue(blue)
        )
    }

    private static func byteValue(_ component: Double) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }
}
