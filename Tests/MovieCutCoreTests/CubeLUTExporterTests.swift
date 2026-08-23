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

    @Test("parse → serialize → parse is lossless and preserves row order")
    func roundTripLossless() throws {
        let original = try CubeLUTParser.parse(Self.sourceCubeText)
        let serialized = CubeLUTExporter.serialize(original, title: "Re-exported")

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
    }

    @Test("bake with identity correction reproduces the identity grid")
    func bakeIdentity() {
        let dimension = 4
        let baked = CubeLUTExporter.bake(dimension: dimension, colorCorrection: ColorCorrection())
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
    func bakeBrightness() {
        let dimension = 4
        let baked = CubeLUTExporter.bake(
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
