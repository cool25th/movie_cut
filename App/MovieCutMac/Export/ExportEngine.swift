import AVFoundation
import Foundation
import MovieCutCore
import Observation

@MainActor
@Observable
final class ExportEngine {
    var isExporting = false
    var exportProgress: Double = 0
    var exportError: String?

    @ObservationIgnored private var activeExportSession: AVAssetExportSession?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    func export(project: Project, to url: URL) async throws {
        isExporting = true
        exportProgress = 0
        exportError = nil

        do {
            let exportPackage = try await makeExportPackage(for: project)
            guard !exportPackage.composition.tracks.isEmpty else {
                throw ExportEngineError.noExportableMedia
            }

            let presetName = presetName(for: project.exportSettings)
            guard let exportSession = AVAssetExportSession(asset: exportPackage.composition, presetName: presetName) else {
                throw ExportEngineError.exportSessionCreationFailed
            }

            exportSession.videoComposition = exportPackage.videoComposition
            exportSession.audioMix = exportPackage.audioMix
            activeExportSession = exportSession
            startProgressPolling()

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            let fileType = outputFileType(for: url, settings: project.exportSettings, supportedFileTypes: exportSession.supportedFileTypes)
            try await exportSession.export(to: url, as: fileType)
            exportProgress = 1
            finishExport()
        } catch {
            exportError = error.localizedDescription
            finishExport()
            throw error
        }
    }

    private func makeExportPackage(for project: Project) async throws -> ExportPackage {
        let composition = AVMutableComposition()
        var videoCompositionTracks: [AVCompositionTrack] = []
        var audioMixInputParameters: [AVAudioMixInputParameters] = []

        for track in project.timeline.tracks where !track.isMuted {
            guard let mediaType = mediaType(for: track.kind) else { continue }

            var destinationTrack: AVMutableCompositionTrack?
            let audioParameters = AVMutableAudioMixInputParameters()

            for clip in track.clips {
                guard let assetId = clip.assetId,
                      let mediaAsset = project.mediaLibrary.assets[assetId] else {
                    continue
                }

                let sourceAsset = AVURLAsset(url: mediaAsset.originalURL)
                guard let sourceTrack = try await sourceAsset.loadTracks(withMediaType: mediaType).first else {
                    continue
                }

                let compositionTrack: AVMutableCompositionTrack
                if let destinationTrack {
                    compositionTrack = destinationTrack
                } else {
                    guard let createdTrack = composition.addMutableTrack(
                        withMediaType: mediaType,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else {
                        throw ExportEngineError.compositionTrackCreationFailed
                    }
                    createdTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
                    destinationTrack = createdTrack
                    compositionTrack = createdTrack

                    if mediaType == .video {
                        videoCompositionTracks.append(createdTrack)
                    } else if mediaType == .audio {
                        audioParameters.trackID = createdTrack.trackID
                    }
                }

                let sourceTimeRange = CMTimeRange(
                    start: CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600),
                    duration: CMTime(seconds: clip.sourceRange.duration, preferredTimescale: 600)
                )
                let destinationTime = CMTime(seconds: clip.timelineRange.start, preferredTimescale: 600)
                try compositionTrack.insertTimeRange(sourceTimeRange, of: sourceTrack, at: destinationTime)

                let playbackRate = min(max(clip.playbackRate, 0.25), 4.0)
                if playbackRate != 1 {
                    let scaledDuration = CMTime(seconds: clip.sourceRange.duration / playbackRate, preferredTimescale: 600)
                    let insertedRange = CMTimeRange(start: destinationTime, duration: sourceTimeRange.duration)
                    compositionTrack.scaleTimeRange(insertedRange, toDuration: scaledDuration)
                }

                if mediaType == .audio {
                    audioParameters.setVolume(Float(clip.volume), at: destinationTime)
                }
            }

            if mediaType == .audio, destinationTrack != nil {
                audioMixInputParameters.append(audioParameters)
            }
        }

        let videoComposition = makeVideoComposition(
            tracks: videoCompositionTracks,
            duration: composition.duration,
            canvas: project.canvas
        )
        let audioMix = makeAudioMix(parameters: audioMixInputParameters)

        return ExportPackage(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix
        )
    }

    private func makeVideoComposition(
        tracks: [AVCompositionTrack],
        duration: CMTime,
        canvas: CanvasPreset
    ) -> AVMutableVideoComposition? {
        guard !tracks.isEmpty else { return nil }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvas.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(canvas.frameRate.framesPerSecond))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = tracks.map { AVMutableVideoCompositionLayerInstruction(assetTrack: $0) }
        videoComposition.instructions = [instruction]

        return videoComposition
    }

    private func makeAudioMix(parameters: [AVAudioMixInputParameters]) -> AVMutableAudioMix? {
        guard !parameters.isEmpty else { return nil }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return audioMix
    }

    private func mediaType(for trackKind: TrackKind) -> AVMediaType? {
        switch trackKind {
        case .video:
            return .video
        case .audio:
            return .audio
        case .text:
            return nil
        }
    }

    private func presetName(for settings: ExportSettings) -> String {
        switch (settings.codec, settings.resolution) {
        case (.hevc, .p1080):
            return AVAssetExportPresetHEVC1920x1080
        case (.hevc, .p4K):
            return AVAssetExportPresetHEVC3840x2160
        case (.hevc, .p720):
            return AVAssetExportPresetHEVCHighestQuality
        case (.h264, .p720):
            return AVAssetExportPreset1280x720
        case (.h264, .p1080):
            return AVAssetExportPreset1920x1080
        case (.h264, .p4K):
            return AVAssetExportPreset3840x2160
        }
    }

    private func outputFileType(
        for url: URL,
        settings: ExportSettings,
        supportedFileTypes: [AVFileType]
    ) -> AVFileType {
        let requested: AVFileType
        switch url.pathExtension.lowercased() {
        case "mov":
            requested = .mov
        case "m4v":
            requested = .m4v
        default:
            requested = settings.codec == .hevc ? .mov : .mp4
        }

        if supportedFileTypes.contains(requested) {
            return requested
        }

        if supportedFileTypes.contains(.mp4) {
            return .mp4
        }

        return supportedFileTypes.first ?? .mov
    }

    private func startProgressPolling() {
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let activeExportSession {
                    exportProgress = Double(activeExportSession.progress)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func finishExport() {
        progressTask?.cancel()
        progressTask = nil
        activeExportSession = nil
        isExporting = false
    }
}

private struct ExportPackage {
    var composition: AVMutableComposition
    var videoComposition: AVMutableVideoComposition?
    var audioMix: AVMutableAudioMix?
}

private enum ExportEngineError: LocalizedError {
    case compositionTrackCreationFailed
    case exportSessionCreationFailed
    case noExportableMedia

    var errorDescription: String? {
        switch self {
        case .compositionTrackCreationFailed:
            return "Could not create an export composition track."
        case .exportSessionCreationFailed:
            return "Could not create an AVAsset export session."
        case .noExportableMedia:
            return "The project does not contain exportable media."
        }
    }
}

private extension ExportResolution {
    var renderSize: CGSize {
        switch self {
        case .p720:
            return CGSize(width: 1280, height: 720)
        case .p1080:
            return CGSize(width: 1920, height: 1080)
        case .p4K:
            return CGSize(width: 3840, height: 2160)
        }
    }
}

private extension ExportFrameRate {
    var framesPerSecond: Int32 {
        switch self {
        case .fps24:
            return 24
        case .fps30:
            return 30
        case .fps60:
            return 60
        }
    }
}
