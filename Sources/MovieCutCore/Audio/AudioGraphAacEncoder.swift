import AVFoundation
import Foundation

/// G-25 switchover 2C — the export-side AAC encoder: graph PCM (§9.1b, the
/// encoder-input render) written into an .m4a as AAC. Export paths that used
/// to let AVAssetExportSession mix and encode the composition now encode the
/// graph's mix directly — from here the audio samples in an exported file
/// can only originate from the graph ("그 외 어떤 경로도 오디오 픽셀(샘플)을
/// 만들지 않는다", spec §1).
public enum AudioGraphAacEncoder {
    public enum EncodeError: Error, Equatable {
        case formatCreationFailed
        case writeFailed(String)
    }

    /// Chunk size for writing — the input PCM already lives in memory as one
    /// interleaved array, so the encoder avoids a second full-size PCM copy.
    private static let chunkFrames = 65_536

    /// Writes interleaved float PCM (up to stereo, any graph rate) as
    /// high-quality AAC. The codec's priming/padding frames are inherent to
    /// AAC — §8's re-decode comparison accounts for them at the caller.
    public static func encode(
        _ audio: AudioGraphSourceAudio,
        to url: URL,
        bitrate: Int = 192_000
    ) throws {
        guard audio.frameCount > 0, audio.sampleRate > 0 else {
            throw EncodeError.writeFailed("empty PCM")
        }
        let channels = AVAudioChannelCount(max(1, min(2, audio.channels)))
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: audio.sampleRate, channels: channels
        ) else {
            throw EncodeError.formatCreationFailed
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: bitrate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: Int(channels),
        ]
        do {
            let file = try AVAudioFile(
                forWriting: url, settings: settings,
                commonFormat: .pcmFormatFloat32, interleaved: false
            )
            guard let chunk = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkFrames)
            ) else {
                throw EncodeError.formatCreationFailed
            }
            var frame = 0
            while frame < audio.frameCount {
                let frames = min(chunkFrames, audio.frameCount - frame)
                chunk.frameLength = AVAudioFrameCount(frames)
                if let data = chunk.floatChannelData {
                    for channel in 0..<Int(channels) {
                        let sourceChannel = min(channel, audio.channels - 1)
                        for index in 0..<frames {
                            data[channel][index] = audio.sample(
                                frame: frame + index, channel: sourceChannel
                            )
                        }
                    }
                }
                try file.write(from: chunk)
                frame += frames
            }
        } catch let error as EncodeError {
            throw error
        } catch {
            throw EncodeError.writeFailed(error.localizedDescription)
        }
    }
}
