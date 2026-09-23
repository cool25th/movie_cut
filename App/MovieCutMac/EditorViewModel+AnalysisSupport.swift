import Foundation
import MovieCutCore

/// Shared analysis-support boundary of the EditorViewModel decomposition
/// (review 2026-08-28 #7). These helpers serve every analysis feature
/// (subtitles, auto cut, highlights, assistant, voiceover) and previously
/// lived as file-private members of the 5,400-line main file — which made
/// every analysis section un-movable (the decomposition limit recorded in
/// the 2026-08-29 session).
///
/// Access note: `recordAnalysisResult`, `sourceClipAndAsset`,
/// `isTranscribable`, and `timelineMapping` are internal (were private) —
/// a same-target visibility widening only; the module's public surface,
/// behavior, and all call sites are unchanged. `clipDescription` stays
/// private (sole caller is in this file).
extension EditorViewModel {
    func recordAnalysisResult(
        action: String,
        count: Int?,
        message: String,
        clipId: UUID?
    ) {
        let item = AnalysisHistoryItem(
            action: action,
            count: count,
            clipDescription: clipDescription(for: clipId),
            message: message,
            timestamp: Date()
        )

        recentAnalysisResults.insert(item, at: 0)
        if recentAnalysisResults.count > 8 {
            recentAnalysisResults.removeSubrange(8...)
        }
    }

    private func clipDescription(for clipId: UUID?) -> String? {
        guard let clipId else { return nil }

        for track in currentProject.timeline.tracks {
            if let clipIndex = track.clips.firstIndex(where: { $0.id == clipId }) {
                let trackName = track.name.isEmpty ? track.kind.rawValue.capitalized : track.name
                return "\(trackName) clip \(clipIndex + 1)"
            }
        }

        return nil
    }

    func sourceClipAndAsset(for clipId: UUID, in project: Project) throws -> (clip: Clip, asset: MediaAsset) {
        for track in project.timeline.tracks {
            if let clip = track.clips.first(where: { $0.id == clipId }) {
                guard let assetId = clip.assetId else {
                    throw EditorCommandError.invalidCommand("Selected clip has no source media.")
                }
                guard let asset = project.mediaLibrary.assets[assetId] else {
                    throw EditorCommandError.assetNotFound(assetId)
                }
                guard Self.isTranscribable(asset) else {
                    throw EditorCommandError.invalidCommand("Select an audio or video clip.")
                }
                return (clip, asset)
            }
        }

        throw EditorCommandError.clipNotFound(clipId)
    }

    static func isTranscribable(_ asset: MediaAsset) -> Bool {
        asset.kind == .audio || asset.kind == .video
    }

    /// Asset-time → timeline mapping, delegated to the shared Core
    /// `Clip.timelineMapping(for:)` (single source — the iOS copy is gone).
    func timelineMapping(
        for sourceRange: TimeRange,
        in clip: Clip
    ) -> (sourceRange: TimeRange, timelineRange: TimeRange)? {
        clip.timelineMapping(for: sourceRange)
    }
}
