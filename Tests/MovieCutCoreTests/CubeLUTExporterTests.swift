import Foundation
import Testing
@testable import MovieCutCore

/// CA-26 — LUT export. Round-trip은 Tolerance 등급(%.6f 직렬화 정밀도),
/// bake는 생산 프로세서(ColorCorrectionPixelProcessor)를 경유하므로
/// 프리뷰=출력 수학과 구조적으로 동일하다.
@Suite("Cube LUT Exporter (CA-26)")
struct CubeLUTExporterTests {
    /// Values chosen to be exact at %.6f so the round-trip is comparable.
    private static let sourceCubeText = """
        TITLE "Round Trip"
        # comment lines are tolerated by the parser
        LUT_3D_SIZE 2
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 1.0 1.0 1.0

        0.000000 0.000000 0.000000
        1.000000 0.250000 0.500000
        0.123456 0.654321 0.111111
        0.999000 0.500000 0.250000
        0.100000 0.900000 0.400000
        0.600000 0.200000 0.800000
        0.750000 0.750000 0.750000
        0.325000 0.125000 0.975000
        """

    @Test("parse → serialize → parse round-trips within %.6f precision and preserves row order")
    func roundTripWithinSerializePrecision() throws {
        let original = try CubeLUTParser.parse(Self.sourceCubeText)
        let serialized = try CubeLUTExporter.serialize(original, title: "Re-exported")

        #expect(serialized.contains("TITLE \"Re-exported\""))
        #expect(serialized.contains("LUT_3D_SIZE 2"))

        let reparsed = try CubeLUTParser.parse(serialized)
        #expect(reparsed.dimension == original.dimension)
        #expect(reparsed.data.count == original.data.count)
        for (index, (a, b)) in zip(original.data, reparsed.data).enumerated() where index % 4 != 3 {
            #expect(abs(a - b) <= 1e-6, "channel \(index) drifted: \(a) vs \(b)")
        }
        // Red-fastest order preserved: the first data row round-trips to the
        // first table entry the parser produced.
        let firstLine = serialized.split(separator: "\n").first { !$0.contains("TITLE") && !$0.contains("LUT_3D_SIZE") && !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("DOMAIN") }
        #expect(firstLine == "0.000000 0.000000 0.000000")
        // This path is a NORMALIZED re-serialization, not a lossless export:
        // the source's DOMAIN lines and comments are intentionally absent.
        #expect(!serialized.contains("DOMAIN"))
        #expect(!serialized.contains("# comment"))
    }

    @Test("serialize rejects inconsistent cubes instead of crashing")
    func serializeValidatesShape() {
        // Data count mismatch: indexing dimension³ rows would run past the
        // array's end — must throw, never trap.
        #expect(throws: CubeLUTExportError.dataCountMismatch(dimension: 2, dataCount: 8)) {
            _ = try CubeLUTExporter.serialize(
                CubeLUT(dimension: 2, data: [0, 0, 0, 1, 0.5, 0.5, 0.5, 1]),
                title: "broken"
            )
        }
        // Dimension outside the parser-supported range.
        #expect(throws: CubeLUTExportError.dimensionOutOfRange(1)) {
            _ = try CubeLUTExporter.serialize(CubeLUT(dimension: 1, data: []), title: "broken")
        }
        #expect(throws: CubeLUTExportError.dimensionOutOfRange(66)) {
            _ = try CubeLUTExporter.serialize(CubeLUT(dimension: 66, data: []), title: "broken")
        }
    }

    @Test("bake rejects invalid dimensions explicitly — no silent identity substitute")
    func bakeRejectsInvalidDimension() throws {
        #expect(throws: CubeLUTExportError.dimensionOutOfRange(0)) {
            _ = try CubeLUTExporter.bake(dimension: 0, colorCorrection: ColorCorrection())
        }
        #expect(throws: CubeLUTExportError.dimensionOutOfRange(1)) {
            _ = try CubeLUTExporter.bake(dimension: 1, colorCorrection: ColorCorrection())
        }
        #expect(throws: CubeLUTExportError.dimensionOutOfRange(66)) {
            _ = try CubeLUTExporter.bake(dimension: 66, colorCorrection: ColorCorrection())
        }
        // Boundary dimensions stay legal.
        let smallest = try CubeLUTExporter.bake(dimension: 2, colorCorrection: ColorCorrection())
        #expect(smallest.dimension == 2)
    }

    @Test("a 65³ bake+serialize keeps the main actor responsive")
    func bigLUTWorkStaysOffMainThread() async throws {
        // The heavy LUT work must be safe to run off the main actor (the
        // export path schedules exactly this combo on a detached task). While
        // it runs, main-actor hops must stay fast.
        let correction = ColorCorrection(brightness: 0.15, contrast: 1.1, saturation: 1.05)
        let clock = ContinuousClock()
        final class Progress: @unchecked Sendable {
            private let lock = NSLock()
            private var finished = false
            var isFinished: Bool {
                lock.lock(); defer { lock.unlock() }
                return finished
            }
            func markFinished() {
                lock.lock(); defer { lock.unlock() }
                finished = true
            }
        }
        let progress = Progress()
        let heavy = Task.detached(priority: .userInitiated) {
            defer { progress.markFinished() }
            let lut = try CubeLUTExporter.bake(dimension: 65, colorCorrection: correction)
            _ = try CubeLUTExporter.serialize(lut, title: "responsiveness")
        }

        var slowestMainActorHop: Duration = .zero
        var probes = 0
        while !progress.isFinished {
            let hopStart = clock.now
            await MainActor.run {}
            let elapsed = hopStart.duration(to: clock.now)
            if elapsed > slowestMainActorHop { slowestMainActorHop = elapsed }
            probes += 1
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        try await heavy.value

        #expect(probes > 0, "the probe loop must overlap the heavy work")
        #expect(
            slowestMainActorHop < .milliseconds(500),
            "main actor blocked for \(slowestMainActorHop) during a 65³ LUT export"
        )
    }

    @Test("bake with identity correction reproduces the identity grid")
    func bakeIdentity() throws {
        let dimension = 4
        let baked = try CubeLUTExporter.bake(dimension: dimension, colorCorrection: ColorCorrection())
        #expect(baked.dimension == dimension)
        let scale = Float(dimension - 1)
        for index in 0..<(dimension * dimension * dimension) {
            let r = Float(index % dimension) / scale
            let g = Float((index / dimension) % dimension) / scale
            let b = Float(index / (dimension * dimension)) / scale
            let offset = index * 4
            #expect(abs(baked.data[offset] - r) <= 0.002, "r at \(index)")
            #expect(abs(baked.data[offset + 1] - g) <= 0.002, "g at \(index)")
            #expect(abs(baked.data[offset + 2] - b) <= 0.002, "b at \(index)")
        }
    }

    @Test("bake with brightness lift brightens mid-gray and lifts black")
    func bakeBrightness() throws {
        let dimension = 4
        let baked = try CubeLUTExporter.bake(
            dimension: dimension,
            colorCorrection: ColorCorrection(brightness: 0.2)
        )
        let mid = dimension / 2
        let midEntry = (mid * dimension * dimension) + (mid * dimension) + mid // b*N² + g*N + r
        let offset = midEntry * 4
        let midIn = Float(mid) / Float(dimension - 1)
        #expect(baked.data[offset] > midIn, "mid gray should brighten")
        // Black lifts with positive brightness.
        #expect(baked.data[0] > 0, "black should lift")
    }
}
