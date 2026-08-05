import Foundation

/// Adds a timeline marker to a project.
public struct AddMarkerCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var marker: Marker

    public init(id: UUID = UUID(), marker: Marker) {
        self.id = id
        self.marker = marker
    }

    public func apply(to project: inout Project) throws {
        guard !project.markers.contains(where: { $0.id == marker.id }) else {
            throw EditorCommandError.invalidCommand("Marker already exists: \(marker.id)")
        }

        project.markers.append(marker)

        if !project.timeline.markers.contains(where: { $0.id == marker.id }) {
            project.timeline.markers.append(marker)
        }
    }

    }

/// Removes a timeline marker from both project and timeline marker collections.
public struct DeleteMarkerCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var markerId: UUID

    public init(id: UUID = UUID(), markerId: UUID) {
        self.id = id
        self.markerId = markerId
    }

    public func apply(to project: inout Project) throws {
        let projectMarker = project.markers.first { $0.id == markerId }
        let timelineMarker = project.timeline.markers.first { $0.id == markerId }
        let deletedMarker = projectMarker ?? timelineMarker
        let projectMarkerCount = project.markers.count
        let timelineMarkerCount = project.timeline.markers.count
        project.markers.removeAll { $0.id == markerId }
        project.timeline.markers.removeAll { $0.id == markerId }

        guard project.markers.count != projectMarkerCount || project.timeline.markers.count != timelineMarkerCount else {
            throw EditorCommandError.invalidCommand("Marker not found: \(markerId)")
        }

    }

    }

/// Updates a timeline marker while preserving its identifier.
public struct UpdateMarkerCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var markerId: UUID
    public var marker: Marker

    public init(id: UUID = UUID(), markerId: UUID, marker: Marker) {
        self.id = id
        self.markerId = markerId
        self.marker = marker
    }

    public func apply(to project: inout Project) throws {
        let updatedMarker = Marker(
            id: markerId,
            time: marker.time,
            name: marker.name,
            color: marker.color
        )
        let previousProjectMarker = project.markers.first { $0.id == markerId }
        let previousTimelineMarker = project.timeline.markers.first { $0.id == markerId }
        let previousMarker = previousProjectMarker ?? previousTimelineMarker

        guard previousMarker != nil else {
            throw EditorCommandError.invalidCommand("Marker not found: \(markerId)")
        }

        if let index = project.markers.firstIndex(where: { $0.id == markerId }) {
            project.markers[index] = updatedMarker
        }

        if let index = project.timeline.markers.firstIndex(where: { $0.id == markerId }) {
            project.timeline.markers[index] = updatedMarker
        }
    }

    }
