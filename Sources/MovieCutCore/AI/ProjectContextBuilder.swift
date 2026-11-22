import Foundation

/// Privacy-safe, deterministic summary of the current `Project` state for AI editing
/// planners (`AI-05`). Contains structural timeline metadata, clip IDs, 1-based clip
/// indices, roles, and selection state without exposing user filesystem paths.
public struct ProjectContextSnapshot: Codable, Sendable, Equatable {
    public struct ClipContextSummary: Codable, Sendable, Equatable {
        public let oneBasedIndex: Int
        public let id: UUID
        public let kind: ClipKind
        public let startSeconds: TimeInterval
        public let durationSeconds: TimeInterval
        public let roleName: String?
        public let hasColorCorrection: Bool
        public let effectCount: Int

        public init(
            oneBasedIndex: Int,
            id: UUID,
            kind: ClipKind,
            startSeconds: TimeInterval,
            durationSeconds: TimeInterval,
            roleName: String?,
            hasColorCorrection: Bool,
            effectCount: Int
        ) {
            self.oneBasedIndex = oneBasedIndex
            self.id = id
            self.kind = kind
            self.startSeconds = startSeconds
            self.durationSeconds = durationSeconds
            self.roleName = roleName
            self.hasColorCorrection = hasColorCorrection
            self.effectCount = effectCount
        }
    }

    public struct TrackContextSummary: Codable, Sendable, Equatable {
        public let id: UUID
        public let name: String
        public let kind: TrackKind
        public let isLocked: Bool
        public let isMuted: Bool
        public let clips: [ClipContextSummary]

        public init(
            id: UUID,
            name: String,
            kind: TrackKind,
            isLocked: Bool,
            isMuted: Bool,
            clips: [ClipContextSummary]
        ) {
            self.id = id
            self.name = name
            self.kind = kind
            self.isLocked = isLocked
            self.isMuted = isMuted
            self.clips = clips
        }
    }

    public let baseRevision: SessionRevision
    public let canvas: CanvasPreset
    public let totalDurationSeconds: TimeInterval
    public let playheadSeconds: TimeInterval
    public let selectedClipIds: [UUID]
    public let tracks: [TrackContextSummary]
    public let markerTimestamps: [TimeInterval]

    public init(
        baseRevision: SessionRevision,
        canvas: CanvasPreset,
        totalDurationSeconds: TimeInterval,
        playheadSeconds: TimeInterval,
        selectedClipIds: [UUID],
        tracks: [TrackContextSummary],
        markerTimestamps: [TimeInterval]
    ) {
        self.baseRevision = baseRevision
        self.canvas = canvas
        self.totalDurationSeconds = totalDurationSeconds
        self.playheadSeconds = playheadSeconds
        self.selectedClipIds = selectedClipIds
        self.tracks = tracks
        self.markerTimestamps = markerTimestamps
    }

    /// Converts this snapshot into the lightweight `AIEditContext` used by `AIEditingProvider`.
    public var aiEditContext: AIEditContext {
        let allClips = tracks.flatMap(\.clips)
        let videoCount = allClips.filter { $0.kind == .video || $0.kind == .image }.count
        let audioCount = allClips.filter { $0.kind == .audio }.count
        let textCount = allClips.filter { $0.kind == .text }.count
        return AIEditContext(
            videoClipCount: videoCount,
            audioClipCount: audioCount,
            textClipCount: textCount,
            hasSelection: !selectedClipIds.isEmpty
        )
    }

    /// Encodes the snapshot as deterministic JSON for structured LLM planner prompts.
    public func toJSONString(prettyPrinted: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        if prettyPrinted {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    /// Produces a compact human-readable summary for model system prompts.
    public func toPromptSummary() -> String {
        var lines: [String] = [
            "Revision: \(baseRevision.value)",
            String(format: "Duration: %.2fs (Playhead: %.2fs)", totalDurationSeconds, playheadSeconds),
            "Selected Clips: \(selectedClipIds.count)",
        ]
        for track in tracks {
            lines.append("Track '\(track.name)' (\(track.kind.rawValue), clips: \(track.clips.count)):")
            for clip in track.clips {
                let roleSuffix = clip.roleName.map { " [role: \($0)]" } ?? ""
                lines.append(
                    String(
                        format: "  #%d id=%@ kind=%@ range=%.2f..%.2fs%@",
                        clip.oneBasedIndex,
                        clip.id.uuidString,
                        clip.kind.rawValue,
                        clip.startSeconds,
                        clip.startSeconds + clip.durationSeconds,
                        roleSuffix
                    )
                )
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Builds privacy-safe `ProjectContextSnapshot` instances and decodes structured JSON
/// editing plans returned by local or remote LLM planners (`AI-05`).
public enum ProjectContextBuilder {

    public static func build(
        from project: Project,
        baseRevision: SessionRevision,
        selectedClipIds: Set<UUID> = [],
        playheadSeconds: TimeInterval = 0
    ) -> ProjectContextSnapshot {
        let roleNamesById = Dictionary(uniqueKeysWithValues: project.roles.map { ($0.id, $0.name) })

        let trackSummaries: [ProjectContextSnapshot.TrackContextSummary] = project.timeline.tracks.map { track in
            let sortedClips = track.clips.sorted { $0.timelineRange.start < $1.timelineRange.start }
            let clipSummaries = sortedClips.enumerated().map { index, clip in
                ProjectContextSnapshot.ClipContextSummary(
                    oneBasedIndex: index + 1,
                    id: clip.id,
                    kind: clip.kind,
                    startSeconds: clip.timelineRange.start,
                    durationSeconds: clip.timelineRange.duration,
                    roleName: clip.roleId.flatMap { roleNamesById[$0] },
                    hasColorCorrection: clip.colorCorrection != nil,
                    effectCount: clip.effects.count
                )
            }
            return ProjectContextSnapshot.TrackContextSummary(
                id: track.id,
                name: track.name,
                kind: track.kind,
                isLocked: track.isLocked,
                isMuted: track.isMuted,
                clips: clipSummaries
            )
        }

        let totalDuration = trackSummaries
            .flatMap(\.clips)
            .map { $0.startSeconds + $0.durationSeconds }
            .max() ?? 0

        let orderedSelected = project.timeline.tracks
            .flatMap(\.clips)
            .map(\.id)
            .filter { selectedClipIds.contains($0) }

        let markerTimes = project.markers.map(\.time).sorted()

        return ProjectContextSnapshot(
            baseRevision: baseRevision,
            canvas: project.canvas,
            totalDurationSeconds: totalDuration,
            playheadSeconds: playheadSeconds,
            selectedClipIds: orderedSelected,
            tracks: trackSummaries,
            markerTimestamps: markerTimes
        )
    }

    /// Decodes and validates a JSON-encoded `ProductionPlan` against the expected `baseRevision`.
    public static func decodeProductionPlan(
        from jsonData: Data,
        expectedRevision: SessionRevision
    ) throws -> ProductionPlan {
        let plan = try JSONDecoder().decode(ProductionPlan.self, from: jsonData)
        guard plan.baseRevision == expectedRevision else {
            throw EditorCommandError.staleRevision(
                expected: plan.baseRevision,
                current: expectedRevision
            )
        }
        guard !plan.actions.isEmpty else {
            throw EditingActionDSL.PlanningError.emptyRange
        }
        return plan
    }
}
