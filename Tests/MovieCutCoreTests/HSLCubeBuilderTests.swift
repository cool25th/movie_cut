import Foundation
import MovieCutCore
import Testing

@Suite("HSL Cube Builder")
struct HSLCubeBuilderTests {
    @Test("identity HSL transform keeps primary and gray colors")
    func identityTransformKeepsColors() {
        expectClose(HSLCubeBuilder.apply(.init(red: 1, green: 0, blue: 0), bands: []), .init(red: 1, green: 0, blue: 0))
        expectClose(HSLCubeBuilder.apply(.init(red: 0, green: 0, blue: 1), bands: [HSLBand(center: .red)]), .init(red: 0, green: 0, blue: 1))
        expectClose(HSLCubeBuilder.apply(.init(red: 0.5, green: 0.5, blue: 0.5), bands: [HSLBand(center: .blue)]), .init(red: 0.5, green: 0.5, blue: 0.5))
    }

    @Test("red saturation minus one turns pure red grayscale")
    func redSaturationMinusOneTurnsRedGrayscale() {
        let output = HSLCubeBuilder.apply(
            .init(red: 1, green: 0, blue: 0),
            bands: [HSLBand(center: .red, saturation: -1)]
        )

        #expect(abs(output.red - output.green) < 0.0001)
        #expect(abs(output.green - output.blue) < 0.0001)
        #expect(abs(output.red - 0.5) < 0.0001)
    }

    @Test("red band does not affect pure blue")
    func redBandDoesNotAffectBlue() {
        let output = HSLCubeBuilder.apply(
            .init(red: 0, green: 0, blue: 1),
            bands: [HSLBand(center: .red, saturation: -1, luminance: 1)]
        )
        expectClose(output, .init(red: 0, green: 0, blue: 1), tolerance: 0.0001)
    }

    @Test("positive red hue shift moves red toward orange")
    func positiveRedHueShiftMovesTowardOrange() {
        let output = HSLCubeBuilder.apply(
            .init(red: 1, green: 0, blue: 0),
            bands: [HSLBand(center: .red, hueShift: 30)]
        )

        #expect(output.red > 0.95)
        #expect(output.green > 0.45)
        #expect(output.blue < 0.05)
    }

    @Test("falloff wraps across the red boundary")
    func falloffWrapsAcrossRedBoundary() {
        let nearRed = HSLCubeBuilder.falloffWeight(hue: 350, center: HSLBandCenter.red.hueDegrees)
        let farRed = HSLCubeBuilder.falloffWeight(hue: 90, center: HSLBandCenter.red.hueDegrees)
        #expect(nearRed > 0.5)
        #expect(farRed == 0)
    }

    @Test("identity cube has RGBA samples and passthrough endpoints")
    func identityCubeHasExpectedShapeAndEndpoints() {
        let cube = HSLCubeBuilder.cube(size: 4, bands: [])
        #expect(cube.count == 4 * 4 * 4 * 4)
        #expect(cube[0] == 0)
        #expect(cube[1] == 0)
        #expect(cube[2] == 0)
        #expect(cube[3] == 1)
        let last = cube.count - 4
        #expect(cube[last] == 1)
        #expect(cube[last + 1] == 1)
        #expect(cube[last + 2] == 1)
        #expect(cube[last + 3] == 1)
    }

    private func expectClose(_ actual: HSLCubeBuilder.RGB, _ expected: HSLCubeBuilder.RGB, tolerance: Double = 0.001) {
        #expect(abs(actual.red - expected.red) <= tolerance)
        #expect(abs(actual.green - expected.green) <= tolerance)
        #expect(abs(actual.blue - expected.blue) <= tolerance)
    }
}
