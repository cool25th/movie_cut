import Foundation

/// Parses user-typed timecode strings into timeline seconds.
///
/// Accepted forms (whitespace-trimmed, colon-separated):
/// - `"SS"` / `"SS.f"` — seconds only (`"5"`, `"5.5"`)
/// - `"MM:SS"` / `"MM:SS.f"` (`"1:30"`, `"1:30.5"`)
/// - `"MM:SS:FF"` — frames interpreted at the given frame rate
/// - `"HH:MM:SS"` / `"HH:MM:SS:FF"`
///
/// Returns `nil` for anything else (empty, non-numeric, negative, frames ≥
/// frame rate, or fractional fields other than the last) so callers can
/// fail explicitly instead of guessing a position — invalid input must
/// never silently seek to 0.
public enum TimecodeParser {
    public static func seconds(from input: String, frameRate: Double) -> TimeInterval? {
        guard frameRate > 0 else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-") else { return nil }

        let components = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...4).contains(components.count) else { return nil }

        var numbers: [Double] = []
        for (index, component) in components.enumerated() {
            guard let value = Double(component), value >= 0 else { return nil }
            // Fractional input is only meaningful in the final (most precise) field.
            let isLast = index == components.count - 1
            guard value.rounded() == value || isLast else { return nil }
            numbers.append(value)
        }

        switch numbers.count {
        case 1:
            return numbers[0]
        case 2:
            return numbers[0] * 60 + numbers[1]
        case 3:
            // MM:SS:FF — the frames field must be a whole count below fps.
            guard numbers[2] < frameRate else { return nil }
            return numbers[0] * 60 + numbers[1] + numbers[2] / frameRate
        case 4:
            guard numbers[3] < frameRate else { return nil }
            return numbers[0] * 3600 + numbers[1] * 60 + numbers[2] + numbers[3] / frameRate
        default:
            return nil
        }
    }
}
