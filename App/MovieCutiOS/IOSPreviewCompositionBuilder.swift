import AVFoundation
import CoreMedia
import Foundation
import MovieCutCore

/// Builds the iOS PREVIEW composition from project state — extracted from
/// PreviewView so the G-27 simulator harness drives the SAME preview path
/// the app renders (no parallel reimplementation to drift).
enum IOSPreviewCompositionBuilder {
    /// Inserts every playable track (video + embedded audio, audio clips)
    /// into `composition` and returns whether any playable media landed.
    @discardableResult
    static func populate(
        _ composition: AVMutableComposition,
        from project: Project
    ) -> Bool {
        var insertedPlayableMedia = false
        for timelineTrack in project.timeline.tracks.sorted(by: { $0.zIndex < $1.zIndex }) {
            switch timelineTrack.kind {
            case .video:
                insertedPlayableMedia = insertVideoTrack(timelineTrack, from: project, into: composition) || insertedPlayableMedia
            case .audio:
                insertedPlayableMedia = insertAudioTrack(timelineTrack, from: project, into: composition) || insertedPlayableMedia
            case .text:
                continue
            }
        }
        return insertedPlayableMedia
    }

    private static func insertVideoTrack(
        _ timelineTrack: Track,
        from project: Project,
        into composition: AVMutableComposition
    ) -> Bool {
        let clips = timelineTrack.clips
            .filter { $0.kind == .video }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
        guard !clips.isEmpty else { return false }

        let videoTrack = timelineTrack.isHidden ? nil : composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioTrack = (timelineTrack.isMuted
            || audioSoloSuppresses(timelineTrack, in: project)) ? nil : composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var videoCursor = CMTime.zero
        var audioCursor = CMTime.zero
        var inserted = false

        for clip in clips {
            guard let asset = asset(for: clip, in: project) else { continue }
            if let videoTrack {
                inserted = insertClip(clip, mediaType: .video, from: asset, into: videoTrack, cursor: &videoCursor) || inserted
            }
            if let audioTrack {
                _ = insertClip(clip, mediaType: .audio, from: asset, into: audioTrack, cursor: &audioCursor)
            }
        }

        return inserted
    }

    /// G-25 Inc 9 audio solo: true when some audio-capable track is soloed
    /// and this track is not — silence this track's audio, keep its video.
    private static func audioSoloSuppresses(_ track: Track, in project: Project) -> Bool {
        guard project.timeline.tracks.contains(where: { $0.isSolo && $0.kind != .text }) else {
            return false
        }
        return !track.isSolo
    }

    private static func insertAudioTrack(
        _ timelineTrack: Track,
        from project: Project,
        into composition: AVMutableComposition
    ) -> Bool {
        guard !timelineTrack.isMuted, !audioSoloSuppresses(timelineTrack, in: project) else { return false }
        let clips = timelineTrack.clips
            .filter { $0.kind == .audio || $0.kind == .video }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
        guard !clips.isEmpty, let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return false }

        var cursor = CMTime.zero
        var inserted = false
        for clip in clips {
            guard let asset = asset(for: clip, in: project) else { continue }
            inserted = insertClip(clip, mediaType: .audio, from: asset, into: audioTrack, cursor: &cursor) || inserted
        }
        return inserted
    }

    private static func asset(for clip: Clip, in project: Project) -> AVURLAsset? {
        guard let assetId = clip.assetId, let mediaAsset = project.mediaLibrary.assets[assetId] else { return nil }
        return AVURLAsset(url: mediaAsset.originalURL)
    }

    @discardableResult
    private static func insertClip(
        _ clip: Clip,
        mediaType: AVMediaType,
        from asset: AVURLAsset,
        into compositionTrack: AVMutableCompositionTrack,
        cursor: inout CMTime
    ) -> Bool {
        guard let sourceTrack = asset.tracks(withMediaType: mediaType).first,
              let sourceRange = sourceTimeRange(for: clip) else { return false }

        let timelineStart = cmTime(clip.timelineRange.start)
        guard CMTimeCompare(timelineStart, cursor) >= 0 else { return false }
        if CMTimeCompare(cursor, timelineStart) < 0 {
            let gap = CMTimeSubtract(timelineStart, cursor)
            compositionTrack.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: gap))
            cursor = timelineStart
        }

        do {
            try compositionTrack.insertTimeRange(sourceRange, of: sourceTrack, at: cursor)

            // Scale by the constant playback rate so the preview duration
            // matches the timeline (a 2x clip plays in half the time). Speed
            // ramps on iOS preview fall back to the clip's baseline rate
            // (ramp segment scaling is in the export engine).
            let playbackRate = min(max(clip.playbackRate, 0.25), 4.0)
            if clip.speedRampPoints.count < 2, playbackRate != 1 {
                let scaledDuration = CMTime(
                    seconds: sourceRange.duration.seconds / playbackRate,
                    preferredTimescale: 600
                )
                let insertedRange = CMTimeRange(start: cursor, duration: sourceRange.duration)
                compositionTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                cursor = CMTimeAdd(cursor, scaledDuration)
            } else {
                cursor = CMTimeAdd(cursor, sourceRange.duration)
            }
            return true
        } catch {
            return false
        }
    }

    private static func sourceTimeRange(for clip: Clip) -> CMTimeRange? {
        // Derive the source range from the canonical mapping so the preview
        // reflects the correct source coverage for any rate. For
        // freeze-frames (tiny source over long timeline), keep the minimal
        // source window — the timeline span is produced by scaleTimeRange.
        if let mapping = clip.makeTimeMapping() {
            let renderedDuration = mapping.renderedTimelineDuration
            guard renderedDuration > 0 else { return nil }
            let sourceDuration = max(clip.sourceRange.duration, 0)
            guard sourceDuration > 0 else { return nil }
            return CMTimeRange(start: cmTime(clip.sourceRange.start), duration: cmTime(sourceDuration))
        }
        let duration = min(max(clip.sourceRange.duration, 0), max(clip.timelineRange.duration, 0))
        guard duration > 0 else { return nil }
        return CMTimeRange(start: cmTime(clip.sourceRange.start), duration: cmTime(duration))
    }

    private static func cmTime(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
