import Foundation

/// P3 increment 3 — the local planner: a deterministic, offline rule-based
/// translator from natural-language instructions (ko/en) to typed
/// `EditingActionDSL.Action`s. This is the "agent can be local" layer: no
/// LLM, no network, no guessing — an instruction either maps to typed
/// actions with a recorded rationale, or it is REJECTED with a typed error
/// (fail-closed, the same discipline as the kernel's decode).
///
/// v1 grammar (each rule tested in both languages):
///   split            "3초에서 잘라" / "split at 3s"
///   range deletion   "2초부터 6초까지 삭제" / "delete 2s to 6s"
///   keep-only range  "2초부터 6초까지만 남겨" / "keep only 2 to 6s"
///   volume           "볼륨 50%" / "볼륨 절반" / "set volume to 0.5"
///   speed            "2배속" / "set speed to 0.5x"
///   audio preset     "음성 강조 적용" / "apply voice enhance"
///   duck background  "배경음악 덱킹해줘" / "duck the background music"
///   remove silence   "무음 제거해줘" / "remove the silence"
///
/// Clip targeting: ordinals over the timeline-flattened clip list
/// ("첫 번째 클립" / "마지막 클립" / "두 번째" / "clip 2" / "last clip"); when
/// no target is stated, clip rules default to the longest clip (the least
/// surprising target) — the chosen target is always named in the rationale
/// so the caller can show it before apply (§1.5 previewability).
///
/// Time literals carry units ("초"/"s", "분"/"m"); bare numbers are operands
/// (volumes, speeds, ordinals), never times.
public enum EditingIntentPlanner {

    /// Why an instruction cannot be planned — typed, never a free string.
    public enum PlannerError: Error, Equatable, Sendable {
        /// No rule matched; the instruction is echoed back verbatim.
        case unrecognized(String)
        /// The timeline has no clips to target.
        case noClips
        /// The ordinal is out of range (1...clipCount).
        case clipOrdinal(Int, count: Int)
        /// A time was expected but none was found.
        case noTime
    }

    /// A planned instruction: typed actions plus one rationale line per
    /// action (what was understood and which clip was targeted — the
    /// explanation the preview surface shows before applying).
    public struct Result: Equatable, Sendable {
        public let actions: [EditingActionDSL.Action]
        public let rationale: [String]

        init(actions: [EditingActionDSL.Action], rationale: [String]) {
            self.actions = actions
            self.rationale = rationale
        }
    }

    // MARK: - Entry

