import Foundation

/// Adds many markers in one dispatch (single undo unit). Used by beat
/// detection (F-15), which can produce hundreds of markers per track.
public struct AddMarkersCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var markers: [Marker]

    public init(id: UUID = UUID(), markers: [Marker]) {
        self.id = id
        self.markers = markers
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        guard !markers.isEmpty else {
            throw EditorCommandError.invalidCommand("No markers to add.")
        }

        let existingIds = Set(project.markers.map(\.id))
        let newMarkers = markers.filter { !existingIds.contains($0.id) }
        guard !newMarkers.isEmpty else {
            throw EditorCommandError.invalidCommand("All markers already exist.")
        }

        project.markers.append(contentsOf: newMarkers)
        let timelineIds = Set(project.timeline.markers.map(\.id))
        project.timeline.markers.append(contentsOf: newMarkers.filter { !timelineIds.contains($0.id) })

        return CommandResult(
            description: "Added \(newMarkers.count) markers",
            undoValues: ["markers": .markers(newMarkers)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .markers(let added)? = result.undoValues["markers"] {
            return RemoveMarkersCommand(markerIds: added.map(\.id))
        }
        return RemoveMarkersCommand(markerIds: markers.map(\.id))
    }
}

/// Removes markers in one dispatch, either by explicit ids or by kind
/// (e.g. clearing every generated beat marker).
public struct RemoveMarkersCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var markerIds: [UUID]?
    public var kind: MarkerKind?

    /// Removes the listed markers.
    public init(id: UUID = UUID(), markerIds: [UUID]) {
        self.id = id
        self.markerIds = markerIds
        self.kind = nil
    }

    /// Removes every marker of the given kind.
    public init(id: UUID = UUID(), kind: MarkerKind) {
        self.id = id
        self.markerIds = nil
        self.kind = kind
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let removed: [Marker]
        if let markerIds {
            let ids = Set(markerIds)
            removed = project.markers.filter { ids.contains($0.id) }
        } else if let kind {
            removed = project.markers.filter { $0.kind == kind }
        } else {
            throw EditorCommandError.invalidCommand("Specify marker ids or a marker kind to remove.")
        }

        guard !removed.isEmpty else {
            throw EditorCommandError.invalidCommand("No matching markers to remove.")
        }

        let removedIds = Set(removed.map(\.id))
        project.markers.removeAll { removedIds.contains($0.id) }
        project.timeline.markers.removeAll { removedIds.contains($0.id) }

        return CommandResult(
            description: "Removed \(removed.count) markers",
            undoValues: ["markers": .markers(removed)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .markers(let removed)? = result.undoValues["markers"] {
            return AddMarkersCommand(markers: removed)
        }
        return NoOpCommand(description: "Missing removed markers for inverse")
    }
}
