import AVFoundation
import CoreMedia

// ImageVideoRenderService moved to Sources/MovieCutCore/Rendering/ (shared
// with the iOS render plan, G-15 AC6). This file keeps the Mac playback
// helper below.

@MainActor
enum ReverseCompositionInserter {
    static func insertReversedFrames(
        from sourceTrack: AVAssetTrack,
        sourceTimeRange: CMTimeRange,
        into compositionTrack: AVMutableCompositionTrack,
        at destinationTime: CMTime
    ) async throws -> CMTime {
        let availableRange = try await sourceTrack.load(.timeRange)
        let effectiveRange = CMTimeRangeGetIntersection(sourceTimeRange, otherRange: availableRange)
        guard effectiveRange.isValid,
              effectiveRange.duration.isNumeric,
              effectiveRange.duration > .zero else {
            throw ReverseCompositionInserterError.invalidSourceRange
        }

        let minimumFrameDuration = try await sourceTrack.load(.minFrameDuration)
        let nominalFrameRate = try await sourceTrack.load(.nominalFrameRate)
        let frameDuration: CMTime
        if minimumFrameDuration.isNumeric, minimumFrameDuration > .zero {
            frameDuration = minimumFrameDuration
        } else if nominalFrameRate > 0 {
            frameDuration = CMTime(
                seconds: 1 / Double(nominalFrameRate),
                preferredTimescale: 60_000
            )
        } else {
            frameDuration = CMTime(value: 1, timescale: 30)
        }

        var sourceEnd = CMTimeRangeGetEnd(effectiveRange)
        var insertedDuration = CMTime.zero
        while sourceEnd > effectiveRange.start {
            try Task.checkCancellation()
            let candidateStart = CMTimeSubtract(sourceEnd, frameDuration)
            let segmentStart = candidateStart > effectiveRange.start
                ? candidateStart
                : effectiveRange.start
            let segmentDuration = CMTimeSubtract(sourceEnd, segmentStart)
            guard segmentDuration.isNumeric, segmentDuration > .zero else { break }

            try compositionTrack.insertTimeRange(
                CMTimeRange(start: segmentStart, duration: segmentDuration),
                of: sourceTrack,
                at: CMTimeAdd(destinationTime, insertedDuration)
            )
            insertedDuration = CMTimeAdd(insertedDuration, segmentDuration)
            sourceEnd = segmentStart
        }

        guard insertedDuration.isNumeric, insertedDuration > .zero else {
            throw ReverseCompositionInserterError.noFramesInserted
        }
        return insertedDuration
    }
}

private enum ReverseCompositionInserterError: LocalizedError {
    case invalidSourceRange
    case noFramesInserted

    var errorDescription: String? {
        switch self {
        case .invalidSourceRange:
            return "The reverse clip source range is invalid."
        case .noFramesInserted:
            return "The reverse clip did not contain any insertable frames."
        }
    }
}
