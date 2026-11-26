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

    /// Deterministic content digest over the flattened clip layout, so two
    /// snapshots can be compared for render-identity cheaply. Encodes every
    /// track (id, kind, mute/lock/hidden, z-order) and every clip's render
    /// attributes — identity, asset/compound references, both ranges, speed
    /// (rate, ramp, reverse), audio level, opacity/blend, transition to the
    /// next clip, effects, color correction/grade, transform, crop, mask,
    /// keyframes, and stabilization — through the fixed-seed FNV-1a hasher
    /// below, so the digest is stable across processes and launches.
    static func digest(of tracks: [Track]) -> String {
        var hasher = DeterministicDigestHasher()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        // Codable sub-values (effects, color, transform, masks, keyframes,
        // ramps, stabilization) are folded in as their canonical sorted-key
        // JSON bytes: every stored field participates without enumerating
        // each one here, and the encoding itself is deterministic.
        func combineJSON<T: Encodable>(_ value: T) {
            if let data = try? encoder.encode(value) {
                hasher.combine(UInt64(data.count))
                hasher.combine(data)
            } else {
                hasher.combine(UInt64(0))
            }
        }

        for track in tracks {
            hasher.combine(track.id)
            hasher.combine(String(describing: track.kind))
            hasher.combine(track.isMuted)
            hasher.combine(track.isLocked)
            hasher.combine(track.isHidden)
            hasher.combine(track.zIndex)
            hasher.combine(UInt64(track.clips.count))
            for clip in track.clips {
                hasher.combine(clip.id)
                // Presence-tagged optionals keep `nil` distinct from any value.
                if let assetId = clip.assetId {
                    hasher.combine(true)
                    hasher.combine(assetId)
                } else {
                    hasher.combine(false)
                }
                if let compoundId = clip.compoundId {
                    hasher.combine(true)
                    hasher.combine(compoundId)
                } else {
                    hasher.combine(false)
                }
                hasher.combine(clip.timelineRange.start)
                hasher.combine(clip.timelineRange.duration)
                hasher.combine(clip.sourceRange.start)
                hasher.combine(clip.sourceRange.duration)
                hasher.combine(clip.playbackRate)
                hasher.combine(clip.isReversed)
                hasher.combine(clip.volume)
                hasher.combine(clip.opacity)
                hasher.combine(String(describing: clip.blendMode))
                if let transition = clip.transition {
                    hasher.combine(true)
                    hasher.combine(transition.duration)
                    hasher.combine(String(describing: transition.type))
                } else {
                    hasher.combine(false)
                }
                hasher.combine(UInt64(clip.effects.count))
                for effect in clip.effects {
                    combineJSON(effect)
                }
                if let colorCorrection = clip.colorCorrection {
                    hasher.combine(true)
                    combineJSON(colorCorrection)
                } else {
                    hasher.combine(false)
                }
                if let colorGrade = clip.colorGrade {
                    hasher.combine(true)
                    combineJSON(colorGrade)
                } else {
                    hasher.combine(false)
                }
                combineJSON(clip.transform)
                if let cropRect = clip.cropRect {
                    hasher.combine(true)
                    combineJSON(cropRect)
                } else {
                    hasher.combine(false)
                }
                if let mask = clip.mask {
                    hasher.combine(true)
                    combineJSON(mask)
                } else {
                    hasher.combine(false)
                }
                hasher.combine(UInt64(clip.keyframes.count))
                for keyframe in clip.keyframes {
                    combineJSON(keyframe)
                }
                hasher.combine(UInt64(clip.speedRampPoints.count))
                for point in clip.speedRampPoints {
                    combineJSON(point)
                }
                if let stabilization = clip.stabilization {
                    hasher.combine(true)
                    combineJSON(stabilization)
                } else {
                    hasher.combine(false)
                }
            }
        }
        return hasher.hexDigest
    }
}

/// FNV-1a 64-bit digest hasher with a fixed seed. `Swift.Hasher` is randomly
/// seeded per process, so a digest built on it changes every launch and
/// cannot back a cross-launch identity such as
/// `FlattenedTimeline.contentDigest`. The encoding below (fixed-width
/// little-endian integers, length-prefixed UTF-8, raw UUID bytes) is stable
/// across processes and launches on the same platform.
struct DeterministicDigestHasher {
    private var value: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let fnvPrime: UInt64 = 0x0000_0100_0000_01b3

    private mutating func absorb(_ byte: UInt8) {
        value = (value ^ UInt64(byte)) &* Self.fnvPrime
    }

    mutating func combine(_ raw: UInt64) {
        absorb(UInt8(truncatingIfNeeded: raw))
        absorb(UInt8(truncatingIfNeeded: raw >> 8))
        absorb(UInt8(truncatingIfNeeded: raw >> 16))
        absorb(UInt8(truncatingIfNeeded: raw >> 24))
        absorb(UInt8(truncatingIfNeeded: raw >> 32))
        absorb(UInt8(truncatingIfNeeded: raw >> 40))
        absorb(UInt8(truncatingIfNeeded: raw >> 48))
        absorb(UInt8(truncatingIfNeeded: raw >> 56))
    }

    mutating func combine(_ raw: Int) {
        combine(UInt64(bitPattern: Int64(raw)))
    }

    mutating func combine(_ flag: Bool) {
        absorb(flag ? 1 : 0)
    }

    mutating func combine(_ scalar: Double) {
        combine(scalar.bitPattern)
    }

    mutating func combine(_ bytes: some Sequence<UInt8>) {
        for byte in bytes {
            absorb(byte)
        }
    }

    mutating func combine(_ text: String) {
        combine(UInt64(text.utf8.count))
        combine(text.utf8)
    }

    mutating func combine(_ id: UUID) {
        withUnsafeBytes(of: id.uuid) { bytes in
            for byte in bytes {
                absorb(byte)
            }
        }
    }

    var hexDigest: String {
        String(value, radix: 16)
    }
}
