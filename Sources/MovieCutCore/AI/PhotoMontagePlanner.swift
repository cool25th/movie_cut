import Foundation

/// Deterministic montage planner that composes a sequence of photos and an optional audio track
/// into a polished video timeline with Ken Burns animations (pan & zoom).
///
/// Placement policy (AI-03a M4): a montage is a NEW-PROJECT creation. Planning
/// against a timeline that already carries clips is rejected with
/// `PlanningError.timelineNotEmpty` — insert-at-position / replace-selection
/// modes are future explicit placement modes, never an implicit overwrite.
public enum PhotoMontagePlanner {

    /// Input bounds (AI-03a M2). The planner must terminate and produce a
    /// bounded action list for every accepted input, and reject everything
    /// it cannot — unknown music lengths are NOT guessed.
    public enum Limits {
        /// Longest allowed target duration (1 hour).
        public static let maxTargetDuration: TimeInterval = 3600
        /// Most photos in one montage.
        public static let maxPhotoCount = 200
        /// Shortest usable music asset — below this the loop count explodes.
        public static let minMusicDuration: TimeInterval = 0.5
        /// Most sequential loop chunks the music path may emit.
        public static let maxMusicLoops = 64
        /// Anti-click micro-fade at each loop junction (AI-03a M5). Short
        /// enough to be inaudible as a fade, long enough to remove the
        /// discontinuity of a butt-spliced junction.
        public static let junctionFadeDuration: TimeInterval = 0.012
    }

    /// Available motion styles applied to photo clips.
    public enum MotionStyle: Sendable, Equatable {
        case zoomIn
        case zoomOut
        case panLeftToRight
        case panRightToLeft
    }

    /// Generates a production plan for assembling photos and audio into a vertical video.
    public static func plan(
        photos: [MediaAsset],
        music: MediaAsset? = nil,
        targetDuration: TimeInterval = 15.0,
        targetCanvas: CanvasPreset = .portrait9x16,
        existingTracks: [Track] = [],
        baseRevision: SessionRevision,
        planId: UUID = UUID()
    ) throws -> ProductionPlan {
        guard !photos.isEmpty else {
            throw EditingActionDSL.PlanningError.emptyRange
        }
        guard targetDuration.isFinite, targetDuration > 0 else {
            throw EditingActionDSL.PlanningError.invalidTimeValue(
                "targetDuration must be finite and > 0 (got \(targetDuration))"
            )
        }
        guard targetDuration <= Limits.maxTargetDuration else {
            throw EditingActionDSL.PlanningError.invalidTimeValue(
                "targetDuration \(targetDuration)s exceeds the \(Limits.maxTargetDuration)s maximum"
            )
        }
        guard photos.count <= Limits.maxPhotoCount else {
            throw EditingActionDSL.PlanningError.invalidTimeValue(
                "\(photos.count) photos exceeds the \(Limits.maxPhotoCount) maximum"
            )
        }
        guard existingTracks.contains(where: { !$0.clips.isEmpty }) == false else {
            throw EditingActionDSL.PlanningError.timelineNotEmpty
        }

        let photoCount = photos.count
        let baseClipDuration = targetDuration / Double(photoCount)

        var actions: [EditingActionDSL.Action] = []
        var assumptions: [String] = []

        // 0. Set target project canvas — the timeline is verified empty, so
        // no existing content is re-cropped by this change.
        actions.append(.setCanvas(canvas: targetCanvas))

        // 1. Resolve or create main video track (never a locked one)
        let videoTrackId: UUID
        if let existingVideoTrack = existingTracks.first(where: { $0.kind == .video && $0.clips.isEmpty && !$0.isLocked }) {
            videoTrackId = existingVideoTrack.id
        } else {
            videoTrackId = UUID()
            actions.append(.createTrack(trackId: videoTrackId, kind: .video, name: "Main Video"))
        }

        // 2. Register photo assets and place clips with Ken Burns keyframing
        for (index, photo) in photos.enumerated() {
            actions.append(.registerAsset(asset: photo))

            let clipId = UUID()
            let startTime = Double(index) * baseClipDuration
            let duration: TimeInterval = (index == photoCount - 1)
                ? (targetDuration - startTime)
                : baseClipDuration

            let timelineRange = TimeRange(start: startTime, duration: duration)
            let sourceRange = TimeRange(start: 0, duration: duration)

            actions.append(.addClip(
                clipId: clipId,
                trackId: videoTrackId,
                assetId: photo.id,
                timelineRange: timelineRange,
                sourceRange: sourceRange,
                kind: .image
            ))

            // Alternate Ken Burns motion styles across photos
            let style = motionStyle(for: index)
            let keyframes = generateKeyframes(for: style, duration: duration)
            actions.append(.setClipKeyframes(clipId: clipId, keyframes: keyframes))
        }
        assumptions.append("Divided \(targetDuration)s across \(photoCount) photos with alternating Ken Burns effects.")

        // 3. Audio track (if provided)
        if let musicAsset = music {
            let audioTrackId: UUID
            if let existingAudioTrack = existingTracks.first(where: { $0.kind == .audio && $0.clips.isEmpty && !$0.isLocked }) {
                audioTrackId = existingAudioTrack.id
            } else {
                audioTrackId = UUID()
                actions.append(.createTrack(trackId: audioTrackId, kind: .audio, name: "Music"))
            }
            actions.append(.registerAsset(asset: musicAsset))

            // AI-03a M2: unknown or non-finite music lengths are rejected —
            // never guessed. The app path always probes
            // (PreparedAssetStore.prepareMusicAsset), so a nil here means an
            // unprobed caller.
            guard let probedDuration = musicAsset.duration,
                  probedDuration.isFinite, probedDuration > 0 else {
                throw EditingActionDSL.PlanningError.invalidTimeValue(
                    "music asset duration is unknown or invalid — probe it before planning"
                )
            }
            guard probedDuration >= Limits.minMusicDuration else {
                throw EditingActionDSL.PlanningError.invalidTimeValue(
                    "music asset \(probedDuration)s is shorter than the \(Limits.minMusicDuration)s minimum"
                )
            }
            let assetDuration = probedDuration

            if assetDuration >= targetDuration {
                let musicClipId = UUID()
                let audioDuration = targetDuration
                actions.append(.addClip(
                    clipId: musicClipId,
                    trackId: audioTrackId,
                    assetId: musicAsset.id,
                    timelineRange: TimeRange(start: 0, duration: audioDuration),
                    sourceRange: TimeRange(start: 0, duration: audioDuration),
                    kind: .audio
                ))

                let fadeOutDuration = min(1.5, audioDuration / 2)
                actions.append(.setClipFade(clipId: musicClipId, fadeIn: 0.5, fadeOut: fadeOutDuration))
                assumptions.append("Added background music with 0.5s fade-in and \(fadeOutDuration)s fade-out.")
            } else {
                // Short audio asset: loop sequentially across targetDuration.
                // The loop count is bounded UP FRONT (AI-03a M2) so planning
                // terminates for every accepted input.
                let requiredLoops = Int(ceil((targetDuration - 0.001) / assetDuration))
                guard requiredLoops <= Limits.maxMusicLoops else {
                    throw EditingActionDSL.PlanningError.invalidTimeValue(
                        "music \(assetDuration)s would need \(requiredLoops) loops for \(targetDuration)s (max \(Limits.maxMusicLoops)) — use a longer track"
                    )
                }

                var currentTimelineTime: TimeInterval = 0
                var chunkIndex = 0
                var lastFadeOut: TimeInterval = 0

                while currentTimelineTime < targetDuration - 0.001 {
                    let remaining = targetDuration - currentTimelineTime
                    let chunkDuration = min(remaining, assetDuration)
                    let clipId = UUID()

                    actions.append(.addClip(
                        clipId: clipId,
                        trackId: audioTrackId,
                        assetId: musicAsset.id,
                        timelineRange: TimeRange(start: currentTimelineTime, duration: chunkDuration),
                        sourceRange: TimeRange(start: 0, duration: chunkDuration),
                        kind: .audio
                    ))

                    let isFirst = (chunkIndex == 0)
                    let isLast = (currentTimelineTime + chunkDuration >= targetDuration - 0.001)
                    // Loop junctions carry an anti-click micro-fade (AI-03a
                    // M5); the montage's own edges keep their musical fades.
                    let junctionFade = min(Limits.junctionFadeDuration, chunkDuration / 2)
                    let fadeIn: TimeInterval = isFirst
                        ? min(0.5, chunkDuration / 2)
                        : junctionFade
                    let fadeOut: TimeInterval = isLast
                        ? min(1.5, chunkDuration / 2)
                        : junctionFade

                    if fadeIn > 0 || fadeOut > 0 {
                        actions.append(.setClipFade(clipId: clipId, fadeIn: fadeIn, fadeOut: fadeOut))
                    }
                    if isLast {
                        lastFadeOut = fadeOut
                    }

                    currentTimelineTime += chunkDuration
                    chunkIndex += 1
                }

                assumptions.append("Looped background music (\(assetDuration)s) across \(targetDuration)s with 0.5s fade-in, \(lastFadeOut)s fade-out, and \(Limits.junctionFadeDuration)s anti-click junction fades.")
            }
        }

        return ProductionPlan(
            planId: planId,
            baseRevision: baseRevision,
            userIntent: "Photo montage (\(photoCount) photos, \(targetDuration)s)",
            targetDuration: targetDuration,
            targetCanvas: targetCanvas,
            actions: actions,
            assumptions: assumptions
        )
    }

