import MovieCutCore
import SwiftUI

/// CA-20 stage 2-B (W4): the timeline index — FCP's Timeline Index. One
/// searchable list over the project's clips AND markers (role names
/// searchable too), each row jumping the playhead to (and, for clips,
/// selecting) its target. The entry build and filter are pure functions of
/// the project snapshot, so search correctness is unit-testable and the
/// reveal path reuses the transport's own seek.
extension EditorViewModel {
    struct TimelineIndexEntry: Identifiable, Equatable {
        enum Kind: Equatable {
            case clip(trackName: String, role: String?)
            case marker
        }

        var id: UUID
        var kind: Kind
        /// The searchable/display title: asset filename for media clips,
        /// text excerpt for text clips, marker name for markers.
        var title: String
        /// Timeline position the row reveals.
        var time: TimeInterval
        /// The clip to select on reveal (markers only move the playhead).
        var clipId: UUID?
    }

    /// All index entries (clips + non-beat markers), timeline order.
    /// Beat markers are analysis artifacts, not index rows — they would
    /// drown the list on any beat-detected project.
    func timelineIndexEntries(filter: String = "") -> [TimelineIndexEntry] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rolesById = Dictionary(uniqueKeysWithValues: currentProject.roles.map { ($0.id, $0.name) })

        var entries: [TimelineIndexEntry] = []
        for track in currentProject.timeline.tracks {
            for clip in track.clips.sorted(by: { $0.timelineRange.start < $1.timelineRange.start }) {
                let roleName = clip.roleId.flatMap { rolesById[$0] }
                let entry = TimelineIndexEntry(
                    id: clip.id,
                    kind: .clip(trackName: track.name, role: roleName),
                    title: Self.indexTitle(for: clip, in: currentProject),
                    time: clip.timelineRange.start,
                    clipId: clip.id
                )
                if query.isEmpty || Self.entry(entry, matches: query) {
                    entries.append(entry)
                }
            }
        }
        for marker in currentProject.markers where marker.kind != .beat {
            let entry = TimelineIndexEntry(
                id: marker.id,
                kind: .marker,
                title: marker.name,
                time: marker.time,
                clipId: nil
            )
            if query.isEmpty || Self.entry(entry, matches: query) {
                entries.append(entry)
            }
        }
        return entries.sorted { lhs, rhs in
            lhs.time != rhs.time ? lhs.time < rhs.time : lhs.title < rhs.title
        }
    }

    /// Reveals an entry: clips select + jump, markers jump via the marker
    /// path (which also reports the quick-tool status line).
    func revealTimelineIndexEntry(_ entry: TimelineIndexEntry) {
        if let clipId = entry.clipId {
            selectedClipIds = [clipId]
            scrubPlayhead(to: entry.time)
        } else if let marker = currentProject.markers.first(where: { $0.id == entry.id }) {
            goToMarker(marker)
        }
    }

    /// Case-insensitive match over title, track name, and role name — the
    /// three things a W4 editor remembers about a clip.
    private static func entry(_ entry: TimelineIndexEntry, matches query: String) -> Bool {
        if entry.title.lowercased().contains(query) { return true }
        if case let .clip(trackName, role) = entry.kind {
            if trackName.lowercased().contains(query) { return true }
            if let role, role.lowercased().contains(query) { return true }
        }
        return false
    }

    private static func indexTitle(for clip: Clip, in project: Project) -> String {
        if let textContent = clip.textContent {
            let flat = textContent.text.replacingOccurrences(of: "\n", with: " ")
            return flat.isEmpty ? NSLocalizedString("Text Clip", comment: "") : flat
        }
        if let assetId = clip.assetId,
           let asset = project.mediaLibrary.assets[assetId] {
            let name = (asset.originalURL.lastPathComponent as NSString).deletingPathExtension
            return name.isEmpty ? asset.originalURL.lastPathComponent : name
        }
        return NSLocalizedString("Clip", comment: "")
    }
}
