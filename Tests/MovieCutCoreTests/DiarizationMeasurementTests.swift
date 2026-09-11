import Accelerate
import AVFoundation
import Foundation
import Testing

@testable import MovieCutCore

/// CA-18 measurement step (backlog §0.5.1 — measurement approved
/// 2026-08-23): on-device speaker DIARIZATION for 2-person subtitle
/// workflows, evaluated as a gate. The candidate under test is a compact
/// fully-offline pipeline implemented HERE (research code — nothing lands
/// in product sources unless the thresholds pass AND the user approves
/// UI work): energy VAD → per-segment averaged log-spectra → deterministic
/// 2-means → confusion against ground truth.
///
/// Pre-registered thresholds (from the backlog row — fixed before any
/// measurement run):
///   T1 speaker-confusion ≤ 10% of speech duration, per fixture
///   T2 RTF ≤ 0.5 (wall / audio duration)
/// "실녹음" (real human recording) is SUBSTITUTED by a noise-perturbed TTS
/// variant (≈12dB SNR pink noise) — real-human capture needs the user;
/// the substitution is part of the report, not a silent pass.
@Suite("CA-18 diarization measurement")
struct DiarizationMeasurementTests {
    struct SegmentSpec: Decodable {
        var start: Double
        var end: Double
        var speaker: Int
    }

    struct FixtureSpec: Decodable {
        var file: String
        var class_: String?
        var segments: [SegmentSpec]

        enum CodingKeys: String, CodingKey {
            case file
            case class_ = "class"
            case segments
        }
    }

    // MARK: - audio loading

