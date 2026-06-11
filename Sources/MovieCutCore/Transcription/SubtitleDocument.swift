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
}
