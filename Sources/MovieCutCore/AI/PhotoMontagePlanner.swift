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
        planId: UUID = UUID(),
        beatTimestamps: [TimeInterval] = [],
        addBeatMarkers: Bool = false
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
        let segmentRanges = computeBeatAlignedSegments(
            photoCount: photoCount,
            targetDuration: targetDuration,
            beatTimestamps: beatTimestamps
        )

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
            let timelineRange = segmentRanges[index]
            let duration = timelineRange.duration
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

            if addBeatMarkers, index > 0 {
                actions.append(.addMarker(name: "Beat Cut \(index)", time: timelineRange.start))
            }
        }
        if beatTimestamps.isEmpty {
            assumptions.append("Divided \(targetDuration)s across \(photoCount) photos with alternating Ken Burns effects.")
        } else {
            assumptions.append("Beat-aligned \(photoCount) photos across \(targetDuration)s using \(beatTimestamps.count) beat candidates.")
        }

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

    /// Computes sequential photo `TimeRange`s across `0..<targetDuration`.
    /// When `beatTimestamps` are provided (`AI-06`), interior cut points snap to the closest
    /// available beat within the valid interval while preserving a minimum clip duration
    /// (`minRebalancedClipDuration = 0.5s`). Falls back to uniform intervals when no usable
    /// beats exist.
    public static func computeBeatAlignedSegments(
        photoCount: Int,
        targetDuration: TimeInterval,
        beatTimestamps: [TimeInterval]
    ) -> [TimeRange] {
        guard photoCount > 0 else { return [] }
        let baseClipDuration = targetDuration / Double(photoCount)
        guard photoCount > 1, !beatTimestamps.isEmpty else {
            return (0..<photoCount).map { index in
                let start = Double(index) * baseClipDuration
                let duration = (index == photoCount - 1) ? (targetDuration - start) : baseClipDuration
                return TimeRange(start: start, duration: duration)
            }
        }

        let minGap = min(minRebalancedClipDuration, baseClipDuration * 0.5)
        let sortedBeats = beatTimestamps
            .filter { $0.isFinite && $0 >= minGap && $0 <= targetDuration - minGap }
            .sorted()

        var cutPoints: [TimeInterval] = [0]
        for boundaryIndex in 1..<photoCount {
            let idealCut = Double(boundaryIndex) * baseClipDuration
            let prevCut = cutPoints[boundaryIndex - 1]
            let remainingCutsAfterThis = Double(photoCount - 1 - boundaryIndex)
            let earliestAllowed = prevCut + minGap
            let latestAllowed = targetDuration - (remainingCutsAfterThis + 1.0) * minGap

            let candidates = sortedBeats.filter { $0 >= earliestAllowed && $0 <= latestAllowed }
            if let nearestBeat = candidates.min(by: { abs($0 - idealCut) < abs($1 - idealCut) }),
               abs(nearestBeat - idealCut) <= baseClipDuration * 0.6 {
                cutPoints.append(nearestBeat)
            } else {
                let fallback = min(max(idealCut, earliestAllowed), latestAllowed)
                cutPoints.append(fallback)
            }
        }
        cutPoints.append(targetDuration)

        return (0..<photoCount).map { index in
            let start = cutPoints[index]
            let end = cutPoints[index + 1]
            return TimeRange(start: start, duration: max(0.001, end - start))
        }
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

    // MARK: - Follow-up Duration Rebalancing (AI-05)

    /// Request parameters for adjusting one clip's duration while keeping the montage's total duration fixed.
    public struct MontageRebalanceRequest: Sendable, Equatable {
        public let targetClipOneBasedIndex: Int
        public let deltaSeconds: TimeInterval
        public let targetTotalDurationSeconds: TimeInterval?

        public init(
            targetClipOneBasedIndex: Int,
            deltaSeconds: TimeInterval,
            targetTotalDurationSeconds: TimeInterval? = nil
        ) {
            self.targetClipOneBasedIndex = targetClipOneBasedIndex
            self.deltaSeconds = deltaSeconds
            self.targetTotalDurationSeconds = targetTotalDurationSeconds
        }
    }

    /// Minimum allowed per-clip duration when rebalancing a montage.
    public static let minRebalancedClipDuration: TimeInterval = 0.5

    /// Deterministically plans a `trimClip` + `setClipKeyframes` sequence that adjusts the target
    /// clip by `deltaSeconds` and redistributes the remaining duration across the other clips on the
    /// main video track so total duration equals `targetTotalDurationSeconds` (or current total).
    public static func planDurationRebalance(
        project: Project,
        request: MontageRebalanceRequest
    ) throws -> [EditingActionDSL.Action] {
        guard let videoTrack = project.timeline.tracks.first(where: { $0.kind == .video && !$0.clips.isEmpty }) else {
            throw EditingActionDSL.PlanningError.emptyRange
        }
        let clips = videoTrack.clips.sorted { $0.timelineRange.start < $1.timelineRange.start }
        guard clips.count >= 2 else {
            throw EditingActionDSL.PlanningError.invalidTimeValue(
                "Rebalancing requires at least 2 clips on the main video track"
            )
        }
        let targetIdx = request.targetClipOneBasedIndex - 1
        guard clips.indices.contains(targetIdx) else {
            throw EditingActionDSL.PlanningError.invalidTimeValue(
                "Target clip index \(request.targetClipOneBasedIndex) is out of range (1...\(clips.count))"
            )
        }
        guard request.deltaSeconds.isFinite, abs(request.deltaSeconds) > 0.001 else {
            throw EditingActionDSL.PlanningError.invalidTimeValue("Delta seconds must be non-zero and finite")
        }

        let currentTotal = clips.reduce(0.0) { $0 + $1.timelineRange.duration }
        let desiredTotal = request.targetTotalDurationSeconds ?? currentTotal
        guard desiredTotal.isFinite, desiredTotal > 0, desiredTotal <= Limits.maxTargetDuration else {
            throw EditingActionDSL.PlanningError.invalidTimeValue("Invalid target total duration \(desiredTotal)s")
        }

        let targetClip = clips[targetIdx]
        let newTargetDuration = targetClip.timelineRange.duration + request.deltaSeconds
        guard newTargetDuration >= minRebalancedClipDuration else {
            throw EditingActionDSL.PlanningError.invalidTimeValue(
                "Target clip duration \(newTargetDuration)s would fall below the \(minRebalancedClipDuration)s minimum"
            )
        }

        let otherIndices = clips.indices.filter { $0 != targetIdx }
        let remainingTotal = desiredTotal - newTargetDuration
        let minRequiredForOthers = Double(otherIndices.count) * minRebalancedClipDuration
        guard remainingTotal >= minRequiredForOthers - 1e-6 else {
            throw EditingActionDSL.PlanningError.invalidTimeValue(
                "Cannot keep total \(desiredTotal)s: remaining \(remainingTotal)s for \(otherIndices.count) clips is below minimum \(minRequiredForOthers)s"
            )
        }

        let currentOthersTotal = otherIndices.reduce(0.0) { $0 + clips[$1].timelineRange.duration }
        var newDurations = Array(repeating: 0.0, count: clips.count)
        newDurations[targetIdx] = newTargetDuration

        var allocatedOthers = 0.0
        for (pos, idx) in otherIndices.enumerated() {
            if pos == otherIndices.count - 1 {
                newDurations[idx] = max(minRebalancedClipDuration, remainingTotal - allocatedOthers)
            } else {
                let weight = currentOthersTotal > 0
                    ? (clips[idx].timelineRange.duration / currentOthersTotal)
                    : (1.0 / Double(otherIndices.count))
                let raw = max(minRebalancedClipDuration, remainingTotal * weight)
                newDurations[idx] = raw
                allocatedOthers += raw
            }
        }

        var actions: [EditingActionDSL.Action] = []
        var cursor: TimeInterval = 0.0
        for (idx, clip) in clips.enumerated() {
            let duration = (idx == clips.count - 1) ? max(minRebalancedClipDuration, desiredTotal - cursor) : newDurations[idx]
            let newTimelineRange = TimeRange(start: cursor, duration: duration)
            let newSourceDuration: TimeInterval
            if clip.kind == .image {
                newSourceDuration = duration
            } else if let assetId = clip.assetId,
                      let assetDuration = project.mediaLibrary.assets[assetId]?.duration {
                newSourceDuration = min(duration, max(0.01, assetDuration - clip.sourceRange.start))
            } else {
                newSourceDuration = duration
            }
            let newSourceRange = TimeRange(start: clip.sourceRange.start, duration: newSourceDuration)

            actions.append(.trimClip(
                clipId: clip.id,
                sourceRange: newSourceRange,
                timelineRange: newTimelineRange
            ))

            if !clip.keyframes.isEmpty {
                let style = motionStyle(for: idx)
                let updatedKeyframes = generateKeyframes(for: style, duration: duration)
                actions.append(.setClipKeyframes(clipId: clip.id, keyframes: updatedKeyframes))
            }

            cursor += duration
        }

        return actions
    }

    /// Parses natural-language montage rebalance instructions (Korean & English), e.g.:
    /// - "3번째 사진 2초 늘리고 전체 30초 유지"
    /// - "세 번째 사진을 2초 더 보여줘. 전체는 30초를 유지"
    /// - "make clip 3 longer by 2s and keep total 30s"
    public static func parseRebalanceInstruction(_ instruction: String) -> MontageRebalanceRequest? {
        let compact = instruction.lowercased().filter { !$0.isWhitespace }
        let hasKeepTotal = compact.contains("전체") || compact.contains("유지") || compact.contains("keeptotal") || compact.contains("total")
        let isIncrease = compact.contains("늘리") || compact.contains("늘려") || compact.contains("더보여") || compact.contains("더길게") || compact.contains("longer") || compact.contains("extend")
        let isDecrease = compact.contains("줄이") || compact.contains("줄여") || compact.contains("짧게") || compact.contains("shorter") || compact.contains("reduce")

        guard hasKeepTotal, isIncrease || isDecrease else { return nil }

        guard let ordinal = extractOrdinal(from: compact) else { return nil }
        let secValues = extractSeconds(from: compact)
        guard let firstSeconds = secValues.first, firstSeconds > 0 else { return nil }

        let signedDelta = isDecrease ? -firstSeconds : firstSeconds
        let targetTotal: TimeInterval? = secValues.count >= 2 ? secValues.last : nil

        return MontageRebalanceRequest(
            targetClipOneBasedIndex: ordinal,
            deltaSeconds: signedDelta,
            targetTotalDurationSeconds: targetTotal
        )
    }

    private static func extractOrdinal(from compact: String) -> Int? {
        let koreanWords: [(String, Int)] = [
            ("첫번째", 1), ("두번째", 2), ("세번째", 3), ("네번째", 4), ("다섯번째", 5),
            ("여섯번째", 6), ("일곱번째", 7), ("여덟번째", 8), ("아홉번째", 9), ("열번째", 10),
            ("first", 1), ("second", 2), ("third", 3), ("fourth", 4), ("fifth", 5),
        ]
        for (word, value) in koreanWords where compact.contains(word) {
            return value
        }
        for suffix in ["번째", "st", "nd", "rd", "th"] {
            var searchStart = compact.startIndex
            while let range = compact.range(of: suffix, range: searchStart..<compact.endIndex) {
                let prefix = compact[..<range.lowerBound]
                var digits = ""
                var idx = prefix.endIndex
                while idx > prefix.startIndex {
                    let prev = prefix.index(before: idx)
                    if prefix[prev].isNumber {
                        digits.insert(prefix[prev], at: digits.startIndex)
                        idx = prev
                    } else {
                        break
                    }
                }
                if let n = Int(digits), n > 0 { return n }
                searchStart = range.upperBound
            }
        }
        for prefixKey in ["clip", "photo", "사진", "클립"] {
            var searchStart = compact.startIndex
            while let range = compact.range(of: prefixKey, range: searchStart..<compact.endIndex) {
                let suffix = compact[range.upperBound...]
                var digits = ""
                var idx = suffix.startIndex
                while idx < suffix.endIndex, suffix[idx].isNumber {
                    digits.append(suffix[idx])
                    idx = suffix.index(after: idx)
                }
                if let n = Int(digits), n > 0 { return n }
                searchStart = range.upperBound
            }
        }
        return nil
    }

    private static func extractSeconds(from compact: String) -> [TimeInterval] {
        var values: [TimeInterval] = []
        var idx = compact.startIndex
        while idx < compact.endIndex {
            if compact[idx].isNumber || compact[idx] == "." {
                var digits = ""
                var scan = idx
                while scan < compact.endIndex, compact[scan].isNumber || compact[scan] == "." {
                    digits.append(compact[scan])
                    scan = compact.index(after: scan)
                }
                if scan < compact.endIndex, (compact[scan] == "초" || compact[scan] == "s"),
                   let val = Double(digits), val > 0 {
                    values.append(val)
                    scan = compact.index(after: scan)
                }
                idx = scan
            } else {
                idx = compact.index(after: idx)
            }
        }
        return values
    }
}
