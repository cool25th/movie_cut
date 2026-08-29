import AVFoundation
import CoreVideo
import AppKit

func makePixel(size: CGSize, hue: CGFloat) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &pb)
    guard let buffer = pb else { fatalError("no buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let color = NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).usingColorSpace(.deviceRGB)!
    ctx.setFillColor(color.cgColor)
    ctx.fill(CGRect(origin: .zero, size: size))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
}

/// BUG-07 orientation probe: left half red, right half blue. Under the 90°
/// display matrix the split becomes top/bottom in the upright view, so an
/// export's quadrant colors reveal whether preferredTransform was applied —
/// a solid-color fixture cannot distinguish upright from sideways.
func makeAsymPixel(size: CGSize) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &pb)
    guard let buffer = pb else { fatalError("no buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.setFillColor(NSColor(calibratedRed: 0.9, green: 0.05, blue: 0.05, alpha: 1).usingColorSpace(.deviceRGB)!.cgColor)
    ctx.fill(CGRect(origin: .zero, size: CGSize(width: size.width / 2, height: size.height)))
    ctx.setFillColor(NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.9, alpha: 1).usingColorSpace(.deviceRGB)!.cgColor)
    ctx.fill(CGRect(origin: CGPoint(x: size.width / 2, y: 0), size: CGSize(width: size.width / 2, height: size.height)))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
}

func write(url: URL, size: CGSize, count: Int, transform: CGAffineTransform?, durations: [Double], asym: Bool = false) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    if let transform { input.transform = transform }
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    var time = Double(0)
    for i in 0..<count {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
        let buffer = asym ? makeAsymPixel(size: size) : makePixel(size: size, hue: CGFloat(i % count) / CGFloat(count))
        adaptor.append(buffer, withPresentationTime: CMTime(seconds: time, preferredTimescale: 600))
        time += durations[i % durations.count]
    }
    input.markAsFinished()
    let sem = DispatchSemaphore(value: 0)
    writer.finishWriting { sem.signal() }
    sem.wait()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "gen", code: 1) }
    print("wrote \(url.lastPathComponent): \(count) frames, \(time)s\(transform != nil ? " +rot90" : "")\(asym ? " asym" : "")")
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
// Rotated: display-matrix 90° (what an iPhone produces).
let rot = CGAffineTransform(translationX: 240, y: 0).rotated(by: CGFloat.pi / 2)
try write(url: dir.appendingPathComponent("ca04_rotated_320x240_2s_90deg.mp4"), size: CGSize(width: 320, height: 240),
          count: 60, transform: rot, durations: [1.0 / 30])
// BUG-07: same 90° metadata, asymmetric content — orientation measurable.
try write(url: dir.appendingPathComponent("ca04_rotated_asym_320x240_2s_90deg.mp4"), size: CGSize(width: 320, height: 240),
          count: 60, transform: rot, durations: [1.0 / 30], asym: true)
// VFR: alternating 1/30 and 1/15 durations — deterministic.
try write(url: dir.appendingPathComponent("ca04_vfr_320x240_5s.mp4"), size: CGSize(width: 320, height: 240),
          count: 100, transform: nil, durations: [1.0 / 30, 1.0 / 15])