    private static func loadMonoPCM(_ url: URL) throws -> (samples: [Float], rate: Double) {
        let file = try AVAudioFile(forReading: url)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: file.processingFormat.sampleRate,
                                         channels: 1,
                                         interleaved: false) else {
            throw NSError(domain: "ca18", code: 1)
        }
        let capacity = AVAudioFrameCount(240_000)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw NSError(domain: "ca18", code: 2)
        }
        var samples: [Float] = []
        // Request only the REMAINING frames each pass: an EOF-overshooting
        // read throws on this SDK (probed: nilError on the read past the
        // end) instead of returning a zero-length buffer.
        while samples.count < file.length {
            let remaining = AVAudioFrameCount(file.length - AVAudioFramePosition(samples.count))
            try file.read(into: buffer, frameCount: min(remaining, capacity))
            let n = Int(buffer.frameLength)
            guard n > 0 else { break }
            let ptr = buffer.floatChannelData![0]
            samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: n))
        }
        return (samples, file.processingFormat.sampleRate)
    }

    // MARK: - candidate pipeline

    private struct Detected {
        var start: Double
        var end: Double
        var feature: [Float]
    }

    private static func detectSegments(samples: [Float], rate: Double) -> [Detected] {
        let frame = Int(0.025 * rate)
        let hop = Int(0.025 * rate)
        var rms: [Float] = []
        var centers: [Double] = []
        var offset = 0
        while offset + frame <= samples.count {
            var sq = Float(0)
            for i in offset..<(offset + frame) {
                sq += samples[i] * samples[i]
            }
            rms.append(sqrt(sq / Float(frame)))
            centers.append((Double(offset) + Double(frame) / 2) / rate)
            offset += hop
        }
        guard !rms.isEmpty else { return [] }
        let sorted = rms.sorted()
        // Speech threshold relative to the file's OWN loud percentile: TTS
        // "silence" carries enough level that a low-percentile anchor merged
        // every utterance into ONE segment (measured: segments_detected=1
        // on a 12-utterance fixture — a meaningless confusion of 0). ~8% of
        // the p95 loudness (-22dB) separates the gap floor from speech.
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let threshold = p95 * 0.08

        // Merge speech frames into segments; gaps ≤ 0.25s stay in one segment.
        var segments: [(start: Double, end: Double)] = []
        var inSegment = false
        var segStart = 0.0
        var lastSpeech = 0.0
        for (i, energy) in rms.enumerated() {
            if energy >= threshold {
                if !inSegment {
                    inSegment = true
                    segStart = max(0, centers[i] - 0.0125)
                }
                lastSpeech = centers[i]
            } else if inSegment, centers[i] - lastSpeech > 0.25 {
                segments.append((segStart, lastSpeech + 0.0125))
                inSegment = false
            }
        }
        if inSegment { segments.append((segStart, lastSpeech + 0.0125)) }
        return segments.filter { $0.end - $0.start >= 0.25 }.map { seg in
            Detected(start: seg.start, end: seg.end, feature: feature(for: seg, samples: samples, rate: rate))
        }
    }

    /// Mean log-magnitude spectrum over up to 8 frames inside the segment
    /// (512-point FFT, lower 64 bins — the voice band at 44.1kHz).
    private static func feature(for seg: (start: Double, end: Double), samples: [Float], rate: Double) -> [Float] {
        let n = 512
        let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Double(n))), FFTRadix(kFFTRadix2))!
        defer { vDSP_destroy_fftsetup(fftSetup) }
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        let segSamples = samples[max(0, Int(seg.start * rate))..<min(samples.count, Int(seg.end * rate))]
        guard !segSamples.isEmpty else { return [Float](repeating: 0, count: 64) }
        let frameCount = min(8, max(1, segSamples.count / n))
        var mean = [Float](repeating: 0, count: 64)
        for f in 0..<frameCount {
            let startIdx = segSamples.startIndex + (segSamples.count - n) * f / max(1, frameCount)
            guard startIdx + n <= segSamples.endIndex else { continue }
            var frameBuf = [Float](repeating: 0, count: n)
            vDSP_vmul(Array(segSamples[startIdx..<(startIdx + n)]), 1, window, 1, &frameBuf, 1, vDSP_Length(n))
            var real = [Float](repeating: 0, count: n / 2)
            var imag = [Float](repeating: 0, count: n / 2)
            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    frameBuf.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, vDSP_Length(log2(Double(n))), FFTDirection(FFT_FORWARD))
                    var mags = [Float](repeating: 0, count: n / 2)
                    vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(n / 2))
                    var logMags = [Float](repeating: 0, count: 64)
                    for b in 0..<64 {
                        logMags[b] = 20 * log10(max(mags[b], 1e-9))
                        mean[b] += logMags[b]
                    }
                }
            }
        }
        for k in 0..<64 { mean[k] /= Float(frameCount) }
        return mean
    }

    /// Deterministic 2-means: init with the maximally distant pair, then
    /// iterate to a fixed point (≤20 rounds).
    private static func twoMeans(_ features: [[Float]]) -> (labels: [Int], changed: Bool) {
        guard features.count >= 2 else { return ([0], false) }
        var bestPair = (0, 1)
        var bestDist = -1.0
        for i in 0..<features.count {
            for j in (i + 1)..<features.count {
                var d = Float(0)
                for k in 0..<64 { let diff = features[i][k] - features[j][k]; d += diff * diff }
                if Double(d) > bestDist {
                    bestDist = Double(d)
                    bestPair = (i, j)
                }
            }
        }
        var centroidA = features[bestPair.0]
        var centroidB = features[bestPair.1]
        var labels = [Int](repeating: 0, count: features.count)
        for _ in 0..<20 {
            var newLabels = [Int](repeating: 0, count: features.count)
            for (i, f) in features.enumerated() {
                var da = Float(0), db = Float(0)
                for k in 0..<64 {
                    da += (f[k] - centroidA[k]) * (f[k] - centroidA[k])
                    db += (f[k] - centroidB[k]) * (f[k] - centroidB[k])
                }
                newLabels[i] = da <= db ? 0 : 1
            }
            var nextA = [Float](repeating: 0, count: 64)
            var nextB = [Float](repeating: 0, count: 64)
            var countA = 0, countB = 0
            for (i, f) in features.enumerated() where newLabels[i] == 0 {
                for k in 0..<64 { nextA[k] += f[k] }
                countA += 1
            }
            for (i, f) in features.enumerated() where newLabels[i] == 1 {
                for k in 0..<64 { nextB[k] += f[k] }
                countB += 1
            }
            guard countA > 0, countB > 0 else { return (labels, false) }
            for k in 0..<64 {
                nextA[k] /= Float(countA)
                nextB[k] /= Float(countB)
            }
            if newLabels == labels {
                labels = newLabels
                break
            }
            labels = newLabels
            centroidA = nextA
            centroidB = nextB
        }
        return (labels, true)
    }

    private func loadManifest() throws -> [FixtureSpec] {
        guard let path = ProcessInfo.processInfo.environment["CA18_MANIFEST"] else { return [] }
        return try JSONDecoder().decode([FixtureSpec].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    @Test("measures diarization confusion + RTF against pre-registered thresholds",
          .enabled(if: ProcessInfo.processInfo.environment["CA18_MANIFEST"] != nil))
    func measure() async throws {
        let fixtures = try loadManifest()
        guard !fixtures.isEmpty else {
            Issue.record("CA18_MANIFEST set but empty/undecodable")
            return
        }

        var failures: [String] = []
        for spec in fixtures {
            let (samples, rate) = try Self.loadMonoPCM(URL(fileURLWithPath: spec.file))
            let duration = Double(samples.count) / rate

            let clock = ContinuousClock()
            let start = clock.now
            let detected = Self.detectSegments(samples: samples, rate: rate)
            let clustered = Self.twoMeans(detected.map(\.feature))
            let elapsed = {
                let c = start.duration(to: clock.now).components
                return Double(c.seconds) + Double(c.attoseconds) / 1e18
            }()
            let rtf = elapsed / max(duration, 0.001)

            // Assign each detected segment its majority ground-truth speaker,
            // choose the cluster→speaker permutation minimizing mislabeled
            // speech duration, report confusion as mislabeled/speech share.
            let speech = spec.segments.reduce(0.0) { $0 + ($1.end - $1.start) }
            func confusion(_ map: [Int: Int]) -> Double {
                var wrong = 0.0
                for d in detected {
                    var votes = [0.0, 0.0]
                    for gt in spec.segments where gt.start < d.end && gt.end > d.start {
                        let overlap = min(d.end, gt.end) - max(d.start, gt.start)
                        votes[gt.speaker] += overlap
                    }
                    if let assigned = votes.indices.max(by: { votes[$0] < votes[$1] }),
                       let clusterLabel = detected.firstIndex(where: { $0.start == d.start && $0.end == d.end })
                        .map({ clustered.labels[$0] }),
                       map[clusterLabel] != assigned {
                        wrong += votes[assigned]
                    }
                }
                return speech > 0 ? wrong / speech : 1
            }
            let direct = confusion([0: 0, 1: 1])
            let swapped = confusion([0: 1, 1: 0])
            let conf = min(direct, swapped)
            let tag = spec.class_ ?? "unknown"

            print(String(format: "CA18MEASURE class=%@ file=%@ segments_detected=%d confusion=%.3f rtf=%.3f",
                         tag, (spec.file as NSString).lastPathComponent, detected.count, conf, rtf))
            if detected.isEmpty {
                // Degeneracy tripwire: with zero detected segments confusion()
                // iterates nothing and scores 0 — the same false-PASS class as
                // the merged-segment defect (2026-09-05). An empty detection is
                // a broken measurement, not a good score.
                failures.append("T1 \(tag) degeneracy: 0 segments detected — confusion undefined, forced FAIL")
            } else if conf > 0.10 {
                failures.append(String(format: "T1 %@ confusion %.1f%% > 10%%", tag, conf * 100))
            }
            if rtf > 0.5 {
                failures.append(String(format: "T2 %@ RTF %.3f > 0.5", tag, rtf))
            }
        }

        if failures.isEmpty {
            print("CA18 VERDICT: PASS — pre-registered thresholds met (synthetic + perturbed fixtures)")
        } else {
            print("CA18 VERDICT: FAIL — \(failures.joined(separator: "; "))")
            Issue.record("CA-18 thresholds not met: \(failures.joined(separator: "; "))")
        }
        #expect(failures.isEmpty)
    }
}
