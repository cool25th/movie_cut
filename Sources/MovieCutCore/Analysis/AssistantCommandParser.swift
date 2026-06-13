import Foundation

/// Which clips an assistant intent applies to (F-21).
public enum AssistantTarget: String, Sendable, Equatable {
    case selection
    case allClips
    case videoClips
    case audioClips
    case textClips
}

/// A rule-mapped editing action.
public enum AssistantAction: Sendable, Equatable {
    case applyFilter(EffectType)
    case removeFilters
    case setVolume(Double)
    case setFade(TimeInterval)
    case removeFade
    case adjustBrightness(Double)
    case adjustContrast(Double)
    case adjustSaturation(Double)
    case addMarker
}

/// A parsed natural-language editing instruction.
public struct AssistantIntent: Sendable, Equatable {
    public var target: AssistantTarget
    public var action: AssistantAction

    public init(target: AssistantTarget, action: AssistantAction) {
        self.target = target
        self.action = action
    }
}

/// The outcome of parsing one instruction.
public enum AssistantParseResult: Sendable, Equatable {
    case recognized(AssistantIntent)
    case unrecognized(suggestions: [String])
}

/// Rule-based natural-language → editing-intent mapper (F-21 step 1). No LLM
/// dependency: a synonym dictionary resolves a target and an action, plus an
/// optional numeric argument. Unrecognized input returns example suggestions.
public enum AssistantCommandParser {
    /// Example phrasings shown when an instruction is not understood.
    public static let exampleCommands: [String] = [
        "Apply a cinematic filter to all clips",
        "Remove all filters",
        "Mute all audio",
        "Set volume to 50%",
        "Add a 1 second fade to all clips",
        "Make everything brighter",
        "Increase contrast on all video",
        "Convert all clips to black and white",
        "Add a marker"
    ]

    public static func parse(_ rawText: String) -> AssistantParseResult {
        let text = rawText.lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unrecognized(suggestions: exampleCommands)
        }

        let target = resolveTarget(in: text)
        guard let action = resolveAction(in: text) else {
            return .unrecognized(suggestions: exampleCommands)
        }

        return .recognized(AssistantIntent(target: target, action: action))
    }

    // MARK: - Target

    private static func resolveTarget(in text: String) -> AssistantTarget {
        if contains(text, ["video"]) { return .videoClips }
        if contains(text, ["audio", "sound", "music", "voiceover"]) { return .audioClips }
        if contains(text, ["text", "title", "caption", "subtitle"]) { return .textClips }
        if contains(text, ["all ", "every", "everything", "whole timeline"]) { return .allClips }
        return .selection
    }

    // MARK: - Action

    private static func resolveAction(in text: String) -> AssistantAction? {
        // Marker.
        if contains(text, ["marker", "bookmark"]), contains(text, ["add", "place", "set", "drop"]) {
            return .addMarker
        }

        // Filters / looks: removal.
        if contains(text, ["remove", "clear", "delete", "no "]),
           contains(text, ["filter", "effect", "look"]) {
            return .removeFilters
        }

        // Black & white maps to the grayscale filter (not an adjustment).
        if contains(text, ["black and white", "grayscale", "greyscale", "monochrome"]) {
            return .applyFilter(.grayscale)
        }

        let hasAdjustVerb = contains(text, [
            "more", "less", "increase", "decrease", "reduce", "lower", "raise", "boost",
            "brighter", "darker", "brighten", "darken", "lighten", "dim"
        ])

        // Color adjustments take priority over filters only when an adjustment
        // verb is present (e.g. "make it more vivid" → saturation, but
        // "apply a vivid filter" → vivid LUT).
        if contains(text, ["bright", "brighter", "brighten", "lighten"]) {
            return .adjustBrightness(contains(text, ["less", "dim"]) ? -0.2 : 0.2)
        }
        if contains(text, ["darker", "darken", "dim"]) {
            return .adjustBrightness(-0.2)
        }
        if contains(text, ["contrast"]) {
            return .adjustContrast(contains(text, ["less", "lower", "reduce", "decrease"]) ? -0.2 : 0.2)
        }
        if contains(text, ["saturation", "saturate", "desaturate"])
            || (hasAdjustVerb && contains(text, ["vivid", "colorful", "vibrant"])) {
            return .adjustSaturation(contains(text, ["less", "lower", "desaturate", "reduce", "decrease"]) ? -0.2 : 0.2)
        }

        // Filters / looks: application.
        if let filter = resolveFilter(in: text) {
            return .applyFilter(filter)
        }

        // Volume / mute.
        if contains(text, ["mute", "silence"]) {
            return .setVolume(0)
        }
        if contains(text, ["unmute", "full volume", "max volume"]) {
            return .setVolume(1)
        }
        if contains(text, ["volume", "loud", "quieter", "louder"]),
           let fraction = firstFraction(in: text) {
            return .setVolume(min(max(fraction, 0), 2))
        }

        // Fade.
        if contains(text, ["fade"]) {
            if contains(text, ["remove", "no ", "clear", "delete"]) {
                return .removeFade
            }
            let seconds = firstSeconds(in: text) ?? 1.0
            return .setFade(seconds)
        }

        return nil
    }

    private static func resolveFilter(in text: String) -> EffectType? {
        if contains(text, ["cinematic", "movie", "film look", "teal", "blockbuster"]) { return .cinematicLUT }
        if contains(text, ["vintage", "retro", "old film", "nostalgic"]) { return .vintageLUT }
        if contains(text, ["noir", "moody", "dramatic"]) { return .noirLUT }
        if contains(text, ["vivid", "punchy", "pop"]) { return .vividLUT }
        if contains(text, ["cool tone", "cold", "blue tone", "icy"]) { return .coolLUT }
        if contains(text, ["sepia", "warm tone", "brown tone"]) { return .sepia }
        if contains(text, ["blur", "blurry", "soft focus"]) { return .blur }
        return nil
    }

    // MARK: - Number parsing

    /// Parses the first percentage or bare ratio into 0...n (50% → 0.5).
    static func firstFraction(in text: String) -> Double? {
        if let percent = firstMatch(in: text, pattern: #"(\d+(?:\.\d+)?)\s*%"#) {
            return percent / 100
        }
        if let value = firstMatch(in: text, pattern: #"(\d+(?:\.\d+)?)"#) {
            // A bare number after "to" is treated as a percentage if > 2.
            return value > 2 ? value / 100 : value
        }
        return nil
    }

    /// Parses the first seconds value ("2 seconds", "1.5s", "2 sec").
    static func firstSeconds(in text: String) -> TimeInterval? {
        firstMatch(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:s\b|sec|second)"#)
            ?? firstMatch(in: text, pattern: #"(\d+(?:\.\d+)?)"#)
    }

    private static func firstMatch(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[captureRange])
    }

    private static func contains(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
