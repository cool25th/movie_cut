import Foundation

/// Removes the supplied timeline ranges (and splits at their boundaries) in a
/// single dispatch so the whole auto-cut pass is one undo unit (F-18 AC③).
public struct AutoCutCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// Timeline-space ranges to remove.
    public var removableRanges: [TimeRange]

    /// Creates an auto-cut command from removable timeline ranges.
    public init(id: UUID = UUID(), removableRanges: [TimeRange]) {
        self.id = id
        self.removableRanges = removableRanges
    }

    public func apply(to project: inout Project) throws {
        let ranges = removableRanges.filter { $0.duration > 0 }
        guard !ranges.isEmpty else {
            throw EditorCommandError.invalidCommand("No removable ranges supplied for auto cut.")
        }

        try AutoCutEngine.applyInline(
            suggestions: [.silenceRemoval(ranges: ranges)],
            to: &project
        )
    }

    }
