import Foundation

/// G-25 Inc 9 (Core half) — the §7 meter math: ITU-R BS.1770-4 integrated
/// loudness (K-weighting + gated 400 ms blocks) and true peak (4×
/// oversampled). PURE and streaming: same input → same numbers on every
/// host, O(1) memory beyond small ring buffers, so the meter UI, the §8 AAC
/// post-check, and the E2E gate all read ONE implementation.
///
/// Stage-1 scope: stereo (or mono) sources — channel weight 1.0 for the
/// first two channels (BS.1770 weights surround channels differently; the
/// audio graph's bus output is stereo, §1).
public enum AudioGraphLoudness {
    /// Digital-silence floor for the peak fields; a fully silent signal
    /// reports −120 dB, never −infinity (JSON/log friendly).
    public static let silenceFloorDb = -120.0

    /// §7 SNS guideline band (internal guideline, never auto-enforced):
    /// master −16…−14 LUFS-I, true peak ≤ −1 dBTP.
    public static let snsGuidelineLufsRange = -16.0 ... -14.0
    public static let snsGuidelineTruePeakDbTp = -1.0

    public struct Measurement: Sendable, Equatable {
        /// Integrated loudness in LUFS. nil when the signal never rises
        /// above the −70 LUFS absolute gate (silence / too short to fill
        /// one 400 ms block) — a silence has no loudness to display.
        public var integratedLufs: Double?
        /// Maximum over-sampled amplitude as dBTP (4× polyphase).
        public var truePeakDbTp: Double
        /// Maximum sample amplitude as dBFS (the pre-oversampling peak).
        public var samplePeakDbFs: Double

        public init(
            integratedLufs: Double?,
            truePeakDbTp: Double,
            samplePeakDbFs: Double
        ) {
            self.integratedLufs = integratedLufs
            self.truePeakDbTp = truePeakDbTp
            self.samplePeakDbFs = samplePeakDbFs
        }
    }

    public static func measure(_ audio: AudioGraphSourceAudio) -> Measurement {
        var analyzer = Analyzer(sampleRate: audio.sampleRate, channels: audio.channels)
        let channels = max(1, min(2, audio.channels))
        for frame in 0..<audio.frameCount {
            var frameSamples = [Double](repeating: 0, count: channels)
            for channel in 0..<channels {
                frameSamples[channel] = Double(audio.sample(frame: frame, channel: channel))
            }
            analyzer.push(frameSamples)
        }
        return analyzer.finish()
    }

    /// Clipping per §8.3: a run of ≥2 consecutive samples at digital full
    /// scale (|x| ≥ 1 − 1/32768; a single full-scale sample is normal).
    /// AAC encoders clip-guard, so runs here mean real master clipping.
    public static func clippingRuns(
        in audio: AudioGraphSourceAudio
    ) -> (runCount: Int, maxRunLength: Int) {
        let threshold: Float = 1.0 - 1.0 / 32_768.0
        var runCount = 0
        var maxRun = 0
        var currentRun = 0
        for frame in 0..<audio.frameCount {
            let isFullScale = (0..<audio.channels).contains { channel in
                abs(audio.sample(frame: frame, channel: channel)) >= threshold
            }
            if isFullScale {
                currentRun += 1
            } else {
                if currentRun >= 2 { runCount += 1 }
                maxRun = max(maxRun, currentRun)
                currentRun = 0
            }
        }
        if currentRun >= 2 { runCount += 1 }
        maxRun = max(maxRun, currentRun)
        return (runCount, maxRun)
    }

    // MARK: - Streaming analyzer

    /// K-weighting (BS.1770-4 §5.1.2): a high-shelf +4 dB stage followed by
    /// a ~38 Hz high-pass, both derived from the ITU analog prototypes for
    /// ANY sample rate (the coefficient construction below reproduces the
    /// ITU's published 48 kHz coefficients exactly).
    struct Biquad {
        var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        var z1 = 0.0
        var z2 = 0.0

        init(shelfWithGainDb gainDb: Double, cornerHz: Double, q: Double, sampleRate: Double) {
            let k = tan(.pi * cornerHz / sampleRate)
            let vh = pow(10, gainDb / 20)
            let vb = pow(vh, 0.4996667741545416)
            let denominator = 1 + k / q + k * k
            b0 = (vh + vb * k / q + k * k) / denominator
            b1 = 2 * (k * k - vh) / denominator
            b2 = (vh - vb * k / q + k * k) / denominator
            a1 = 2 * (k * k - 1) / denominator
            a2 = (1 - k / q + k * k) / denominator
        }

