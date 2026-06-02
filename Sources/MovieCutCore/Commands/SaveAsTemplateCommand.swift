import Foundation

extension TemplateStore {
    /// Shared template store used by commands that operate through `EditorCommand`.
    public static let shared = TemplateStore(bundles: TemplateStore.builtInTemplates())
}

/// Saves the current project structure as a reusable template.
public struct SaveAsTemplateCommand: EditorCommand, Codable {
    /// The command identifier.
    public let id: UUID

    /// User-visible template name.
    public var name: String

    /// User-visible template description.
    public var description: String

    /// Creates a save-as-template command.
    public init(id: UUID = UUID(), name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let bundle = TemplateBundle(
            identifier: templateIdentifier,
            name: name,
            description: description,
            author: "MovieCut",
            canvasPreset: project.canvas,
            tracks: templateTracks(from: project),
            textStyleDefaults: textStyleDefaults(from: project),
            exportPreset: project.exportSettings
        )

        TemplateStore.shared.add(bundle)

        return CommandResult(description: "Saved template \(name)")
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RemoveTemplateCommand(identifier: templateIdentifier, name: name)
    }

    private var templateIdentifier: String {
        let slug = name
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "-")

        return "com.moviecut.template.user.\(slug.isEmpty ? id.uuidString.lowercased() : slug)"
    }

    private func templateTracks(from project: Project) -> [TemplateTrack] {
        project.timeline.tracks
            .sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.zIndex < rhs.zIndex
            }
            .map { track in
                TemplateTrack(
                    kind: track.kind,
                    name: track.name,
                    placeholderClips: templateClips(from: track.clips)
                )
            }
    }

    private func templateClips(from clips: [Clip]) -> [TemplateClip] {
        clips
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
            .map { clip in
                TemplateClip(
                    kind: clip.kind,
                    duration: clip.timelineRange.duration,
                    textContent: clip.textContent,
                    effects: clip.effects
                )
            }
    }

    private func textStyleDefaults(from project: Project) -> TextClipContent {
        project.timeline.tracks
            .flatMap(\.clips)
            .compactMap(\.textContent)
            .first ?? TextClipContent(text: "Your text")
    }
}

private struct RemoveTemplateCommand: EditorCommand {
    let id: UUID
    let identifier: String
    let name: String

    init(id: UUID = UUID(), identifier: String, name: String) {
        self.id = id
        self.identifier = identifier
        self.name = name
    }

    func apply(to project: inout Project) throws -> CommandResult {
        TemplateStore.shared.remove(id: identifier)
        return CommandResult(description: "Removed template \(name)")
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        NoOpCommand(description: "Template removal cannot be inverted without a bundle snapshot")
    }
}
