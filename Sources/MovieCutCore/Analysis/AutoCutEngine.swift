import Foundation

/// Converts analysis suggestions into editor commands.
public struct AutoCutEngine: Sendable {
    /// Builds edit commands for the supplied suggestions using the current session project.
    public static func apply(
        suggestions: [AnalysisSuggestion],
        to session: isolated EditorSession
    ) throws -> [any EditorCommand] {
        var project = session.project
        var commands: [any EditorCommand] = []
        try buildCommands(for: suggestions, to: &project, commands: &commands)
        return commands
    }

    /// Applies the suggestions directly to a project in place. Used by
    /// `AutoCutCommand` so an entire auto-cut pass is a single undo unit
    /// (F-18 AC③).
    public static func applyInline(
        suggestions: [AnalysisSuggestion],
        to project: inout Project
    ) throws {
        var commands: [any EditorCommand] = []
        try buildCommands(for: suggestions, to: &project, commands: &commands)
    }

    private static func buildCommands(
        for suggestions: [AnalysisSuggestion],
        to project: inout Project,
        commands: inout [any EditorCommand]
    ) throws {
        for suggestion in suggestions {
            switch suggestion {
            case .silenceRemoval(let ranges):
                try appendRemovalCommands(for: ranges, to: &project, commands: &commands)
            case .sceneChanges(let times):
                try appendSplitCommands(at: times, to: &project, commands: &commands)
            case .autoCut(let editedRanges):
                try appendRemovalCommands(for: editedRanges, to: &project, commands: &commands)
            }
        }
    }

    private static func appendRemovalCommands(
        for ranges: [TimeRange],
        to project: inout Project,
        commands: inout [any EditorCommand]
    ) throws {
        for range in normalizedRanges(ranges) where range.duration > 0 {
            try appendSplitCommands(at: [range.start, range.end], to: &project, commands: &commands)

            for clipReference in clips(in: range, project: project) {
                let command = DeleteClipCommand(clipId: clipReference.clipId)
                try append(command, to: &project, commands: &commands)
            }
        }
    }

    private static func appendSplitCommands(
        at times: [TimeInterval],
        to project: inout Project,
        commands: inout [any EditorCommand]
    ) throws {
        for time in normalizedTimes(times) {
            for clipReference in clips(crossing: time, project: project) {
                let command = SplitClipCommand(
                    clipId: clipReference.clipId,
                    trackId: clipReference.trackId,
                    splitTime: time
                )
                try append(command, to: &project, commands: &commands)
            }
        }
    }

    private static func append(
        _ command: any EditorCommand,
        to project: inout Project,
        commands: inout [any EditorCommand]
    ) throws {
        _ = try command.apply(to: &project)
        commands.append(command)
    }

    private static func clips(crossing time: TimeInterval, project: Project) -> [ClipReference] {
        var references: [ClipReference] = []

        for track in project.timeline.tracks {
            for clip in track.clips where time > clip.timelineRange.start && time < clip.timelineRange.end {
                references.append(ClipReference(trackId: track.id, clipId: clip.id))
            }
        }

        return references
    }

    private static func clips(in range: TimeRange, project: Project) -> [ClipReference] {
        var references: [ClipReference] = []

        for track in project.timeline.tracks {
            for clip in track.clips where clip.timelineRange.duration > 0 {
                if clip.timelineRange.start >= range.start && clip.timelineRange.end <= range.end {
                    references.append(ClipReference(trackId: track.id, clipId: clip.id))
                }
            }
        }

        return references
    }

    private static func normalizedTimes(_ times: [TimeInterval]) -> [TimeInterval] {
        Array(Set(times.filter { $0.isFinite })).sorted()
    }

    private static func normalizedRanges(_ ranges: [TimeRange]) -> [TimeRange] {
        let sortedRanges = ranges
            .filter { $0.start.isFinite && $0.duration.isFinite && $0.duration > 0 }
            .sorted { $0.start < $1.start }

        var normalized: [TimeRange] = []
        for range in sortedRanges {
            guard var lastRange = normalized.popLast() else {
                normalized.append(range)
                continue
            }

            if range.start <= lastRange.end {
                let end = max(lastRange.end, range.end)
                lastRange.duration = end - lastRange.start
                normalized.append(lastRange)
            } else {
                normalized.append(lastRange)
                normalized.append(range)
            }
        }

        return normalized
    }
}

private struct ClipReference: Sendable {
    var trackId: UUID
    var clipId: UUID
}
