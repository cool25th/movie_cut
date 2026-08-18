import AVFoundation
import Foundation

/// G-25 spec §3.1 — the engine-adapter half of source normalization: the
/// audio entering a graph is ALWAYS at the graph rate and speed 1, and the
/// adapter owns getting it there.
///
/// - **decode** any media file's audio: `AVAudioFile` for audio-only
///   containers, `AVAssetReader` for video containers' embedded audio
///   tracks. Audio-less video decodes to an explicit silent source — that
///   IS its actual contribution to the mix — while a media file whose
///   audio track exists but cannot be read THROWS (never a silent
///   quality downgrade).
/// - **resample** to the graph rate with `AVAudioConverter` (high
///   quality). The offline renderer's nearest-frame ratio read stays a
///   §9.2 synthetic-dummy fallback; the product path never uses it.
/// - **timeStretched** pre-renders clip speed (0.25–4) with
///   `AVAudioUnitTimePitch` in an offline-rendering engine — the same
///   time-domain pitch-preserving family the AVFoundation path applies
///   via `scaleTimeRange`.
///
/// Reverse is deliberately NOT here: the product already materializes
/// reversed clips as pre-rendered media files (`temporaryReverseRenderURLs`),
/// so for the graph a reversed clip is just another effective-media source
/// (spec §0) the wiring supplies. Speed RAMPS likewise need pre-rendered
/// media (a single rate cannot reproduce a curve) — wiring-increment work.
public enum AudioGraphSourceAdapter {
    public enum AdapterError: Error, Equatable {
        case bufferUnavailable
        case readerStartFailed(String)
        case renderFailed(String)
    }

    /// The full §3.1 pipeline for one source: decode → resample to the
    /// graph rate → speed pre-render. `speed` is the product's clipped
    /// playback rate (1 = no stretch).
    public static func normalizedAudio(
        fileAt url: URL,
        graphSampleRate: Double = 48_000,
        speed: Double = 1
    ) async throws -> AudioGraphSourceAudio {
        var audio = try await decode(fileAt: url)
        if audio.sampleRate != graphSampleRate {
            audio = try resample(audio, to: graphSampleRate)
        }
        if speed != 1 {
            audio = try timeStretched(audio, speed: speed)
        }
        return audio
    }

    // MARK: - Decode