        init(highPassAt cornerHz: Double, q: Double, sampleRate: Double) {
            let k = tan(.pi * cornerHz / sampleRate)
            let denominator = 1 + k / q + k * k
            b0 = 1
            b1 = -2
            b2 = 1
            a1 = 2 * (k * k - 1) / denominator
            a2 = (1 - k / q + k * k) / denominator
        }

        mutating func process(_ input: Double) -> Double {
            let output = b0 * input + z1
            z1 = b1 * input - a1 * output + z2
            z2 = b2 * input - a2 * output
            return output
        }
    }

    /// 4× oversampling polyphase for true peak: windowed-sinc fractional
    /// delay interpolation. y(n + p/4) = Σₖ w·sinc(k + p/4)·x[n−k] with k
    /// spanning BOTH sides (±halfWidth/4) — a symmetric interpolator, with
    /// the streaming output delayed by `halfWidth / 4` samples so only
    /// already-pushed samples are needed. Each phase is normalized to
    /// exactly unity DC gain so the meter never invents headroom; the
    /// symmetric windowed design keeps every phase flat well inside the
    /// tolerance BS.1770 allows for 4× true-peak meters.
    struct Oversampler {
        static let halfWidth = 48
        /// Taps per phase: k ∈ [−K, K].
        static let halfTaps = halfWidth / 4
        static let tapsPerPhase = 2 * halfTaps + 1
        static let historyLength = tapsPerPhase

        let phaseCoefficients: [[Double]]
        private var history: [Double]
        private var historyIndex = 0
        private var framesSeen = 0

        init() {
            func prototype(_ j: Int) -> Double {
                let t = Double(j) / 4
                let sinc = t == 0 ? 1.0 : sin(.pi * t) / (.pi * t)
                let position = Double(j + Self.halfWidth) / Double(2 * Self.halfWidth)
                let blackman = 0.42 - 0.5 * cos(2 * .pi * position) + 0.08 * cos(4 * .pi * position)
                return sinc * blackman
            }
            // Phase p interpolates at τ = m + p/4 using x[m−k], k ∈ [−K, K],
            // with coefficient w·sinc(k + p/4) — prototype index 4k + p.
            phaseCoefficients = (0..<4).map { phase in
                let raw = (-Self.halfTaps...Self.halfTaps).map { k in prototype(4 * k + phase) }
                let dcGain = raw.reduce(0, +)
                return raw.map { $0 / dcGain }
            }
            history = [Double](repeating: 0, count: Self.historyLength)
        }

        mutating func push(_ input: Double) -> [Double] {
            // Prime the history with the first sample: a zero-filled
            // history turns the signal start into a step edge whose
            // ringing reads as +1 dB of phantom true peak (worst on DC).
            // Priming models "the signal already existed before the meter".
            if framesSeen == 0 {
                for index in 0..<Self.historyLength { history[index] = input }
            }
            history[historyIndex] = input
            historyIndex = (historyIndex + 1) % Self.historyLength
            framesSeen += 1
            // Emit the four interpolated samples around x[n − K] (a fixed
            // K-sample output delay — the peak maximum is unaffected).
            let newest = (historyIndex - 1 + Self.historyLength) % Self.historyLength
            var outputs = [Double](repeating: 0, count: 4)
            for phase in 0..<4 {
                var accumulator = 0.0
                for k in -Self.halfTaps...Self.halfTaps {
                    // x[n − K − k]: sample age K + k, newest read at k = −K.
                    let age = Self.halfTaps + k
                    let index = ((newest - age) % Self.historyLength + Self.historyLength) % Self.historyLength
                    accumulator += phaseCoefficients[phase][k + Self.halfTaps] * history[index]
                }
                outputs[phase] = accumulator
            }
            return outputs
        }
    }

    /// Streaming analyzer: biquad states, one 400 ms sliding energy window
    /// per channel (blocks step 100 ms per BS.1770-4), and the oversampler
    /// peak. Constant memory for any signal length.
    struct Analyzer {
        private var shelfFilters: [Biquad]
        private var highPassFilters: [Biquad]
        private var oversamplers: [Oversampler]
        private let blockLength: Int
        private let blockStep: Int
        private let channels: Int

