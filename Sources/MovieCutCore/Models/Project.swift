import Foundation

/// The top-level document model for a MovieCut project.
public struct Project: Codable, Sendable, Equatable, Identifiable {
    /// The project identifier.
    public var id: UUID

    /// The user-visible project name.
    public var name: String

    /// The project creation date.
    public var createdAt: Date

    /// The most recent project update date.
    public var updatedAt: Date

    /// The app version that last wrote the project.
    public var appVersion: String

    /// The project schema version.
    public var schemaVersion: Int

    /// Imported media assets referenced by the timeline.
    public var mediaLibrary: MediaLibrary

    /// The editable timeline.
    public var timeline: Timeline

    /// Default export settings for the project.
    public var exportSettings: ExportSettings

    /// Creates a project with Phase 0 defaults.
    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        appVersion: String = "0.1.0",
        schemaVersion: Int = 1,
        mediaLibrary: MediaLibrary = MediaLibrary(),
        timeline: Timeline = Timeline(),
        exportSettings: ExportSettings = ExportSettings()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.appVersion = appVersion
        self.schemaVersion = schemaVersion
        self.mediaLibrary = mediaLibrary
        self.timeline = timeline
        self.exportSettings = exportSettings
    }
}
