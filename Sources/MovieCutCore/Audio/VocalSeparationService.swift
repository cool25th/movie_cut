import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Separation modes for center-channel stem extraction.
public enum VocalSeparationMode: String, Sendable, Equatable, CaseIterable {
    /// Cancel center-panned content (karaoke / instrumental).
    case removeVocals
    /// Keep center-panned content (approximate vocal isolation).
    case isolateCenter
}

/// A block of interleaved-by-channel stereo audio samples in `[-1, 1]`.
public struct StereoFrames: Sendable, Equatable {
    /// Left-channel samples.
    public var left: [Float]
    /// Right-channel samples.
    public var right: [Float]

    /// Creates stereo frames.
    public init(left: [Float], right: [Float]) {
        self.left = left
        self.right = right
    }

    /// The number of usable frames (the shorter of the two channels).
    public var frameCount: Int {
        min(left.count, right.count)
    }
}

/// A stereo stem separator. Conformers may be DSP-based or, in future, ML-based.
public protocol AudioStemSeparator: Sendable {
    /// Processes stereo frames for the requested mode.
    func process(_ frames: StereoFrames, mode: VocalSeparationMode) -> StereoFrames
}

/// Real-time-friendly vocal separation using center-channel (mid/side)
/// cancellation.
///
/// Lead vocals are typically panned to the center, so they appear nearly
/// identically in the left and right channels. Estimating the center as
/// `mid = (L + R) / 2` lets the processor either subtract it (karaoke) or keep
/// it (isolation). This is a true DSP technique — not ML stem separation — so it
/// works best on center-panned vocals and leaves stereo-panned instruments
/// audible. The ``AudioStemSeparator`` protocol is the seam for a future ML
/// provider (e.g. a Demucs-style model) without changing call sites.
public struct CenterChannelVocalSeparator: AudioStemSeparator {
    /// Effect amount in `[0, 1]`; 0 is a passthrough, 1 is full cancellation/isolation.
    public let wetMix: Float

    /// Creates a center-channel vocal separator.
    public init(wetMix: Float = 1) {
        self.wetMix = min(max(wetMix, 0), 1)
    }

    public func process(_ frames: StereoFrames, mode: VocalSeparationMode) -> StereoFrames {
        let count = frames.frameCount
        guard count > 0 else {
            return StereoFrames(left: [], right: [])
        }

        var outLeft = [Float](repeating: 0, count: count)
        var outRight = [Float](repeating: 0, count: count)
        let wet = wetMix
        let dry = 1 - wet

        for index in 0..<count {
            let left = frames.left[index]
            let right = frames.right[index]
            let mid = (left + right) * 0.5

            switch mode {
            case .removeVocals:
                // Subtract the estimated center from each channel. Fully wet
                // yields the side signal (L−R)/2 and its inverse, cancelling
                // anything panned dead-center while preserving panned content.
                outLeft[index] = left - wet * mid
                outRight[index] = right - wet * mid
            case .isolateCenter:
                // Blend toward the mono center estimate, emphasizing center-
                // panned content (the approximate vocal).
                outLeft[index] = dry * left + wet * mid
                outRight[index] = dry * right + wet * mid
            }
        }

        return StereoFrames(left: outLeft, right: outRight)
    }
}

#if canImport(AVFoundation)
public extension CenterChannelVocalSeparator {
    /// Processes a non-interleaved stereo float `AVAudioPCMBuffer` and returns a
    /// new buffer with the separation applied. Returns nil for unsupported
    /// formats (non-float, or fewer than two channels).
    func process(buffer: AVAudioPCMBuffer, mode: VocalSeparationMode) -> AVAudioPCMBuffer? {
        guard let channels = buffer.floatChannelData,
              buffer.format.channelCount >= 2,
              buffer.format.commonFormat == .pcmFormatFloat32 else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return buffer }

        let leftPointer = channels[0]
        let rightPointer = channels[1]
        let left = Array(UnsafeBufferPointer(start: leftPointer, count: frameLength))
        let right = Array(UnsafeBufferPointer(start: rightPointer, count: frameLength))

        let processed = process(StereoFrames(left: left, right: right), mode: mode)
        for index in 0..<frameLength {
            leftPointer[index] = processed.left[index]
            rightPointer[index] = processed.right[index]
        }
        return buffer
    }
}
#endif