        private var energyRings: [[Double]]
        private var energyIndices: [Int]
        private var runningSums: [Double]
        private var framesSeen = 0
        private var blockPowers: [Double] = []
        private var truePeak: Double = 0
        private var samplePeak: Double = 0

        init(sampleRate: Double, channels: Int = 2) {
            let channelCount = max(1, min(2, channels))
            self.channels = channelCount
            shelfFilters = (0..<channelCount).map { _ in
                Biquad(shelfWithGainDb: 3.999843853973347, cornerHz: 1_681.974450955533, q: 0.7071752369554196, sampleRate: sampleRate)
            }
            highPassFilters = (0..<channelCount).map { _ in
                Biquad(highPassAt: 38.13547087602444, q: 0.5003270373238773, sampleRate: sampleRate)
            }
            oversamplers = (0..<channelCount).map { _ in Oversampler() }
            let length = max(1, Int(0.4 * sampleRate))
            blockLength = length
            blockStep = max(1, Int(0.1 * sampleRate))
            energyRings = (0..<channelCount).map { _ in [Double](repeating: 0, count: length) }
            energyIndices = [Int](repeating: 0, count: channelCount)
            runningSums = [Double](repeating: 0, count: channelCount)
        }

        mutating func push(_ frame: [Double]) {
            var weightedSum = 0.0
            for channel in 0..<channels {
                let input = channel < frame.count ? frame[channel] : 0
                var filtered = shelfFilters[channel].process(input)
                filtered = highPassFilters[channel].process(filtered)
                weightedSum += filtered * filtered

                samplePeak = max(samplePeak, abs(input))
                for oversampled in oversamplers[channel].push(input) {
                    truePeak = max(truePeak, abs(oversampled))
                }

                // Sliding 400 ms energy: add the new sample, drop the one
                // leaving the window.
                let ring = channel
                let outgoing = energyRings[ring][energyIndices[ring]]
                runningSums[ring] += filtered * filtered - outgoing
                energyRings[ring][energyIndices[ring]] = filtered * filtered
                energyIndices[ring] = (energyIndices[ring] + 1) % blockLength
            }

            framesSeen += 1
            // A block completes every `blockStep` frames once the window
            // is full (BS.1770-4: 400 ms blocks, 75% overlap).
            if framesSeen >= blockLength, (framesSeen - blockLength) % blockStep == 0 {
                var z = 0.0
                for channel in 0..<channels {
                    z += runningSums[channel] / Double(blockLength)
                }
                blockPowers.append(z)
            }
        }

        func finish() -> Measurement {
            Measurement(
                integratedLufs: integratedLoudness(from: blockPowers, framesSeen: framesSeen, blockLength: blockLength),
                truePeakDbTp: truePeak > 0 ? 20 * log10(truePeak) : AudioGraphLoudness.silenceFloorDb,
                samplePeakDbFs: samplePeak > 0 ? 20 * log10(samplePeak) : AudioGraphLoudness.silenceFloorDb
            )
        }

        private func integratedLoudness(from powers: [Double], framesSeen: Int, blockLength: Int) -> Double? {
            guard framesSeen >= blockLength, !powers.isEmpty else { return nil }
            let loudness = powers.map { -0.691 + 10 * log10(max($0, 1e-30)) }
            // Absolute gate (−70 LUFS), then the relative gate (mean of the
            // surviving blocks − 10 LU).
            let absoluteKept = zip(powers, loudness).filter { $0.1 > -70 }
            guard !absoluteKept.isEmpty else { return nil }
            let keptMean = absoluteKept.map(\.0).reduce(0, +) / Double(absoluteKept.count)
            let relativeThreshold = -0.691 + 10 * log10(max(keptMean, 1e-30)) - 10
            let finalKept = zip(powers, loudness).filter { $0.1 > -70 && $0.1 > relativeThreshold }
            guard !finalKept.isEmpty else { return nil }
            let finalMean = finalKept.map(\.0).reduce(0, +) / Double(finalKept.count)
            return -0.691 + 10 * log10(max(finalMean, 1e-30))
        }
    }
}
