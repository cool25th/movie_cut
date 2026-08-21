import AVFoundation
import Foundation

/// G-25 spec §8 — the output-quality gate as pure Core functions: after an
/// export finishes, the ACTUAL encoded file is re-decoded (never the
/// pre-encoder PCM) and checked against the reference render:
///
/// 1. re-decoded PCM ↔ reference PCM: length within ±1 sample (gate) and an
///    RMS difference (REPORTED, never gated — lossy codecs change RMS),
/// 2. LUFS-I / true peak measured on the decoded file → guideline warnings,
/// 3. clipping (runs of full-scale samples) → warning.
///
/// Stage-1 policy (spec §8): warnings NEVER block. `passed` is the length
/// gate plus a successful measurement; every guideline breach lands in
/// `warnings` for the E2E gate to report. §8's "±1 sample" applies to the
/// reference-vs-decoded PCM pair; an AAC stream's codec priming/padding
/// frames are the CALLER's to trim (AVAssetExportSession writes gapless
/// metadata, but AVAudioFile does not apply it on read) — the check itself
/// stays exact.
public enum AudioGraphExportPostCheck {
    public struct Report: Sendable, Equatable {
        public var referenceFrames: Int
        public var decodedFrames: Int
        /// §8.1 gate: |length difference| ≤ 1 sample.
        public var lengthWithinOneSample: Bool
        /// §8.1 report: reference RMS − decoded RMS over the compared
        /// overlap, in dB.
        public var rmsDifferenceDb: Double
        public var referenceMeasurement: AudioGraphLoudness.Measurement
        public var decodedMeasurement: AudioGraphLoudness.Measurement
        public var clippingRunCount: Int
        public var maxClippingRunLength: Int
        /// Loudness guideline outcome (§7 band −16…−14 LUFS-I / ≤ −1 dBTP)
        /// when a target was given; nil = no target declared.
        public var withinLoudnessGuideline: Bool?
        /// Human-readable, non-blocking warnings (§8.2·§8.3).
        public var warnings: [String]
        /// Length gate only — warnings never block in stage 1 (§8).
        public var passed: Bool

        public init(
            referenceFrames: Int,
            decodedFrames: Int,
            lengthWithinOneSample: Bool,
            rmsDifferenceDb: Double,
            referenceMeasurement: AudioGraphLoudness.Measurement,
            decodedMeasurement: AudioGraphLoudness.Measurement,
            clippingRunCount: Int,
            maxClippingRunLength: Int,
            withinLoudnessGuideline: Bool?,
            warnings: [String],
            passed: Bool
        ) {
            self.referenceFrames = referenceFrames
            self.decodedFrames = decodedFrames
            self.lengthWithinOneSample = lengthWithinOneSample
            self.rmsDifferenceDb = rmsDifferenceDb
            self.referenceMeasurement = referenceMeasurement
            self.decodedMeasurement = decodedMeasurement
            self.clippingRunCount = clippingRunCount
            self.maxClippingRunLength = maxClippingRunLength
            self.withinLoudnessGuideline = withinLoudnessGuideline
            self.warnings = warnings
            self.passed = passed
        }
    }

