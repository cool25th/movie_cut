import Foundation
import CoreGraphics

/// A single-source, fully-expanded view of a project timeline used for both
/// playback and export rendering (Task 5.8, Requirement 7.5).
///
/// Inc 1 compound clips are a **single-level** nesting unit: a container clip
/// (one carrying `compoundId`) stands in for several child clips whose
/// `timelineRange` is stored **relative to the container's start**. Before any
/// frame is rendered, the project's tracks are flattened once: each container
/// is replaced by its definition's children, shifted by the container's
/// timeline start, and every non-container clip passes through untouched.
///
/// **Cache discipline (the parity claim).** The flatten happens in exactly one
/// place — `CompoundFlattener.flatten(_:)` — and the result is a value
/// snapshot. `PlaybackEngine` and `ExportEngine` take that snapshot as an
/// argument; neither one calls flatten itself, neither keeps its own cache, and
/// the frame loop never calls flatten. Because both engines read the identical
/// snapshot, the preview and export compositions are equal by construction.
///
/// The snapshot is recomputed on project change (by the orchestrator) and is a
/// `Sendable` value, so it can be handed to both engines without races.
public struct FlattenedTimeline: Sendable, Equatable {
    /// The source project's identity and schema, carried for diagnostics. This
    /// snapshot is derived from that project; it is not the project itself.
    public let projectId: UUID
    public let schemaVersion: Int

    /// The render-time frame rate, copied from the source timeline.
    public let frameRate: Rational

    /// The render canvas size, copied from the source timeline.
    public let canvasSize: CGSize

    /// The fully-expanded tracks: no clip here carries a `compoundId`, and the
    /// relative child composition of every compound has been laid onto the
    /// parent timeline. Tracks retain their original kind/ordering/visibility;
    /// only clips have been expanded in place.
    public let tracks: [Track]

    /// A content hash over the flattened tracks, used to detect that two
    /// snapshots are byte-identical without a full structural compare. Two
    /// snapshots with the same `contentDigest` render identically.
    public let contentDigest: String

    /// Creates a flattened timeline snapshot. Construction is normally done by
    /// `CompoundFlattener.flatten`; the initializer is public so tests can
    /// synthesize known snapshots.
    public init(
        projectId: UUID,
        schemaVersion: Int,
        frameRate: Rational,
        canvasSize: CGSize,
        tracks: [Track],
        contentDigest: String
    ) {
        self.projectId = projectId
        self.schemaVersion = schemaVersion
        self.frameRate = frameRate
        self.canvasSize = canvasSize
        self.tracks = tracks
        self.contentDigest = contentDigest
    }
}

/// Pure, single-level compound-clip flattening (Task 5.8).
///
/// The flattener is **non-recursive**: Inc 1 forbids nesting (validated by
/// `Project.validateCompounds` at load), so a single pass over each track is
/// sufficient. A container clip (one with a `compoundId`) is replaced by its
/// definition's `childClips`, each repositioned by the container's timeline
/// start. A container with no resolvable definition is a structural error that
/// load-time validation already rejects; here it is dropped defensively and
/// the snapshot is still well-formed, but this branch is unreachable for a
/// project that passed `validateCompounds`.
public enum CompoundFlattener {
    /// Produces a `FlattenedTimeline` snapshot for `project`, expanding every
    /// compound container exactly one level. Pure: no mutation of `project`,
    /// no I/O, no shared mutable state.
    ///
    /// Call this **once per project change** (outside the frame loop) and hand
    /// the resulting snapshot to both `PlaybackEngine` and `ExportEngine` as an
    /// argument. Do not call it inside either engine.
    public static func flatten(_ project: Project) -> FlattenedTimeline {
        let compoundsById = Dictionary(uniqueKeysWithValues: project.compounds.map { ($0.id, $0) })

        var flattenedTracks: [Track] = []
        flattenedTracks.reserveCapacity(project.timeline.tracks.count)

        for track in project.timeline.tracks {
            var expanded = track
            var newClips: [Clip] = []
            newClips.reserveCapacity(track.clips.count)

            for clip in track.clips {
                guard let compoundId = clip.compoundId else {
                    // Plain clip: pass through untouched.
                    newClips.append(clip)
                    continue
                }

                // Container clip: expand its definition's children by the
                // container's timeline start. Single level only — children
                // never themselves carry a compoundId (load validates this).
                if let compound = compoundsById[compoundId] {
                    newClips.append(contentsOf: visibleChildren(
                        of: compound,
                        in: clip
                    ))
                }
                // An unresolved compoundId is unreachable for a validated
                // project; if it occurs we drop the container rather than emit
                // a half-rendered reference.
            }

            expanded.clips = newClips
            flattenedTracks.append(expanded)
        }

        return FlattenedTimeline(
            projectId: project.id,
            schemaVersion: project.schemaVersion,
            frameRate: project.timeline.frameRate,
            canvasSize: project.timeline.canvasSize,
            tracks: flattenedTracks,
            contentDigest: digest(of: flattenedTracks)
        )
    }

