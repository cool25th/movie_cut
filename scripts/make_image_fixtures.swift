// Generates the image fixtures ffmpeg cannot write (G-15 AC5):
//   - swatch_green_64x64.heic      solid-color HEIC for format coverage
//   - exif_orient6_asym_320x240.jpg left-red/right-blue JPEG carrying EXIF
//                                  orientation 6 (Rotate 90 CW) — a correct
//                                  renderer must display it UPRIGHT with red
//                                  on top, the same semantics as the
//                                  ca04_rotated_asym +90° video fixture.
//
// Usage: swift scripts/make_image_fixtures.swift [output-dir]
// Called from scripts/make_fixtures.sh (guarded so committed bytes do not
// churn on re-runs).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct FixtureError: Error, CustomStringConvertible {
    let description: String
}

func makeContext(width: Int, height: Int) throws -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw FixtureError(description: "bitmap context create failed (\(width)x\(height))")
    }
    return ctx
}

/// Left half red, right half blue — the ca04_rotated_asym layout. Values
/// (230/20) survive JPEG compression with clear channel separation.
func asymmetricImage(width: Int, height: Int) throws -> CGImage {
    let ctx = try makeContext(width: width, height: height)
    ctx.setFillColor(red: 0.90, green: 0.08, blue: 0.08, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    ctx.setFillColor(red: 0.08, green: 0.08, blue: 0.90, alpha: 1)
    ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    guard let image = ctx.makeImage() else {
        throw FixtureError(description: "asymmetric makeImage failed")
    }
    return image
}

func solidColorImage(width: Int, height: Int, r: CGFloat, g: CGFloat, b: CGFloat) throws -> CGImage {
    let ctx = try makeContext(width: width, height: height)
    ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = ctx.makeImage() else {
        throw FixtureError(description: "solid makeImage failed")
    }
    return image
}

func write(_ image: CGImage, as type: UTType, to url: URL, properties: [CFString: Any] = [:]) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, type.identifier as CFString, 1, nil
    ) else {
        throw FixtureError(description: "destination create failed for \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw FixtureError(description: "finalize failed for \(url.lastPathComponent)")
    }
}

let outputDir = URL(
    fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/Fixtures"
)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let heic = try solidColorImage(width: 64, height: 64, r: 0.08, g: 0.85, b: 0.25)
try write(heic, as: .heic, to: outputDir.appendingPathComponent("swatch_green_64x64.heic"))

let asym = try asymmetricImage(width: 320, height: 240)
try write(
    asym,
    as: .jpeg,
    to: outputDir.appendingPathComponent("exif_orient6_asym_320x240.jpg"),
    properties: [
        // Orientation 6 = "0th row is the visual right side" → display rotates
        // 90° CW. The top-level orientation key is routed by ImageIO into the
        // format-appropriate dictionary (EXIF for JPEG); the TIFF copy is
        // belt-and-suspenders for third-party readers.
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6],
    ]
)

print("generated: swatch_green_64x64.heic, exif_orient6_asym_320x240.jpg")
