import Foundation

/// Pastes a value-snapshotted multi-clip payload in one atomic edit.
public struct PasteClipsCommand: EditorCommand {
    public let id: UUID
    public let payload: ClipboardPayload
    public let anchorTime: TimeInterval

    public init(
        id: UUID = UUID(),
        payload: ClipboardPayload,
        anchorTime: TimeInterval
    ) {
        self.id = id
        self.payload = payload
        self.anchorTime = anchorTime
    }

    public func apply(to project: inout Project) throws {
        guard anchorTime.isFinite else {
            throw EditorCommandError.invalidCommand("Paste anchor time must be finite.")
        }

        let orderedGroups = payload.sourceTrackGroups.sorted {
            if $0.trackOrder != $1.trackOrder { return $0.trackOrder < $1.trackOrder }
            return $0.sourceTrackId.uuidString < $1.sourceTrackId.uuidString
        }
        let sourceClips = orderedGroups.flatMap(\.clips)
        guard !sourceClips.isEmpty else {
            throw EditorCommandError.invalidCommand("Clipboard payload cannot be empty.")
        }
        guard sourceClips.allSatisfy({
            $0.timelineRange.start.isFinite &&
                $0.timelineRange.duration.isFinite &&
                $0.timelineRange.duration >= 0
        }) else {
            throw EditorCommandError.invalidCommand("Clipboard clips must have finite, nonnegative timeline ranges.")
        }

        let earliestStart = sourceClips.map(\.timelineRange.start).min()!
        let shift = max(0, anchorTime) - earliestStart
        let previousTracks = project.timeline.tracks
        var tracks = previousTracks
        var pastedIds = Set<UUID>()
        var pastedGroupIds: [UUID: UUID] = [:]

        for sourceClip in sourceClips {
            if let sourceGroupId = sourceClip.groupId,
               pastedGroupIds[sourceGroupId] == nil {
                pastedGroupIds[sourceGroupId] = UUID()
            }
        }

        for group in orderedGroups where !group.clips.isEmpty {
            guard group.clips.allSatisfy({ Self.isCompatible($0.kind, with: group.trackKind) }) else {
                throw EditorCommandError.invalidCommand("Clipboard source-track group contains incompatible clip kinds.")
            }

            let pastedGroup = group.clips.map { sourceClip -> Clip in
                var clip = sourceClip
                clip.id = UUID()
                clip.groupId = sourceClip.groupId.flatMap { pastedGroupIds[$0] }
                clip.timelineRange = TimeRange(
                    start: sourceClip.timelineRange.start + shift,
                    duration: sourceClip.timelineRange.duration
                )
                return clip
            }

            let originalIndex = tracks.firstIndex(where: { $0.id == group.sourceTrackId })
            let targetIndex: Int
            if let originalIndex, Self.canPlace(pastedGroup, on: tracks[originalIndex]) {
                targetIndex = originalIndex
            } else if let compatibleIndex = tracks.indices.first(where: {
                Self.canPlace(pastedGroup, on: tracks[$0])
            }) {
                targetIndex = compatibleIndex
            } else {
                let ordinal = tracks.lazy.filter { $0.kind == group.trackKind }.count + 1
                tracks.append(Track(
                    kind: group.trackKind,
                    name: "\(Self.displayName(for: group.trackKind)) \(ordinal)",
                    zIndex: tracks.count
                ))
                targetIndex = tracks.index(before: tracks.endIndex)
            }

            tracks[targetIndex].clips.append(contentsOf: pastedGroup)
            tracks[targetIndex].normalizeClipZIndexes()
            pastedIds.formUnion(pastedGroup.map(\.id))
        }

        for index in tracks.indices {
            tracks[index].zIndex = index
        }
        project.timeline.tracks = tracks
    }

        private static func canPlace(_ clips: [Clip], on track: Track) -> Bool {
        guard !track.isLocked,
              clips.allSatisfy({ isCompatible($0.kind, with: track.kind) }) else {
            return false
        }
        return !clips.contains { candidate in
            track.clips.contains { candidate.timelineRange.overlaps($0.timelineRange) }
        }
    }

    private static func isCompatible(_ clipKind: ClipKind, with trackKind: TrackKind) -> Bool {
        switch clipKind {
        case .video, .image: trackKind == .video
        case .audio: trackKind == .audio
        case .text: trackKind == .text
        }
    }

    private static func displayName(for kind: TrackKind) -> String {
        switch kind {
        case .video: "Video"
        case .audio: "Audio"
        case .text: "Text"
        }
    }
}