    /// Re-decodes an encoded audio file (AVAudioFile — the real container
    /// bytes, §8) into interleaved float PCM at the file's own processing
    /// format. Comparison against the reference requires matching sample
    /// rates; the check reports both measurements either way.
    public static func decode(fileAt url: URL) throws -> AudioGraphSourceAudio {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        guard channels > 0 else {
            throw NSError(
                domain: "MovieCutCore.AudioGraphExportPostCheck", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "unreadable channel count for \(url.lastPathComponent)"]
            )
        }
        var interleaved = [Float]()
        interleaved.reserveCapacity(Int(file.length) * channels)
        let chunkFrames: AVAudioFrameCount = 65_536
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { break }
            try file.read(into: buffer, frameCount: chunkFrames)
            guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { break }
            let frames = Int(buffer.frameLength)
            for frame in 0..<frames {
                for channel in 0..<channels {
                    interleaved.append(channelData[channel][frame])
                }
            }
        }
        return AudioGraphSourceAudio(
            sampleRate: format.sampleRate,
            channels: channels,
            interleaved: interleaved
        )
    }

    /// Plausible lossy-codec delay (priming) bound for the correlation
    /// search — Apple AAC priming is 2,112 samples; the bound leaves room
    /// for encoder variation.
    public static let maxCodecDelaySamples = 8_192

    /// §8.1's CALLER-SIDE TRIM (G-25 2C-3): measures the lossy codec's
    /// delay (priming) by correlating the re-decoded file against the exact
    /// PCM the encoder consumed, then drops the priming head AND the
    /// trailing padding so the result aligns 1:1 with the reference —
    /// `check(reference:decoded:)` then judges length at ±1 with real
    /// teeth. Coarse stride-64 sweep + stride-1 refinement on the
    /// mono-summed channels; a mono-summed dot product is exact for stereo
    /// pairs and robust for half-silent references (the overlap energy
    /// anchors the alignment).
    public static func trimCodecDelay(
        reference: AudioGraphSourceAudio,
        decoded: AudioGraphSourceAudio
    ) -> (trimmed: AudioGraphSourceAudio, codecDelaySamples: Int) {
        guard reference.frameCount > 0, decoded.frameCount > 0 else {
            return (decoded, 0)
        }
        let channels = min(reference.channels, decoded.channels, 2)
        func monoSum(_ audio: AudioGraphSourceAudio, frame: Int) -> Double {
            var sum = 0.0
            for channel in 0..<channels {
                sum += Double(audio.sample(frame: frame, channel: channel))
            }
            return sum
        }

        func correlation(at offset: Int) -> Double {
            let frames = min(reference.frameCount, decoded.frameCount - offset)
            guard frames > 0 else { return 0 }
            var score = 0.0
            var frame = 0
            while frame < frames {
                score += monoSum(reference, frame: frame) * monoSum(decoded, frame: frame + offset)
                frame += 1
            }
            return score
        }

        // Coarse sweep (stride 64) then stride-1 refinement.
        var bestOffset = 0
        var bestScore = -Double.infinity
        var offset = 0
        while offset <= min(maxCodecDelaySamples, decoded.frameCount) {
            let score = correlation(at: offset)
            if score > bestScore {
                bestScore = score
                bestOffset = offset
            }
            offset += 64
        }
        let fineStart = max(0, bestOffset - 64)
        let fineEnd = min(min(maxCodecDelaySamples, decoded.frameCount), bestOffset + 64)
        offset = fineStart
        while offset <= fineEnd {
            let score = correlation(at: offset)
            if score > bestScore {
                bestScore = score
                bestOffset = offset
            }
            offset += 1
        }

        // Drop the priming head and the trailing padding: exactly the
        // reference's frame count (or everything that remains).
        let available = decoded.frameCount - bestOffset
        let frames = min(reference.frameCount, max(available, 0))
        var interleaved = [Float]()
        interleaved.reserveCapacity(frames * decoded.channels)
        for frame in 0..<frames {
            for channel in 0..<decoded.channels {
                interleaved.append(decoded.sample(frame: bestOffset + frame, channel: channel))
            }
        }
        return (
            AudioGraphSourceAudio(
                sampleRate: decoded.sampleRate, channels: decoded.channels, interleaved: interleaved
            ),
            bestOffset
        )
    }

    /// §8.1-8.3 on one reference/decoded pair. `targetLoudnessLufs` comes
    /// from the graph's master bus (`AudioGraphMasterBus.targetLoudness`);
    /// nil means no target was declared and the loudness guideline is not
    /// evaluated.
    public static func check(
        reference: AudioGraphSourceAudio,
        decoded: AudioGraphSourceAudio,
        targetLoudnessLufs: Double? = nil
    ) -> Report {
        let referenceMeasurement = AudioGraphLoudness.measure(reference)
        let decodedMeasurement = AudioGraphLoudness.measure(decoded)
        let (clippingRuns, maxClippingRun) = AudioGraphLoudness.clippingRuns(in: decoded)

        let referenceFrames = reference.frameCount
        let decodedFrames = decoded.frameCount
        let lengthMatches = abs(decodedFrames - referenceFrames) <= 1

        // RMS difference over the compared overlap (channel-combined).
        let overlap = min(referenceFrames, decodedFrames) * min(reference.channels, decoded.channels)
        var referenceEnergy = 0.0
        var decodedEnergy = 0.0
        if overlap > 0 {
            let channels = min(reference.channels, decoded.channels)
            for frame in 0..<min(referenceFrames, decodedFrames) {
                for channel in 0..<channels {
                    let a = Double(reference.sample(frame: frame, channel: channel))
                    let b = Double(decoded.sample(frame: frame, channel: channel))
                    referenceEnergy += a * a
                    decodedEnergy += b * b
                }
            }
        }
        let referenceRms = sqrt(referenceEnergy / Double(overlap))
        let decodedRms = sqrt(decodedEnergy / Double(overlap))
        let rmsDifferenceDb: Double
        if referenceRms > 0, decodedRms > 0 {
            rmsDifferenceDb = 20 * log10(referenceRms / decodedRms)
        } else if referenceRms == 0, decodedRms == 0 {
            rmsDifferenceDb = 0
        } else {
            rmsDifferenceDb = .infinity
        }

        var warnings: [String] = []
        if !lengthMatches {
            warnings.append("length differs by \(abs(decodedFrames - referenceFrames)) samples (gate: ±1)")
        }
        if let target = targetLoudnessLufs, let decodedLufs = decodedMeasurement.integratedLufs {
            // §7 guideline band around the declared target: 1 LU above /
            // 2 LU below (EBU R128-style tolerance). Warn, never block.
            let within = decodedLufs <= target + 1 && decodedLufs >= target - 2
            if !within {
                warnings.append(
                    String(format: "integrated loudness %.1f LUFS is outside the %.1f LUFS target band (+1/−2 LU)", decodedLufs, target)
                )
            }
            let guidelineWithinBand = AudioGraphLoudness.snsGuidelineLufsRange.contains(decodedLufs)
            if !guidelineWithinBand {
                warnings.append(
                    String(
                        format: "integrated loudness %.1f LUFS is outside the SNS guideline band −16…−14 LUFS-I (§7)",
                        decodedLufs
                    )
                )
            }
        }
        if decodedMeasurement.truePeakDbTp > AudioGraphLoudness.snsGuidelineTruePeakDbTp {
            warnings.append(
                String(format: "true peak %.2f dBTP exceeds the −1 dBTP guideline (§7)", decodedMeasurement.truePeakDbTp)
            )
        }
        if clippingRuns > 0 {
            warnings.append("clipping: \(clippingRuns) run(s) of consecutive full-scale samples, longest \(maxClippingRun) samples")
        }

        let withinLoudnessGuideline: Bool?
        if let decodedLufs = decodedMeasurement.integratedLufs {
            withinLoudnessGuideline = AudioGraphLoudness.snsGuidelineLufsRange.contains(decodedLufs)
        } else {
            withinLoudnessGuideline = nil
        }

        return Report(
            referenceFrames: referenceFrames,
            decodedFrames: decodedFrames,
            lengthWithinOneSample: lengthMatches,
            rmsDifferenceDb: rmsDifferenceDb,
            referenceMeasurement: referenceMeasurement,
            decodedMeasurement: decodedMeasurement,
            clippingRunCount: clippingRuns,
            maxClippingRunLength: maxClippingRun,
            withinLoudnessGuideline: withinLoudnessGuideline,
            warnings: warnings,
            passed: lengthMatches
        )
    }
}
