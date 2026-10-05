import Foundation

/// A rich, structured snapshot of a project passed to planning providers.
public struct ProjectContextSnapshot: Sendable, Equatable, Codable {
    /// The project identifier.
    public let projectId: UUID

    /// The exact session revision at the time this snapshot was captured.
    public let sessionRevision: SessionRevision

    /// The project schema version.
    public let schemaVersion: Int

    /// Current timeline duration in seconds.
    public let duration: TimeInterval

    /// Canvas settings and aspect ratio.
    public let canvas: CanvasPreset

    /// Total number of tracks on the timeline.
    public let trackCount: Int

    /// Total number of clips across all tracks.
    public let clipCount: Int

    /// Currently selected clip identifiers in the editor.
    public let selectedClipIds: [UUID]

    public init(
        projectId: UUID,
        sessionRevision: SessionRevision,
        schemaVersion: Int,
        duration: TimeInterval,
        canvas: CanvasPreset,
        trackCount: Int,
        clipCount: Int,
        selectedClipIds: [UUID] = []
    ) {
        self.projectId = projectId
        self.sessionRevision = sessionRevision
        self.schemaVersion = schemaVersion
        self.duration = duration
        self.canvas = canvas
        self.trackCount = trackCount
        self.clipCount = clipCount
        self.selectedClipIds = selectedClipIds
    }

    public init(from project: Project, revision: SessionRevision, selectedClipIds: [UUID] = []) {
        self.projectId = project.id
        self.sessionRevision = revision
        self.schemaVersion = project.schemaVersion
        self.duration = project.timeline.duration
        self.canvas = project.canvas
        self.trackCount = project.timeline.tracks.count
        self.clipCount = project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        self.selectedClipIds = selectedClipIds
    }
}