    /// Plans one instruction against the project. Pure — no mutation, no
    /// session; feed the result to `EditingActionApplier` to apply.
    public static func plan(
        instruction: String,
        for project: Project
    ) throws -> Result {
        let clips = project.timeline.tracks
            .flatMap(\.clips)
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
        guard !clips.isEmpty else { throw PlannerError.noClips }

        let text = normalize(instruction)
        let allTimes = times(in: text)

        // --- split (single time) ---
        if matches(text, ["잘라", "분할", "split", "cutat"]) {
            guard let at = allTimes.first else { throw PlannerError.noTime }
            let target = try defaultClip(in: clips)
            return Result(
                actions: [.splitClip(clipId: target.clip.id, time: at)],
                rationale: ["split clip #\(target.index) at \(at)초"]
            )
        }

        // --- range intents (two times, whole-timeline) ---
        if allTimes.count >= 2 {
            let sorted = [allTimes[0], allTimes[1]].sorted()
            let (lower, upper) = (sorted[0], sorted[1])
            if matches(text, ["까지만남겨", "만남겨", "keeponly", "onlykeep"]) {
                return Result(
                    actions: [.keepTimelineRange(start: lower, end: upper)],
                    rationale: ["keep-only [\(lower), \(upper))초 구간만 유지"]
                )
            }
            if matches(text, ["삭제", "지워", "제거", "delete", "remove"]) {
                return Result(
                    actions: [.deleteTimelineRange(start: lower, end: upper)],
                    rationale: ["delete [\(lower), \(upper))초 구간 제거"]
                )
            }
        }

        // --- clip-property intents (volume / speed / preset) ---
        if matches(text, ["볼륨", "소리줘", "volume"]) {
            let value = volumeValue(in: text)
            let target = try targetedClip(in: text, clips: clips)
            return Result(
                actions: [.setVolume(clipId: target.clip.id, volume: value)],
                rationale: ["volume of clip #\(target.index) → \(value)"]
            )
        }
        if matches(text, ["배속", "속도", "speed"]) {
            guard let rate = rateValue(in: text) else { throw PlannerError.unrecognized(instruction) }
            let target = try targetedClip(in: text, clips: clips)
            return Result(
                actions: [.setSpeed(clipId: target.clip.id, rate: rate)],
                rationale: ["speed of clip #\(target.index) → \(rate)x"]
            )
        }
        if let preset = presetValue(in: text) {
            let target = try targetedClip(in: text, clips: clips)
            return Result(
                actions: [.applyAudioPreset(clipId: target.clip.id, preset: preset)],
                rationale: ["EQ preset of clip #\(target.index) → \(preset.rawValue)"]
            )
        }

        // --- analysis intents ---
        if matches(text, ["덕킹", "duck"]) {
            let target = try targetedClip(in: text, clips: clips)
            return Result(
                actions: [.duckBackground(speechClipId: target.clip.id)],
                rationale: ["duck background under clip #\(target.index)"]
            )
        }
        if matches(text, ["무음", "침묵", "silence"]) {
            let target = try targetedClip(in: text, clips: clips)
            return Result(
                actions: [.removeSilence(clipId: target.clip.id)],
                rationale: ["remove silence in clip #\(target.index)"]
            )
        }

        throw PlannerError.unrecognized(instruction)
    }

    // MARK: - Text helpers

