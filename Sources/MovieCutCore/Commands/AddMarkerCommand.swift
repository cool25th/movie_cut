import Foundation

/// Adds a timeline marker to a project.
public struct AddMarkerCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var marker: Marker

    public init(id: UUID = UUID(), marker: Marker) {
        self.id = id
        self.marker = marker
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        guard !project.markers.contains(where: { $0.id == marker.id }) else {
            throw EditorCommandError.invalidCommand("Marker already exists: \(marker.id)")
        }

        project.markers.append(marker)

        if !project.timeline.markers.contains(where: { $0.id == marker.id }) {
            project.timeline.markers.append(marker)
        }

        return CommandResult(
            description: "Added marker \(marker.id)",
            undoValues: ["markerId": .uuid(marker.id)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .uuid(let markerId)? = result.undoValues["markerId"] {
            return DeleteMarkerCommand(markerId: markerId)
        }

        return DeleteMarkerCommand(markerId: marker.id)
    }
}

struct DeleteMarkerCommand: EditorCommand, Sendable, Codable {
    let id: UUID
    var markerId: UUID

    init(id: UUID = UUID(), markerId: UUID) {
        self.id = id
        self.markerId = markerId
    }

    func apply(to project: inout Project) throws -> CommandResult {
        let projectMarkerCount = project.markers.count
        let timelineMarkerCount = project.timeline.markers.count
        project.markers.removeAll { $0.id == markerId }
        project.timeline.markers.removeAll { $0.id == markerId }

        guard project.markers.count != projectMarkerCount || project.timeline.markers.count != timelineMarkerCount else {
            throw EditorCommandError.invalidCommand("Marker not found: \(markerId)")
        }

        return CommandResult(description: "Deleted marker \(markerId)")
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        NoOpCommand(description: "Missing marker snapshot for inverse")
    }
}