    private static func motionStyle(for index: Int) -> MotionStyle {
        switch index % 4 {
        case 0: return .zoomIn
        case 1: return .zoomOut
        case 2: return .panLeftToRight
        default: return .panRightToLeft
        }
    }

    private static func generateKeyframes(for style: MotionStyle, duration: TimeInterval) -> [Keyframe] {
        switch style {
        case .zoomIn:
            return [
                Keyframe(property: .scaleX, time: 0, value: 1.0),
                Keyframe(property: .scaleY, time: 0, value: 1.0),
                Keyframe(property: .scaleX, time: duration, value: 1.15),
                Keyframe(property: .scaleY, time: duration, value: 1.15),
            ]
        case .zoomOut:
            return [
                Keyframe(property: .scaleX, time: 0, value: 1.15),
                Keyframe(property: .scaleY, time: 0, value: 1.15),
                Keyframe(property: .scaleX, time: duration, value: 1.0),
                Keyframe(property: .scaleY, time: duration, value: 1.0),
            ]
        case .panLeftToRight:
            return [
                Keyframe(property: .scaleX, time: 0, value: 1.1),
                Keyframe(property: .scaleY, time: 0, value: 1.1),
                Keyframe(property: .positionX, time: 0, value: -15.0),
                Keyframe(property: .positionX, time: duration, value: 15.0),
            ]
        case .panRightToLeft:
            return [
                Keyframe(property: .scaleX, time: 0, value: 1.1),
                Keyframe(property: .scaleY, time: 0, value: 1.1),
                Keyframe(property: .positionX, time: 0, value: 15.0),
                Keyframe(property: .positionX, time: duration, value: -15.0),
            ]
        }
    }
}