    /// Lowercased, whitespace-stripped form for matching (Korean particles
    /// survive as substrings after this normalization).
    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .filter { !$0.isWhitespace }
    }

    private static func matches(_ normalized: String, _ keys: [String]) -> Bool {
        keys.contains { normalized.contains($0) }
    }

    /// All time literals in seconds: "1분 30초" → 90, "90초"/"90s" → 90,
    /// "1m30s" → 90, "1.5s" → 1.5. Bare numbers are NOT times.
    private static func times(in text: String) -> [Double] {
        var results: [Double] = []
        var pendingSeconds = 0.0
        var index = text.startIndex

        while index < text.endIndex {
            let ch = text[index]
            if ch.isNumber || ch == "." {
                var digits = ""
                var scan = index
                while scan < text.endIndex, text[scan].isNumber || text[scan] == "." {
                    digits.append(text[scan])
                    scan = text.index(after: scan)
                }
                let after = scan < text.endIndex ? text[scan] : " "
                if let value = Double(digits), digits.contains(where: \.isNumber) {
                    if after == "분" || after == "m" {
                        pendingSeconds += value * 60
                    } else if after == "초" || after == "s" {
                        results.append(value + pendingSeconds)
                        pendingSeconds = 0
                        scan = text.index(after: scan)
                    } else {
                        pendingSeconds = 0
                    }
                }
                index = scan
            } else {
                index = text.index(after: index)
            }
        }
        return results
    }

    /// Volume: "절반/반으로" → 0.5, "N%" → N/100, plain ≤2 → as-is,
    /// larger numbers read as percent ("볼륨 150" → 1.5).
    private static func volumeValue(in text: String) -> Double {
        if text.contains("절반") || text.contains("반으로") { return 0.5 }
        if let pct = percentNumber(in: text) { return min(pct / 100, 2) }
        if let n = lastNumber(in: text) { return n <= 2 ? n : min(n / 100, 2) }
        return 1.0
    }

    /// Speed: "N%" → N/100 (≥0.1), otherwise the last number clamped to
    /// 0.1...10 (the kernel's own validity window).
    private static func rateValue(in text: String) -> Double? {
        if let pct = percentNumber(in: text) { return max(pct / 100, 0.1) }
        guard let n = lastNumber(in: text) else { return nil }
        return min(max(n, 0.1), 10)
    }

    private static func percentNumber(in text: String) -> Double? {
        guard let percentIndex = text.firstIndex(of: "%") else { return nil }
        return lastNumber(in: String(text[..<percentIndex]))
    }

    /// The last numeric token — the operand nearest the intent keyword in
    /// every grammar form this planner accepts.
    private static func lastNumber(in text: String) -> Double? {
        var value: Double?
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch.isNumber || ch == "." {
                var digits = ""
                var scan = index
                while scan < text.endIndex, text[scan].isNumber || text[scan] == "." {
                    digits.append(text[scan])
                    scan = text.index(after: scan)
                }
                if let parsed = Double(digits), digits.contains(where: \.isNumber) {
                    value = parsed
                }
                index = scan
            } else {
                index = text.index(after: index)
            }
        }
        return value
    }

    private static func presetValue(in text: String) -> EqualizerPresetID? {
        if matches(text, ["voiceenhance", "음성강조", "보이스"]) { return .voiceEnhance }
        if matches(text, ["bassboost", "베이스", "저음"]) { return .bassBoost }
        if matches(text, ["trebleboost", "트레블", "고음"]) { return .trebleBoost }
        if matches(text, ["flat", "플랫", "초기화"]) { return .flat }
        return nil
    }

    // MARK: - Clip targeting

    private static func targetedClip(in text: String, clips: [Clip]) throws -> (clip: Clip, index: Int) {
        if let ordinal = ordinal(in: text, count: clips.count) {
            guard (1...clips.count).contains(ordinal) else {
                throw PlannerError.clipOrdinal(ordinal, count: clips.count)
            }
            return (clips[ordinal - 1], ordinal)
        }
        return try defaultClip(in: clips)
    }

    /// The longest clip is the default target — the least surprising choice
    /// for "the main footage" and never an accidental micro-clip.
    private static func defaultClip(in clips: [Clip]) throws -> (clip: Clip, index: Int) {
        guard let clip = clips.max(by: { $0.timelineRange.duration < $1.timelineRange.duration }) else {
            throw PlannerError.noClips
        }
        return (clip, clips.firstIndex(where: { $0.id == clip.id }).map { $0 + 1 } ?? 0)
    }

    /// 1-based ordinal from "첫/first" → 1, "마지막/last" → count, or the
    /// number written INTO an ordinal marker ("N번째", "Nth", "clip N") —
    /// never a free-floating number (that is the operand's namespace).
    private static func ordinal(in text: String, count: Int) -> Int? {
        if text.contains("첫") || text.contains("first") { return 1 }
        if text.contains("마지막") || text.contains("last") { return count }

        // Digits immediately BEFORE "번째" or "th".
        for marker in ["번째", "th"] {
            if let range = text.range(of: marker) {
                let before = text[..<range.lowerBound]
                if let n = digitsAtEnd(of: before) { return n }
            }
        }
        // Digits immediately AFTER "clip".
        if let range = text.range(of: "clip") {
            let after = text[range.upperBound...]
            if let n = digitsAtStart(of: after) { return n }
        }
        return nil
    }

    private static func digitsAtEnd(of s: Substring) -> Int? {
        var index = s.endIndex
        var digits = ""
        while index > s.startIndex {
            let prev = s.index(before: index)
            if s[prev].isNumber {
                digits.insert(s[prev], at: digits.startIndex)
                index = prev
            } else {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func digitsAtStart(of s: Substring) -> Int? {
        var digits = ""
        var index = s.startIndex
        while index < s.endIndex, s[index].isNumber {
            digits.append(s[index])
            index = s.index(after: index)
        }
        return digits.isEmpty ? nil : Int(digits)
    }
}
