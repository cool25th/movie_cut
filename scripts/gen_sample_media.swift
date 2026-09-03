// Generates the bundled CA-25 sample media: a ~12s vertical (720×1280, 30fps)
// H.264 clip with real `say` narration on an AAC track, so the sample project
// supports the onboarding flow's subtitle step (real speech → auto-transcribe)
// and the export step, entirely offline.
//
// Usage:
//   swift scripts/gen_sample_media.swift /tmp/sample_media.mov
//
// Standalone by design (AVFoundation + CoreMedia only — no MovieCutCore
// dependency) so it can run as a plain interpreted script. The companion
// Mac test `SampleProjectTemplateTests` packages this media into the bundled
// `.mctemplate`.

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: gen_sample_media.swift <output.mov>\n", stderr)
    exit(2)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

let width = 720, height = 1280, fps = 30, seconds = 12
let frameCount = fps * seconds

// Narration via `say` (offline system TTS) → AIFF.
let aiffURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("sample-narration-\(UUID().uuidString).aiff")
let text = "Welcome to MovieCut. Import a clip, add automatic subtitles, and export a vertical short. This sample narration gives the speech recognizer something to transcribe."
let say = Process()
say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
say.arguments = ["-o", aiffURL.path, text]
try say.run()
say.waitUntilExit()
guard say.terminationStatus == 0 else {
    fputs("say failed (\(say.terminationStatus))\n", stderr)
    exit(3)
}

try? FileManager.default.removeItem(at: outputURL)
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
]
let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
videoInput.expectsMediaDataInRealTime = false
writer.add(videoInput)

// Narration reader → AAC encoder. The AAC rate must match the source PCM so
// the writer's resampler isn't engaged.
// `say` emits big-endian int16 AIFF; the AAC encoder rejects those native
// sample buffers ("Cannot Encode Media"). Normalize to LE float32 44.1kHz
// mono CAF first — the reader then hands the encoder a format it accepts.
let cafURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("sample-narration-\(UUID().uuidString).caf")
let afconvert = Process()
afconvert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
afconvert.arguments = ["-f", "caff", "-d", "LEF32@44100", "-c", "1", aiffURL.path, cafURL.path]
try afconvert.run()
afconvert.waitUntilExit()
guard afconvert.terminationStatus == 0 else {
    fputs("afconvert failed (\(afconvert.terminationStatus))\n", stderr)
    exit(9)
}
let speechAsset = AVURLAsset(url: cafURL)
let reader = try AVAssetReader(asset: speechAsset)
guard let speechTrack = speechAsset.tracks(withMediaType: .audio).first else {
    fputs("narration has no audio track\n", stderr)
    exit(3)
}
// Narration sample rate via AVAudioFile — stable across SDKs (the
// CMFormatDescription bridge is not visible to Swift here).
let audioRate = (try? AVAudioFile(forReading: cafURL))?.fileFormat.sampleRate ?? 44_100
let audioSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: audioRate,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 96_000,
]
let skipAudio = ProcessInfo.processInfo.environment["SAMPLE_SKIP_AUDIO"] == "1"
let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
audioInput.expectsMediaDataInRealTime = false
if !skipAudio { writer.add(audioInput) }

let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])

