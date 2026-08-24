import Foundation

/// Parses user-typed timecode strings into timeline seconds.
///
/// Accepted forms (whitespace-trimmed, colon-separated):
/// - `"SS"` / `"SS.f"` — seconds only (`"5"`, `"5.5"`)
/// - `"MM:SS"` / `"MM:SS.f"` (`"1:30"`, `"1:30.5"`)
/// - `"MM:SS:FF"` — the 3-field form is ALWAYS minutes : seconds : frames
///   at the given frame rate (the on-screen badge format); there is no
///   3-field hours form
/// - `"HH:MM:SS:FF"` — hours need the 4-field form
///
/// Frames fields (`FF`) accept whole frame numbers only; fractional input is
/// legal solely in the seconds position of the 1- and 2-field forms.
///
/// The frame rate, every parsed field, and the final computed seconds must
/// all be finite — `"inf"`, `"nan"`, `"1e309"`, and inputs whose arithmetic
/// overflows are rejected explicitly.
///
/// Returns `nil` for anything else (empty, non-numeric, negative, frames ≥
/// frame rate, or fractional fields other than the trailing seconds) so
/// callers can fail explicitly instead of guessing a position — invalid
/// input must never silently seek to 0.
public enum TimecodeParser {
    public static func seconds(from input: String, frameRate: Double) -> TimeInterval? {
        // `frameRate > 0` alone admits +inf; only isFinite excludes it.
        guard frameRate.isFinite, frameRate > 0 else { return nil }
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-") else { return nil }

        let components = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...4).contains(components.count) else { return nil }

        var numbers: [Double] = []
        for (index, component) in components.enumerated() {
            // Double() happily parses "inf", "infinity", "nan", and "1e309"
            // (→ +inf); only the isFinite check keeps them out.
            guard let value = Double(component), value.isFinite, value >= 0 else { return nil }
            let isLast = index == components.count - 1
            // Fractional input is only meaningful in the trailing SECONDS
            // field of the 1- and 2-field forms; a trailing FRAMES field
            // (3- and 4-field forms) is a whole frame number by definition.
            let lastFieldAcceptsFractions = isLast && components.count <= 2
            guard value.rounded() == value || lastFieldAcceptsFractions else { return nil }
            numbers.append(value)
        }

        // Every composition below must stay finite: a huge hours field
        // ("1e308:00:00:00") parses field-by-field but overflows when scaled.
        switch numbers.count {
        case 1:
            let result = numbers[0]
            return result.isFinite ? result : nil
        case 2:
            let result = numbers[0] * 60 + numbers[1]
            return result.isFinite ? result : nil
        case 3:
            // MM:SS:FF — the frames field must be a whole count below fps.
            // For NTSC-style rates the largest displayable frame is the
            // largest whole number strictly below the rate (29 at 29.97,
            // 23 at 23.976) — the raw `< frameRate` comparison already
            // admits it; do NOT round the rate down to an integer first.
            guard numbers[2] < frameRate else { return nil }
            let result = numbers[0] * 60 + numbers[1] + numbers[2] / frameRate
            return result.isFinite ? result : nil
        case 4:
            guard numbers[3] < frameRate else { return nil }
            let result = numbers[0] * 3600 + numbers[1] * 60 + numbers[2] + numbers[3] / frameRate
            return result.isFinite ? result : nil
        default:
            return nil
        }
    }
}