    /// Returns the definition children visible through a container's current
    /// source window, shifted onto the parent timeline. Moving a container only
    /// changes the final shift; trimming it changes `sourceRange`, which clips
    /// child timeline/source ranges through the shared ClipTrimMath mapping.
    /// Release uses this same function so rendered and released results agree.
    public static func visibleChildren(
        of definition: CompoundDefinition,
        in container: Clip
    ) -> [Clip] {
        let windowStart = max(0, container.sourceRange.start)
        let windowEnd = max(windowStart, container.sourceRange.end)
        let minimumDuration = 1.0 / 600.0

        return definition.childClips.compactMap { child in
            let visibleStart = max(child.timelineRange.start, windowStart)
            let visibleEnd = min(child.timelineRange.end, windowEnd)
            guard visibleEnd - visibleStart >= minimumDuration else { return nil }

            var visible = child
            if visibleStart > visible.timelineRange.start,
               let startTrim = ClipTrimMath.compute(
                   clip: visible,
                   edge: .start,
                   targetTimelineTime: visibleStart,
                   assetDuration: visible.kind == .image ? nil : visible.sourceRange.end,
                   minimumDuration: minimumDuration
               ) {
                visible.sourceRange = startTrim.source
                visible.timelineRange = startTrim.timeline
            }

            if visibleEnd < visible.timelineRange.end,
               let endTrim = ClipTrimMath.compute(
                   clip: visible,
                   edge: .end,
                   targetTimelineTime: visibleEnd,
                   assetDuration: visible.kind == .image ? nil : visible.sourceRange.end,
                   minimumDuration: minimumDuration
               ) {
                visible.sourceRange = endTrim.source
                visible.timelineRange = endTrim.timeline
            }

            visible.timelineRange = TimeRange(
                start: container.timelineRange.start + (visible.timelineRange.start - windowStart),
                duration: visible.timelineRange.duration
            )
            visible.compoundId = nil
            return visible
        }
    }

    /// Stable content digest over the flattened clip layout, so two snapshots
    /// can be compared for render-identity cheaply. Encodes track id/kind and
    /// each clip's id, compoundId-absence, and timeline/source ranges.
    static func digest(of tracks: [Track]) -> String {
        var hasher = Hasher()
        for track in tracks {
            hasher.combine(track.id)
            hasher.combine(track.kind)
            for clip in track.clips {
                hasher.combine(clip.id)
                // A correctly flattened timeline has no containers; record this
                // so any leak surfaces as a digest difference.
                hasher.combine(clip.compoundId == nil)
                hasher.combine(clip.timelineRange.start)
                hasher.combine(clip.timelineRange.duration)
                hasher.combine(clip.sourceRange.start)
                hasher.combine(clip.sourceRange.duration)
            }
        }
        return String(hasher.finalize(), radix: 16)
    }
}