// Plain gradient slides — deterministic, no external art. Each of the three
// onboarding steps has ONE static image; per-frame work is a memcpy (a
// naive per-pixel loop made generation take minutes).
let bytesPerRow = width * 4
func renderSlide(_ slide: Int) -> [UInt8] {
    var image = [UInt8](repeating: 0, count: bytesPerRow * height)
    for y in 0..<height {
        let t = Double(y) / Double(height)
        let (r, g, b): (UInt8, UInt8, UInt8) = {
            switch slide {
            case 0: return (UInt8(18 + 30 * t), UInt8(24 + 40 * t), UInt8(38 + 60 * t))
            case 1: return (UInt8(38 - 20 * t), UInt8(24 + 20 * t), UInt8(50 + 40 * t))
            default: return (UInt8(20 + 25 * t), UInt8(45 - 15 * t), UInt8(42 + 30 * t))
            }
        }()
        let rowStart = y * bytesPerRow
        for x in 0..<width {
            let o = rowStart + x * 4
            image[o + 0] = b // BGRA — VideoToolbox H.264 rejects 32ARGB here
            image[o + 1] = g
            image[o + 2] = r
            image[o + 3] = 255
        }
    }
    return image
}
let slides = [renderSlide(0), renderSlide(1), renderSlide(2)]
func blit(_ slideIndex: Int, into buffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
    let dst = base.assumingMemoryBound(to: UInt8.self)
    let image = slides[slideIndex]
    let bufferRow = CVPixelBufferGetBytesPerRow(buffer)
    image.withUnsafeBufferPointer { src in
        let base = src.baseAddress!
        for y in 0..<height {
            memcpy(dst + y * bufferRow, base + y * bytesPerRow, bytesPerRow)
        }
    }
}

writer.startWriting()
writer.startSession(atSourceTime: .zero)

let readerOutput = AVAssetReaderTrackOutput(track: speechTrack, outputSettings: nil)
reader.add(readerOutput)
reader.startReading()

let audioQueue = DispatchQueue(label: "sample-audio")
let audioDone = DispatchSemaphore(value: skipAudio ? 1 : 0)  // pre-signaled when skipped
var audioAppended = false
if !skipAudio { audioInput.requestMediaDataWhenReady(on: audioQueue) {
    while audioInput.isReadyForMoreMediaData {
        guard let sample = readerOutput.copyNextSampleBuffer() else {
            audioInput.markAsFinished()
            audioDone.signal()
            return
        }
        if audioInput.append(sample) { audioAppended = true }
    }
} }
let pool = adaptor.pixelBufferPool!
for frame in 0..<frameCount {
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
    guard let pixelBuffer = pb else { fatalError("pixel buffer pool exhausted") }
    blit(Int((Double(frame) / Double(frameCount)) * 3), into: pixelBuffer)
    var spins = 0
    while !videoInput.isReadyForMoreMediaData {
        if writer.status != .writing {
            fputs("writer stopped during video: \(String(describing: writer.error))\n", stderr)
            exit(6)
        }
        usleep(2_000)
        spins += 1
        if spins > 5_000 {
            fputs("video input never became ready (status=\(writer.status.rawValue))\n", stderr)
            exit(7)
        }
    }
    let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
    if !adaptor.append(pixelBuffer, withPresentationTime: time) {
        fputs("video append failed at frame \(frame): \(String(describing: writer.error))\n", stderr)
        exit(8)
    }
}
videoInput.markAsFinished()

audioDone.wait()
if reader.status != .completed {
    fputs("narration reader ended: \(reader.status.rawValue) \(String(describing: reader.error))\n", stderr)
}
if !audioAppended {
    fputs("no audio samples were appended\n", stderr)
}

guard writer.status == .writing else {
    FileHandle.standardError.write("writer ended early: \(String(describing: writer.error))\n".data(using: .utf8)!)
    exit(4)
}
// finishWriting() is completion-based in this SDK (the sync polling form is
// unavailable to Swift here) — bridge via semaphore.
let finishDone = DispatchSemaphore(value: 0)
writer.finishWriting {
    finishDone.signal()
}
finishDone.wait()
guard writer.status == .completed else {
    fputs("writer failed: \(String(describing: writer.error))\n", stderr)
    exit(5)
}
try? FileManager.default.removeItem(at: aiffURL)
try? FileManager.default.removeItem(at: cafURL)
let size = (try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
print("sample media written: \(outputURL.path) (\(size / 1024) KB, \(seconds)s \(width)x\(height)@\(fps), audio=\(audioAppended))")
