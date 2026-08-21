import Foundation

public enum TrackProperty: Sendable, Codable, Equatable {
    case isLocked(Bool)
    case isMuted(Bool)
    case isSolo(Bool)
    case isHidden(Bool)
    case zIndex(Int)
}

public struct SetTrackPropertyCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var trackId: UUID
    public var property: TrackProperty
    private var oldValue: TrackProperty?

    public init(
        id: UUID = UUID(),
        trackId: UUID,
        property: TrackProperty,
        oldValue: TrackProperty? = nil
    ) {
        self.id = id
        self.trackId = trackId
        self.property = property
        self.oldValue = oldValue
    }

    public func apply(to project: inout Project) throws {
        let index = try project.trackIndex(for: trackId)
        let previous: TrackProperty

        switch property {
        case .isLocked(let isLocked):
            previous = .isLocked(project.timeline.tracks[index].isLocked)
            project.timeline.tracks[index].isLocked = isLocked
        case .isMuted(let isMuted):
            previous = .isMuted(project.timeline.tracks[index].isMuted)
            project.timeline.tracks[index].isMuted = isMuted
        case .isSolo(let isSolo):
            previous = .isSolo(project.timeline.tracks[index].isSolo)
            project.timeline.tracks[index].isSolo = isSolo
        case .isHidden(let isHidden):
            previous = .isHidden(project.timeline.tracks[index].isHidden)
            project.timeline.tracks[index].isHidden = isHidden
        case .zIndex(let zIndex):
            previous = .zIndex(project.timeline.tracks[index].zIndex)
            project.timeline.tracks[index].zIndex = zIndex
        }
    }
}

private extension TrackProperty {
    func replacingValue(with value: Bool) -> TrackProperty {
        switch self {
        case .isLocked:
            return .isLocked(value)
        case .isMuted:
            return .isMuted(value)
        case .isSolo:
            return .isSolo(value)
        case .isHidden:
            return .isHidden(value)
        case .zIndex:
            return self
        }
    }
}
