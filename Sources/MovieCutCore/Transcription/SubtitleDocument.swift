import Foundation

/// Parses and serializes SubRip (.srt) subtitle documents using the same
/// `TranscriptionSegment` model the STT pipeline produces, so imported
/// subtitles flow through the existing pending-clip and burn-in paths.
public enum SubtitleDocument {
    /// Parses SRT text into ordered transcription segments.
    ///
    /// The parser is tolerant: the numeric index line is optional, CRLF and LF
    /// line endings are accepted, multi-line cue text is joined with newlines,
    /// and blocks without a valid `start --> end` timecode line are skipped.
    public static func parseSRT(_ text: String) -> [TranscriptionSegment] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")

        var segments: [TranscriptionSegment] = []
        for block in blocks {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }

            guard let timecodeIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  let (start, end) = parseTimecodeLine(lines[timecodeIndex])
            else {
                continue
            }

            let textLines = lines[(timecodeIndex + 1)...]
            let cueText = textLines.joined(separator: "\n")
            guard !cueText.isEmpty, end > start else { continue }

            segments.append(TranscriptionSegment(
                text: cueText,
                startTime: start,
                endTime: end,
                confidence: 1.0
            ))
        }

        return segments.sorted { $0.startTime < $1.startTime }
    }

    /// Serializes segments into SRT text. Segments are written in start-time
    /// order with 1-based indexes and `HH:MM:SS,mmm` timestamps.
    public static func srtString(from segments: [TranscriptionSegment]) -> String {
        let ordered = segments.sorted { $0.startTime < $1.startTime }
        var blocks: [String] = []
        for (index, segment) in ordered.enumerated() {
            let text = segment.text.isEmpty ? " " : segment.text
            blocks.append(
                """
                \(index + 1)
                \(srtTimestamp(from: segment.startTime)) --> \(srtTimestamp(from: segment.endTime))
                \(text)
                """
            )
        }
        return blocks.joined(separator: "\n\n") + (blocks.isEmpty ? "" : "\n")
    }

    /// Parses an `HH:MM:SS,mmm` (or `.mmm`) timestamp into seconds.
    public static func timeInterval(fromSRTTimestamp timestamp: String) -> TimeInterval? {
        let cleaned = timestamp
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]),
              hours >= 0, minutes >= 0, seconds >= 0
        else {
            return nil
        }

        return hours * 3600 + minutes * 60 + seconds
    }

    /// Formats seconds as an SRT `HH:MM:SS,mmm` timestamp.
    public static func srtTimestamp(from time: TimeInterval) -> String {
        let clamped = max(0, time)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let milliseconds = totalMilliseconds % 1000
        let totalSeconds = totalMilliseconds / 1000
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    private static func parseTimecodeLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2,
              let start = timeInterval(fromSRTTimestamp: parts[0]),
              let end = timeInterval(fromSRTTimestamp: parts[1])
        else {
            return nil
        }
        return (start, end)
    }

    // MARK: - WebVTT (.vtt)

    /// Serializes segments into WebVTT text. Segments are written in start-time
    /// order with `HH:MM:SS.mmm` timestamps and a leading `WEBVTT` header.
    ///
    /// Scope is text and timing only: no regional or styling metadata, no NOTE
    /// blocks, no cue identifiers.
    public static func vttString(from segments: [TranscriptionSegment]) -> String {
        let ordered = segments.sorted { $0.startTime < $1.startTime }
        var blocks: [String] = ["WEBVTT", ""]
        for segment in ordered {
            let text = segment.text.isEmpty ? " " : segment.text
            blocks.append(
                """
                \(vttTimestamp(from: segment.startTime)) --> \(vttTimestamp(from: segment.endTime))
                \(text)
                """
            )
        }
        // Join cues with blank lines. Trim the leading "WEBVTT\n\n" spacing so
        // an empty input yields "" rather than a stray header (mirrors srtString).
        guard ordered.isEmpty else {
            return blocks.joined(separator: "\n\n") + "\n"
        }
        return ""
    }

    /// Parses WebVTT text into ordered transcription segments.
    ///
    /// Tolerant like the SRT parser: `WEBVTT` header and optional `NOTE` blocks
    /// are skipped, optional cue identifier lines are ignored, `HH:MM:SS.mmm`
    /// and `MM:SS.mmm` timestamps are accepted (with optional trailing cue
    /// settings such as `align:start position:50%`), and multi-line cue text is
    /// joined with newlines.
    public static func parseVTT(_ text: String) -> [TranscriptionSegment] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")

        // Drop the leading "WEBVTT" header line if present.
        if let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           first.uppercased().hasPrefix("WEBVTT")
        {
            if let headerIndex = lines.firstIndex(of: first) {
                lines.removeFirst(headerIndex + 1)
            }
        }

        var segments: [TranscriptionSegment] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                index += 1
                continue
            }

            // Skip NOTE blocks (run until the next blank line).
            if line.hasPrefix("NOTE") {
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    index += 1
                }
                continue
            }

            // A cue may begin with an optional identifier line (no "-->").
            let timecodeLine: String
            if line.contains("-->") {
                timecodeLine = line
            } else {
                index += 1
                guard index < lines.count else { break }
                timecodeLine = lines[index].trimmingCharacters(in: .whitespaces)
            }

            guard let (start, end) = parseVTTTimecodeLine(timecodeLine) else {
                index += 1
                continue
            }

            index += 1
            var textLines: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                textLines.append(lines[index])
                index += 1
            }

            let cueText = textLines.joined(separator: "\n")
            guard !cueText.isEmpty, end > start else { continue }

            segments.append(TranscriptionSegment(
                text: cueText,
                startTime: start,
                endTime: end,
                confidence: 1.0
            ))
        }

        return segments.sorted { $0.startTime < $1.startTime }
    }

    /// Formats seconds as a WebVTT `HH:MM:SS.mmm` timestamp.
    public static func vttTimestamp(from time: TimeInterval) -> String {
        let clamped = max(0, time)
        let totalMilliseconds = Int((clamped * 1000).rounded())
        let milliseconds = totalMilliseconds % 1000
        let totalSeconds = totalMilliseconds / 1000
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }

    /// Parses a WebVTT `HH:MM:SS.mmm` (or `MM:SS.mmm`) timestamp into seconds.
    public static func timeInterval(fromVTTTimestamp timestamp: String) -> TimeInterval? {
        let cleaned = timestamp.trimmingCharacters(in: .whitespaces)
        let parts = cleaned.components(separatedBy: ":")
        guard let secondsPart = parts.last?.replacingOccurrences(of: ",", with: "."),
              let seconds = Double(secondsPart), seconds >= 0
        else {
            return nil
        }

        let numericPrefix = parts.dropLast().compactMap { Double($0) }
        let nonNegative = numericPrefix.allSatisfy { $0 >= 0 }
        guard numericPrefix.count == parts.count - 1, nonNegative else {
            return nil
        }

        // hours? minutes? seconds  ->  weigh right-to-left.
        var total = seconds
        var multiplier = 60.0
        for value in numericPrefix.reversed() {
            total += value * multiplier
            multiplier *= 60
        }
        return total
    }

    /// Splits a WebVTT cue timecode line (`start --> end` with optional
    /// trailing cue settings) into a `(start, end)` pair. Unlike the SRT
    /// timecode parser, this accepts the `MM:SS.mmm` form WebVTT permits.
    private static func parseVTTTimecodeLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }

        // The end token may carry trailing cue settings ("00:02.500 align:start").
        // Trim whitespace first, then drop everything from the first space onward.
        let startRaw = parts[0].trimmingCharacters(in: .whitespaces)
        let endTrimmed = parts[1].trimmingCharacters(in: .whitespaces)
        let endRaw = endTrimmed.components(separatedBy: " ").first ?? endTrimmed

        guard let start = timeInterval(fromVTTTimestamp: startRaw),
              let end = timeInterval(fromVTTTimestamp: endRaw)
        else {
            return nil
        }
        return (start, end)
    }

    // MARK: - Advanced SubStation Alpha (.ass)

    /// Serializes segments into Advanced SubStation Alpha text.
    ///
    /// Scope is text and timing only: a single hard-coded `Default` style is
    /// emitted, there is no per-clip style mapping, and no karaoke (`\k`)
    /// tags. Cue text newlines are encoded as ASS hard line breaks (`\N`).
    public static func assString(from segments: [TranscriptionSegment]) -> String {
        let ordered = segments.sorted { $0.startTime < $1.startTime }

        let header = """
        [Script Info]
        ; Script generated by MovieCut
        ScriptType: v4.00+
        WrapStyle: 0
        ScaledBorderAndShadow: yes
        YCbCr Matrix: TV.709
        PlayResX: 1920
        PlayResY: 1080

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,40,40,60,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """

        if ordered.isEmpty {
            return header + "\n"
        }

        var dialogues: [String] = [header]
        for segment in ordered {
            let text = segment.text.isEmpty
                ? " "
                : segment.text.replacingOccurrences(of: "\n", with: "\\N")
            let start = assTimestamp(from: segment.startTime)
            let end = assTimestamp(from: segment.endTime)
            // Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            dialogues.append(
                "Dialogue: 0,\(start),\(end),Default,,0,0,0,,\(text)"
            )
        }
        return dialogues.joined(separator: "\n") + "\n"
    }

    /// Parses Advanced SubStation Alpha text into ordered transcription
    /// segments.
    ///
    /// Only the `[Events]` `Dialogue:` rows are read. The `Format:` line
    /// drives column indexing so the Start/End/Text fields are located
    /// regardless of column order. ASS hard line breaks (`\N`) are decoded
    /// back to newlines.
    public static func parseASS(_ text: String) -> [TranscriptionSegment] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var formatColumns: [String] = []
        var segments: [TranscriptionSegment] = []
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Format:") {
                let payload = line.dropFirst("Format:".count)
                formatColumns = payload
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                continue
            }

            guard line.hasPrefix("Dialogue:") else { continue }
            guard let startIndex = formatColumns.firstIndex(of: "Start"),
                  let endIndex = formatColumns.firstIndex(of: "End"),
                  let textIndex = formatColumns.firstIndex(of: "Text")
            else {
                continue
            }

            let payload = String(line.dropFirst("Dialogue:".count))
            // Split into at most (textIndex + 1) fields so the Text column keeps
            // any embedded commas verbatim.
            let fieldCount = textIndex + 1
            let fields = splitKeepingTail(payload, maxFields: fieldCount)
            guard fields.count == fieldCount,
                  let start = timeInterval(fromASSTimestamp: fields[startIndex]),
                  let end = timeInterval(fromASSTimestamp: fields[endIndex])
            else {
                continue
            }

            let cueText = fields[textIndex]
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\\N", with: "\n")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\h", with: " ")
            guard !cueText.isEmpty, end > start else { continue }

            segments.append(TranscriptionSegment(
                text: cueText,
                startTime: start,
                endTime: end,
                confidence: 1.0
            ))
        }

        return segments.sorted { $0.startTime < $1.startTime }
    }

    /// Formats seconds as an ASS `H:MM:SS.cc` timestamp (single-digit hour,
    /// centisecond precision).
    public static func assTimestamp(from time: TimeInterval) -> String {
        let clamped = max(0, time)
        let totalCentiseconds = Int((clamped * 100).rounded())
        let centiseconds = totalCentiseconds % 100
        let totalSeconds = totalCentiseconds / 100
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }

    /// Parses an ASS `H:MM:SS.cc` timestamp into seconds.
    public static func timeInterval(fromASSTimestamp timestamp: String) -> TimeInterval? {
        let cleaned = timestamp
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]),
              hours >= 0, minutes >= 0, seconds >= 0
        else {
            return nil
        }

        return hours * 3600 + minutes * 60 + seconds
    }

    /// Splits `string` on commas into at most `maxFields` pieces, leaving the
    /// final piece as the un-split remainder (so commas inside the last field
    /// survive). Trims leading whitespace from each field.
    private static func splitKeepingTail(_ string: String, maxFields: Int) -> [String] {
        guard maxFields > 1 else { return [string] }
        var pieces: [String] = []
        var current = string.startIndex
        while pieces.count < maxFields - 1, let hit = string.range(of: ",", range: current..<string.endIndex) {
            pieces.append(String(string[current..<hit.lowerBound]))
            current = hit.upperBound
        }
        pieces.append(String(string[current..<string.endIndex]))
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
