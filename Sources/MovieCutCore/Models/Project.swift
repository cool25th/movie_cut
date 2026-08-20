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

    /// User-defined project timeline markers.
    public var markers: [Marker] = []

    /// The project's editing canvas.
    public var canvas: CanvasPreset

    /// Default export settings for the project.
    public var exportSettings: ExportSettings

    /// Optional canvas background fill behind video frames. Nil renders the
    /// historical solid black canvas.
    public var canvasBackground: CanvasBackground?

    /// Optional card-news document. Nil preserves legacy timeline-only projects.
    public var cardDocument: CardDocument?

    /// Editing preview (playback) settings. Defaults to proxy playback off.
    public var playbackSettings: PlaybackSettings

    /// Compound-clip definitions (Requirement 7). Empty for projects predating
    /// the field, which decode to `[]` so compound-free legacy files stay
    /// byte-identical. Each `Clip.compoundId` references an entry here. The
    /// schema version is intentionally not bumped for this additive field;
    /// the bump is deferred to task 6.
    public var compounds: [CompoundDefinition]

    /// G-26: the project's master audio processing preset. The graph
    /// builder expands this into the spec's master bus — the chain's FULL
    /// parameters plus the §6 preset algorithm version — so the renderers
    /// consume serialized values, never a hardcoded preset. Nil (the
    /// default, and what legacy projects decode to) means no master
    /// processing; persisted only when set.
    public var masterAudioProcessing: MasterAudioProcessing?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case updatedAt
        case appVersion
        case schemaVersion
        case mediaLibrary
        case timeline
        case markers
        case canvas
        case exportSettings
        case canvasBackground
        case cardDocument
        case playbackSettings
        case compounds
        case masterAudioProcessing
    }

    /// Creates a project with Phase 0 defaults.
    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        appVersion: String = "0.1.0",
        schemaVersion: Int = currentSchemaVersion,
        mediaLibrary: MediaLibrary = MediaLibrary(),
        timeline: Timeline = Timeline(),
        markers: [Marker] = [],
        canvas: CanvasPreset = CanvasPreset.defaultPreset(),
        exportSettings: ExportSettings = ExportSettings(),
        canvasBackground: CanvasBackground? = nil,
        cardDocument: CardDocument? = nil,
        playbackSettings: PlaybackSettings = PlaybackSettings(),
        compounds: [CompoundDefinition] = [],
        masterAudioProcessing: MasterAudioProcessing? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.appVersion = appVersion
        self.schemaVersion = schemaVersion
        self.mediaLibrary = mediaLibrary
        self.timeline = timeline
        self.markers = markers
        self.canvas = canvas
        self.exportSettings = exportSettings
        self.canvasBackground = canvasBackground
        self.cardDocument = cardDocument
        self.playbackSettings = playbackSettings
        self.compounds = compounds
        self.masterAudioProcessing = masterAudioProcessing
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        mediaLibrary = try container.decode(MediaLibrary.self, forKey: .mediaLibrary)
        timeline = try container.decode(Timeline.self, forKey: .timeline)
        markers = try container.decodeIfPresent([Marker].self, forKey: .markers) ?? []
        canvas = try container.decodeIfPresent(CanvasPreset.self, forKey: .canvas) ?? CanvasPreset.defaultPreset()
        exportSettings = try container.decode(ExportSettings.self, forKey: .exportSettings)
        canvasBackground = try container.decodeIfPresent(CanvasBackground.self, forKey: .canvasBackground)
        cardDocument = try container.decodeIfPresent(CardDocument.self, forKey: .cardDocument)
        playbackSettings = try container.decodeIfPresent(PlaybackSettings.self, forKey: .playbackSettings) ?? PlaybackSettings()
        // decodeIfPresent ?? [] so compound-free legacy projects stay byte-
        // identical and partial payloads still load. The schema bump is
        // deferred to task 6.
        compounds = try container.decodeIfPresent([CompoundDefinition].self, forKey: .compounds) ?? []
        masterAudioProcessing = try container.decodeIfPresent(MasterAudioProcessing.self, forKey: .masterAudioProcessing)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(mediaLibrary, forKey: .mediaLibrary)
        try container.encode(timeline, forKey: .timeline)
        try container.encode(markers, forKey: .markers)
        try container.encode(canvas, forKey: .canvas)
        try container.encode(exportSettings, forKey: .exportSettings)
        try container.encodeIfPresent(canvasBackground, forKey: .canvasBackground)
        try container.encodeIfPresent(cardDocument, forKey: .cardDocument)
        try container.encode(playbackSettings, forKey: .playbackSettings)
        // Persist compounds only when non-empty so a compound-free project
        // stays byte-identical to its pre-feature JSON (Requirement 7.6).
        if !compounds.isEmpty {
            try container.encode(compounds, forKey: .compounds)
        }
        try container.encodeIfPresent(masterAudioProcessing, forKey: .masterAudioProcessing)
    }
}
