import Foundation
import Testing

/// The macOS app target owns AVFoundation preview composition. These checks keep
/// speed ramp preview routing visible in SwiftPM's static contract loop.
@Suite("SpeedRamp Preview StaticContract")
struct SpeedRampPreviewStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw SpeedRampPreviewStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw SpeedRampPreviewStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Mac PlaybackEngine speed ramp preview segments and scales composition time")
    func playbackEngineSegmentsAndScalesSpeedRampPreview() throws {
        let source = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")

        #expect(source.contains("insertSpeedRampSegments("))
        #expect(source.contains("clip.speedRampPoints.count >= 2"))
        #expect(source.contains("SpeedRampCurve(points: clip.speedRampPoints)"))
        #expect(source.contains("compositionTrack.scaleTimeRange"))

        let videoBranch = try section(
            in: source,
            from: "if isFreezeFrame {",
            to: "let preferredTransform = try await sourceTrack.load(.preferredTransform)"
        )
        #expect(videoBranch.contains("clip.speedRampPoints.count >= 2"))
        #expect(videoBranch.contains("targetDuration = try insertSpeedRampSegments("))
        #expect(videoBranch.contains("SpeedRampCurve(points: clip.speedRampPoints)"))
        #expect(videoBranch.contains("compositionTrack: videoCompositionTrack"))

        let embeddedAudioBranch = try section(
            in: source,
            from: "if !isFreezeFrame,\n                       let audioCompositionTrack",
            to: "applyAudioVolumeAndFades("
        )
        #expect(embeddedAudioBranch.contains("clip.speedRampPoints.count >= 2"))
        #expect(embeddedAudioBranch.contains("targetDuration = try insertSpeedRampSegments("))
        #expect(embeddedAudioBranch.contains("SpeedRampCurve(points: clip.speedRampPoints)"))
        #expect(embeddedAudioBranch.contains("compositionTrack: audioCompositionTrack"))

        let audioTrackBranch = try section(
            in: source,
            from: "case .audio:",
            to: "case .text:"
        )
        #expect(audioTrackBranch.contains("clip.speedRampPoints.count >= 2"))
        #expect(audioTrackBranch.contains("targetDuration = try insertSpeedRampSegments("))
        #expect(audioTrackBranch.contains("SpeedRampCurve(points: clip.speedRampPoints)"))
        #expect(audioTrackBranch.contains("compositionTrack: audioCompositionTrack"))
    }

    @Test("Backlog marks speed ramp preview and export complete with optical flow still separate")
    func backlogMarksSpeedRampPreviewAndExportComplete() throws {
        let source = try source("docs/CAPCUT_FEATURE_BACKLOG.md")

        #expect(source.contains("- [x] ✅ 속도 조절 / speed ramp preview+export (P1)"))
        #expect(source.contains("Mac `PlaybackEngine` preview와 `ExportEngine` export"))
        #expect(source.contains("SpeedRampCurve(points: clip.speedRampPoints)"))
        #expect(source.contains("scaleTimeRange"))
        #expect(source.contains("audio preview path"))
        #expect(source.contains("- [ ] ❌ 옵티컬 플로우 보간(부드러운 슬로우모션) (P3)"))
        #expect(source.contains("다음 1순위는 F-01 실기기 검증"))
        #expect(!source.contains("preview 미반영"))
        #expect(!source.contains("다음 1순위는 speed ramp preview"))
    }
}

private enum SpeedRampPreviewStaticContractError: Error {
    case missingMarker(String)
}
