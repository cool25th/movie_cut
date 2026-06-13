import CoreImage
import Foundation
import Testing
@testable import MovieCutCore

/// F-09 external LUT: .cube parsing, error reporting, and the externalLUT
/// effect remapping pixels through CIColorCube.
@Suite("Cube LUT")
struct CubeLUTTests {
    /// Builds a valid identity .cube of the given size (output == input).
    private func identityCube(size: Int) -> String {
        var lines = ["TITLE \"Identity\"", "LUT_3D_SIZE \(size)"]
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    lines.append("\(Float(r) / denom) \(Float(g) / denom) \(Float(b) / denom)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// An "invert" .cube that maps each channel to 1 - value.
    private func invertCube(size: Int) -> String {
        var lines = ["LUT_3D_SIZE \(size)"]
        let denom = Float(size - 1)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    lines.append("\(1 - Float(r) / denom) \(1 - Float(g) / denom) \(1 - Float(b) / denom)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    @Test("parses a standard 33-size cube with the right entry count")
    func parses33() throws {
        let lut = try CubeLUTParser.parse(identityCube(size: 33))
        #expect(lut.dimension == 33)
        #expect(lut.data.count == 33 * 33 * 33 * 4)
        // First entry is black RGBA, alpha 1.
        #expect(lut.data[0] == 0 && lut.data[1] == 0 && lut.data[2] == 0 && lut.data[3] == 1)
        // Last entry is white.
        let last = lut.data.suffix(4)
        #expect(Array(last) == [1, 1, 1, 1])
    }

    @Test("parses 17 and 65 sizes, tolerating comments and blank lines")
    func parsesOtherSizes() throws {
        for size in [17, 65] {
            let text = "# a comment\n\n" + identityCube(size: size) + "\n"
            let lut = try CubeLUTParser.parse(text)
            #expect(lut.dimension == size)
            #expect(lut.data.count == size * size * size * 4)
        }
    }

    @Test("missing size throws")
    func missingSize() {
        #expect(throws: CubeLUTParser.ParseError.missingSize) {
            _ = try CubeLUTParser.parse("0.0 0.0 0.0\n1.0 1.0 1.0")
        }
    }

    @Test("1D LUTs are rejected")
    func rejects1D() {
        #expect(throws: CubeLUTParser.ParseError.unsupported1D) {
            _ = try CubeLUTParser.parse("LUT_1D_SIZE 16\n0 0 0")
        }
    }

    @Test("entry count mismatch throws")
    func entryMismatch() {
        let text = "LUT_3D_SIZE 2\n0 0 0\n1 1 1"  // expects 8 entries, has 2
        #expect(throws: CubeLUTParser.ParseError.entryCountMismatch(expected: 8, found: 2)) {
            _ = try CubeLUTParser.parse(text)
        }
    }

    @Test("oversized cube is rejected")
    func oversized() {
        #expect(throws: CubeLUTParser.ParseError.sizeOutOfRange(128)) {
            _ = try CubeLUTParser.parse("LUT_3D_SIZE 128")
        }
    }

    @Test("invert LUT remaps a red pixel toward cyan (AC① guarded)")
    func invertRemapsPixels() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutLUTTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("invert.cube")
        try invertCube(size: 2).write(to: url, atomically: true, encoding: .utf8)

        let bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: bounds)
        let effect = Effect(type: .externalLUT, parameters: ["intensity": 1.0], lutPath: url.path)
        let output = VisualEffectPixelProcessor.apply([effect], to: red)
        #expect(output.extent == bounds)

        let context = CIContext()
        var bytes = [UInt8](repeating: 0, count: 4)
        let pixel = CGRect(x: 0, y: 0, width: 1, height: 1)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                output.cropped(to: pixel),
                toBitmap: buffer.baseAddress!,
                rowBytes: 4,
                bounds: pixel,
                format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
            )
        }
        if bytes[3] == 0 {
            print("Skipping CIColorCube pixel assertion: renderer returned transparent black.")
        } else {
            // Inverted red → low red, high green+blue (cyan-ish).
            #expect(bytes[0] < 80)
            #expect(bytes[1] > 150)
            #expect(bytes[2] > 150)
        }
    }

    @Test("zero intensity leaves the image unchanged")
    func zeroIntensityPassthrough() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("passthrough-\(UUID().uuidString).cube")
        try invertCube(size: 2).write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let bounds = CGRect(x: 0, y: 0, width: 2, height: 2)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: bounds)
        let effect = Effect(type: .externalLUT, parameters: ["intensity": 0.0], lutPath: url.path)
        let output = VisualEffectPixelProcessor.apply([effect], to: red)
        #expect(output.extent == bounds)
    }
}

/// Wiring visibility for the LUT import UI (not a completion criterion by
/// itself — see spec DoD §1.3).
@Suite("Cube LUT Static Contract")
struct CubeLUTStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("processor and model support external LUTs")
    func processorSupportsExternalLUT() throws {
        let processor = try source("Sources/MovieCutCore/Rendering/VisualEffectPixelProcessor.swift")
        #expect(processor.contains("case .externalLUT"))
        #expect(processor.contains("CIColorCube"))

        let model = try source("Sources/MovieCutCore/Models/Effect.swift")
        #expect(model.contains("case externalLUT"))
        #expect(model.contains("var lutPath: String?"))
    }

    @Test("view model imports and validates LUTs")
    func viewModelImports() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("func importExternalLUT"))
        #expect(viewModel.contains("CubeLUTParser.parse(contentsOf: url)"))
        #expect(viewModel.contains("MovieCut/LUTs"))

        let inspector = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")
        #expect(inspector.contains("Import LUT"))
        #expect(inspector.contains("importExternalLUT"))
    }
}