    public static func decode(fileAt url: URL) async throws -> AudioGraphSourceAudio {
        if let decoded = try? AudioGraphExportPostCheck.decode(fileAt: url), decoded.frameCount > 0 {
            return decoded
        }
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            // No audio track at all (e.g. a silent video fixture): silence
            // is the honest representation of what this media contributes.
            return AudioGraphSourceAudio(sampleRate: 48_000, channels: 2, interleaved: [0, 0])
        }
        return try readEmbeddedAudio(from: asset, track: track)
    }

    /// Extracts a video container's first audio track as interleaved float
    /// PCM via `AVAssetReader` (`AVAudioFile` cannot open video files).
    private static func readEmbeddedAudio(
        from asset: AVURLAsset,
        track: AVAssetTrack
    ) throws -> AudioGraphSourceAudio {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw AdapterError.readerStartFailed(reader.error?.localizedDescription ?? "unknown")
        }

        var interleaved = [Float]()
        var sampleRate = 0.0
        var channels = 0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if sampleRate == 0,
               let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) {
                sampleRate = asbd.pointee.mSampleRate
                channels = Int(asbd.pointee.mChannelsPerFrame)
            }
            var bufferList = AudioBufferList()
            let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                bufferListSizeNeededOut: nil,
                bufferListOut: &bufferList,
                bufferListSize: MemoryLayout<AudioBufferList>.size,
                blockBufferAllocator: kCFAllocatorDefault,
                blockBufferMemoryAllocator: kCFAllocatorDefault,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: nil
            )
            guard status == noErr else { continue }
            for buffer in UnsafeMutableAudioBufferListPointer(&bufferList) {
                let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                guard floatCount > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                interleaved.append(contentsOf: UnsafeBufferPointer(start: data, count: floatCount))
            }
        }
        guard reader.status != .failed else {
            throw AdapterError.renderFailed(reader.error?.localizedDescription ?? "read failed")
        }
        guard sampleRate > 0, channels > 0 else {
            throw AdapterError.renderFailed("no audio format description in track output")
        }
        return AudioGraphSourceAudio(sampleRate: sampleRate, channels: channels, interleaved: interleaved)
    }

    // MARK: - Resample

    /// Rate conversion with `AVAudioConverter` at high quality. Identity
    /// when the rate already matches (or the audio is empty).
    public static func resample(
        _ audio: AudioGraphSourceAudio,
        to rate: Double
    ) throws -> AudioGraphSourceAudio {
        guard audio.sampleRate != rate, audio.frameCount > 0, audio.sampleRate > 0 else {
            return audio
        }
        let channelCount = AVAudioChannelCount(max(1, audio.channels))
        guard let inFormat = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: channelCount),
              let outFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channelCount),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(audio.frameCount)) else {
            throw AdapterError.bufferUnavailable
        }
        fillNonInterleaved(inBuffer, from: audio)

        guard let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw AdapterError.bufferUnavailable
        }
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue

        // The converter's input handler is @Sendable; the one-shot feed
        // state lives behind a reference so the closure can consume it.
        // The handler signals .endOfStream (not .noDataNow) once the input
        // is spent so the converter FLUSHES its filter tail, and each
        // convert(to:) call REPLACES the chunk's frameLength — production
        // is accumulated here, not in one buffer.
        final class SourceFeed: @unchecked Sendable {
            let buffer: AVAudioPCMBuffer
            var exhausted = false
            init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        }
        let feed = SourceFeed(buffer: inBuffer)
        var conversionError: NSError?
        var interleaved = [Float]()
        var produced: AVAudioFrameCount = 0
        let expected = AVAudioFrameCount(Double(audio.frameCount) * rate / audio.sampleRate)
        guard let chunk = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 65_536) else {
            throw AdapterError.bufferUnavailable
        }
        while produced < expected + 4_096 {
            let status = converter.convert(to: chunk, error: &conversionError) { _, outStatus in
                if feed.exhausted {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                feed.exhausted = true
                outStatus.pointee = .haveData
                return feed.buffer
            }
            if status == .error {
                throw conversionError ?? AdapterError.renderFailed("resample failed")
            }
            if chunk.frameLength > 0, let data = chunk.floatChannelData {
                for frame in 0..<Int(chunk.frameLength) {
                    for channel in 0..<Int(channelCount) {
                        interleaved.append(data[channel][frame])
                    }
                }
                produced += chunk.frameLength
            }
            if status == .endOfStream || chunk.frameLength == 0 { break }
        }
        return AudioGraphSourceAudio(sampleRate: rate, channels: Int(channelCount), interleaved: interleaved)
    }

    // MARK: - Speed pre-render

    /// Speed ≠ 1 pre-render (§3.1): offline `AVAudioEngine` manual
    /// rendering through `AVAudioUnitTimePitch` (pitch-preserving, the
    /// time-domain family `scaleTimeRange` applies). Rate stays at the
    /// input's sample rate — only the DURATION changes (frames ÷ speed).
    ///
    /// Mono input renders as dual-mono stereo: the offline engine's mono
    /// path attenuates by 1/√2 (measured — a mono bypass render comes out
    /// −3 dB while stereo is unity), and the graph's .mono channel mapping
    /// feeds both L and R anyway, so dual-mono stereo is acoustically
    /// identical to a stretched mono source.
    public static func timeStretched(
        _ audio: AudioGraphSourceAudio,
        speed: Double
    ) throws -> AudioGraphSourceAudio {
        guard speed != 1, speed > 0, audio.frameCount > 0, audio.sampleRate > 0 else {
            return audio
        }
        // Always render in stereo (mono input upmixed to dual-mono).
        let renderChannels = 2
        guard let format = AVAudioFormat(
                  standardFormatWithSampleRate: audio.sampleRate,
                  channels: AVAudioChannelCount(renderChannels)
              ),
              let inBuffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(audio.frameCount)
              ) else {
            throw AdapterError.bufferUnavailable
        }
        inBuffer.frameLength = AVAudioFrameCount(audio.frameCount)
        if let channelData = inBuffer.floatChannelData {
            for frame in 0..<audio.frameCount {
                for channel in 0..<renderChannels {
                    channelData[channel][frame] = audio.sample(
                        frame: frame, channel: min(channel, audio.channels - 1)
                    )
                }
            }
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = Float(speed)
        engine.attach(player)
        engine.attach(timePitch)
        try engine.enableManualRenderingMode(
            .offline, format: format, maximumFrameCount: 4_096
        )
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        player.scheduleBuffer(inBuffer)
        player.play()
        defer {
            player.stop()
            engine.stop()
        }

        // `isPlaying` never goes false under offline rendering, so the stop
        // condition is the expected frame count plus an algorithm-tail
        // margin; the exact-zero tail is trimmed afterwards.
        let expected = Double(audio.frameCount) / speed
        let frameCeiling = expected + 48_000
        var interleaved = [Float]()
        interleaved.reserveCapacity(Int(expected) * renderChannels + 16_384)
        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
            throw AdapterError.bufferUnavailable
        }
        while Double(interleaved.count / renderChannels) < frameCeiling {
            chunk.frameLength = 0
            let status = try engine.renderOffline(4_096, to: chunk)
            guard status == .success, chunk.frameLength > 0 else { break }
            if let data = chunk.floatChannelData {
                for frame in 0..<Int(chunk.frameLength) {
                    for channel in 0..<renderChannels {
                        interleaved.append(data[channel][frame])
                    }
                }
            }
        }
        while interleaved.count >= renderChannels {
            let frameStart = interleaved.count - renderChannels
            let frameIsSilent = (0..<renderChannels).allSatisfy { interleaved[frameStart + $0] == 0 }
            if frameIsSilent {
                interleaved.removeLast(renderChannels)
            } else {
                break
            }
        }
        return AudioGraphSourceAudio(
            sampleRate: audio.sampleRate,
            channels: renderChannels,
            interleaved: interleaved
        )
    }

    // MARK: - Buffer helpers

    private static func fillNonInterleaved(
        _ buffer: AVAudioPCMBuffer,
        from audio: AudioGraphSourceAudio
    ) {
        buffer.frameLength = AVAudioFrameCount(audio.frameCount)
        guard let channelData = buffer.floatChannelData else { return }
        for channel in 0..<audio.channels {
            for frame in 0..<audio.frameCount {
                channelData[channel][frame] = audio.sample(frame: frame, channel: channel)
            }
        }
    }
}
