import Foundation

/// A reusable project template definition.
public struct TemplateBundle: Codable, Sendable, Equatable {
    /// Reverse-DNS template identifier.
    public var identifier: String

    /// User-visible template name.
    public var name: String

    /// User-visible template description.
    public var description: String

    /// Template author or organization.
    public var author: String

    /// Canvas settings used by projects created from this template.
    public var canvasPreset: CanvasPreset

    /// Tracks and placeholder clips included in the template.
    public var tracks: [TemplateTrack]

    /// Default text styling for generated text placeholders.
    public var textStyleDefaults: TextClipContent

    /// Default export settings for projects created from this template.
    public var exportPreset: ExportSettings

    /// Creates a template bundle.
    public init(
        identifier: String,
        name: String,
        description: String,
        author: String,
        canvasPreset: CanvasPreset,
        tracks: [TemplateTrack],
        textStyleDefaults: TextClipContent,
        exportPreset: ExportSettings
    ) {
        self.identifier = identifier
        self.name = name
        self.description = description
        self.author = author
        self.canvasPreset = canvasPreset
        self.tracks = tracks
        self.textStyleDefaults = textStyleDefaults
        self.exportPreset = exportPreset
    }
}

/// A track included in a template.
public struct TemplateTrack: Codable, Sendable, Equatable {
    /// The generated track kind.
    public var kind: TrackKind

    /// The generated track name.
    public var name: String

    /// Placeholder clips placed on this track.
    public var placeholderClips: [TemplateClip]

    /// Creates a template track.
    public init(kind: TrackKind, name: String, placeholderClips: [TemplateClip]) {
        self.kind = kind
        self.name = name
        self.placeholderClips = placeholderClips
    }
}

/// A placeholder clip included in a template.
public struct TemplateClip: Codable, Sendable, Equatable {
    /// The generated clip kind.
    public var kind: ClipKind

    /// Placeholder duration in seconds.
    public var duration: TimeInterval

    /// Text content for text placeholders.
    public var textContent: TextClipContent?

    /// Effects applied to the generated placeholder clip.
    public var effects: [Effect]

    /// Creates a template clip.
    public init(
        kind: ClipKind,
        duration: TimeInterval,
        textContent: TextClipContent? = nil,
        effects: [Effect] = []
    ) {
        self.kind = kind
        self.duration = duration
        self.textContent = textContent
        self.effects = effects
    }
}
