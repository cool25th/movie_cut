import Foundation

/// An immutable-by-value clipboard snapshot of clips and their source tracks.
/// The payload owns complete `Clip` values and never reads the source project
/// after it has been created.
public struct ClipboardPayload: Sendable, Equatable {
    /// A copied group of clips that originally shared one track.
    public struct SourceTrackGroup: Sendable, Equatable {
        /// The source track identifier, used as the preferred paste target.
        public let sourceTrackId: UUID

        /// The source track kind.
        public let trackKind: TrackKind

        /// The source track's order in the timeline at copy time.
        public let trackOrder: Int

        /// Complete clip value snapshots from this source track.
        public let clips: [Clip]

        public init(
            sourceTrackId: UUID,
            trackKind: TrackKind,
            trackOrder: Int,
            clips: [Clip]
        ) {
            self.sourceTrackId = sourceTrackId
            self.trackKind = trackKind
            self.trackOrder = trackOrder
            self.clips = clips
        }
    }

    /// Source-track groups ordered as captured by the caller.
    public let sourceTrackGroups: [SourceTrackGroup]

    public init(sourceTrackGroups: [SourceTrackGroup]) {
        self.sourceTrackGroups = sourceTrackGroups
    }

    /// Captures complete values for selected clips from a project.
    public init(project: Project, clipIds: Set<UUID>) throws {
        var foundIds = Set<UUID>()
        var groups: [SourceTrackGroup] = []

        for (trackOrder, track) in project.timeline.tracks.enumerated() {
            let clips = track.clips.filter { clipIds.contains($0.id) }
            guard !clips.isEmpty else { continue }
            foundIds.formUnion(clips.map(\.id))
            groups.append(SourceTrackGroup(
                sourceTrackId: track.id,
                trackKind: track.kind,
                trackOrder: trackOrder,
                clips: clips
            ))
        }

        if let missingId = clipIds.subtracting(foundIds).sorted(by: { $0.uuidString < $1.uuidString }).first {
            throw EditorCommandError.clipNotFound(missingId)
        }
        self.sourceTrackGroups = groups
    }
}

/// More explicit spelling for callers that keep multiple clipboard formats.
public typealias ClipClipboardPayload = ClipboardPayload
