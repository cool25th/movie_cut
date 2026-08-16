import Foundation

/// Represents the navigation context of the active timeline view (Inc 2).
///
/// - `root`: Viewing and editing the main project timeline.
/// - `compound(id, name)`: Viewing and editing the constituent child clips of a specific compound clip.
public enum TimelineContext: Equatable, Sendable, Hashable {
    case root
    case compound(id: UUID, name: String)

    public var isRoot: Bool {
        if case .root = self { return true }
        return false
    }

    public var compoundId: UUID? {
        if case let .compound(id, _) = self { return id }
        return nil
    }

    public var displayName: String {
        switch self {
        case .root:
            return "Main Timeline"
        case .compound(_, let name):
            return name
        }
    }
}

/// A breadcrumb item in the timeline navigation trail (Inc 2).
public struct TimelineBreadcrumb: Identifiable, Equatable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let context: TimelineContext

    public var isRoot: Bool { context.isRoot }
    public var compoundId: UUID? { context.compoundId }

    public init(id: UUID = UUID(), title: String, context: TimelineContext) {
        self.id = id
        self.title = title
        self.context = context
    }

    public static func root(projectName: String) -> TimelineBreadcrumb {
        TimelineBreadcrumb(title: projectName.isEmpty ? "Main Timeline" : projectName, context: .root)
    }

    public static func compound(id: UUID, name: String) -> TimelineBreadcrumb {
        TimelineBreadcrumb(title: name, context: .compound(id: id, name: name))
    }
}

/// Pure helper for transforming compound constituent clips to/from a virtual timeline.
public enum CompoundTimelineConverter {
    /// Converts a compound definition's relative child clips into an editable virtual Track/Timeline structure.
    public static func makeVirtualTimeline(from compound: CompoundDefinition, frameRate: Rational = Rational(numerator: 30, denominator: 1)) -> Timeline {
        var videoClips: [Clip] = []
        var audioClips: [Clip] = []

        for clip in compound.childClips {
            switch clip.kind {
            case .video, .text, .image:
                videoClips.append(clip)
            case .audio:
                audioClips.append(clip)
            }
        }

        var tracks: [Track] = []
        if !videoClips.isEmpty || audioClips.isEmpty {
            tracks.append(Track(
                kind: .video,
                name: "\(compound.name) (Video)",
                zIndex: 0,
                clips: videoClips
            ))
        }

        if !audioClips.isEmpty {
            tracks.append(Track(
                kind: .audio,
                name: "\(compound.name) (Audio)",
                zIndex: 1,
                clips: audioClips
            ))
        }

        return Timeline(frameRate: frameRate, tracks: tracks)
    }

    /// Extracts all child clips from the virtual timeline tracks back into the compound definition child list.
    public static func extractChildClips(from virtualTimeline: Timeline) -> [Clip] {
        var result: [Clip] = []
        for track in virtualTimeline.tracks {
            for clip in track.clips {
                result.append(clip)
            }
        }
        return result.sorted { $0.timelineRange.start < $1.timelineRange.start }
    }
}
