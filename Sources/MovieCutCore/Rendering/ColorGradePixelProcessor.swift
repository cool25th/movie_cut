import CoreImage
import Foundation

/// Applies a 3-way ``ColorGrade`` (lift / gamma / gain) to rendered pixels,
/// shared by preview and export.
///
/// ASC CDL `out = (in * slope + offset) ^ power`:
/// - slope (gain) + offset (lift) map to a single `CIColorMatrix` (per-channel
///   diagonal slope, offset as the bias vector),
/// - power (gamma) maps to `CIGammaAdjust`.
public enum ColorGradePixelProcessor {
    private static let hslCubeDimension = 64
    private static let curveCubeDimension = 64

    private nonisolated(unsafe) static let hslCubeCache: NSCache<NSString, CubeLUTBox> = {
        let cache = NSCache<NSString, CubeLUTBox>()
        cache.countLimit = 24
        return cache
    }()

    private nonisolated(unsafe) static let curveCubeCache: NSCache<NSString, CubeLUTBox> = {
        let cache = NSCache<NSString, CubeLUTBox>()
        cache.countLimit = 24
        return cache
    }()

    public static func apply(_ grade: ColorGrade, to image: CIImage) -> CIImage {
        guard !grade.isIdentity else { return image }

        let originalExtent = image.extent
        var output = image

        if !primaryIsIdentity(grade) {
            output = applyPrimaryGrade(grade, to: output)
        }

        if let bands = activeHSLBands(grade.hslBands),
           let hslCube = hslCube(for: bands) {
            output = applyColorCube(hslCube, to: output)
        }

        if let curves = grade.curves,
           !curves.isIdentity,
           let curveCube = curveCube(for: curves) {
            output = applyColorCube(curveCube, to: output)
        }

        return output.cropped(to: originalExtent)
    }

    public static func isIdentity(_ grade: ColorGrade) -> Bool { grade.isIdentity }

    private static func applyPrimaryGrade(_ grade: ColorGrade, to image: CIImage) -> CIImage {
        var output = image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: grade.gain.red, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: grade.gain.green, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: grade.gain.blue, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: grade.lift.red, y: grade.lift.green, z: grade.lift.blue, w: 0)
            ]
        )

        if grade.gamma != 1 {
            output = output.applyingFilter("CIGammaAdjust", parameters: ["inputPower": grade.gamma])
        }

        return output
    }

    private static func applyColorCube(_ cube: CubeLUTBox, to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorCube") else { return image }
        filter.setValue(cube.dimension, forKey: "inputCubeDimension")
        filter.setValue(cube.dataObject, forKey: "inputCubeData")
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    private static func hslCube(for bands: [HSLBand]) -> CubeLUTBox? {
        let key = "hsl:\(hslCubeDimension):\(hslKey(for: bands))" as NSString
        if let cached = hslCubeCache.object(forKey: key) {
            return cached
        }
        let data = HSLCubeBuilder.cube(size: hslCubeDimension, bands: bands)
        let cube = CubeLUTBox(lut: CubeLUT(dimension: hslCubeDimension, data: data))
        hslCubeCache.setObject(cube, forKey: key)
        return cube
    }

    private static func curveCube(for curves: ColorCurves) -> CubeLUTBox? {
        let curves = ColorCurves(master: curves.master, red: curves.red, green: curves.green, blue: curves.blue)
        guard !curves.isIdentity else { return nil }

        let key = "curves:\(curveCubeDimension):\(curveKey(for: curves))" as NSString
        if let cached = curveCubeCache.object(forKey: key) {
            return cached
        }

        let data = curveCubeData(size: curveCubeDimension, curves: curves)
        let cube = CubeLUTBox(lut: CubeLUT(dimension: curveCubeDimension, data: data))
        curveCubeCache.setObject(cube, forKey: key)
        return cube
    }

    private static func curveCubeData(size: Int, curves: ColorCurves) -> [Float] {
        let size = max(size, 2)
        var data: [Float] = []
        data.reserveCapacity(size * size * size * 4)

        for blueIndex in 0..<size {
            for greenIndex in 0..<size {
                for redIndex in 0..<size {
                    let red = Double(redIndex) / Double(size - 1)
                    let green = Double(greenIndex) / Double(size - 1)
                    let blue = Double(blueIndex) / Double(size - 1)

                    data.append(Float(applyCurves(to: red, master: curves.master, channel: curves.red)))
                    data.append(Float(applyCurves(to: green, master: curves.master, channel: curves.green)))
                    data.append(Float(applyCurves(to: blue, master: curves.master, channel: curves.blue)))
                    data.append(1)
                }
            }
        }
        return data
    }

    private static func applyCurves(to value: Double, master: [CurvePoint], channel: [CurvePoint]) -> Double {
        let masterValue = CurveEvaluator.evaluate(points: master, at: value)
        return CurveEvaluator.evaluate(points: channel, at: masterValue)
    }

    private static func activeHSLBands(_ bands: [HSLBand]?) -> [HSLBand]? {
        guard let bands else { return nil }
        var byCenter: [HSLBandCenter: HSLBand] = [:]
        for band in bands {
            byCenter[band.center] = HSLBand(
                center: band.center,
                hueShift: band.hueShift,
                saturation: band.saturation,
                luminance: band.luminance
            )
        }
        let active = HSLBandCenter.allCases.compactMap { byCenter[$0] }.filter { !$0.isIdentity }
        return active.isEmpty ? nil : active
    }

    private static func primaryIsIdentity(_ grade: ColorGrade) -> Bool {
        grade.lift == .zero && grade.gamma == 1 && grade.gain == .one
    }

    private static func hslKey(for bands: [HSLBand]) -> String {
        bands.map { band in
            [
                band.center.rawValue,
                String(band.hueShift),
                String(band.saturation),
                String(band.luminance)
            ].joined(separator: ",")
        }
        .joined(separator: "|")
    }

    private static func curveKey(for curves: ColorCurves) -> String {
        [
            "m:\(curvePointsKey(curves.master))",
            "r:\(curvePointsKey(curves.red))",
            "g:\(curvePointsKey(curves.green))",
            "b:\(curvePointsKey(curves.blue))"
        ].joined(separator: "|")
    }

    private static func curvePointsKey(_ points: [CurvePoint]) -> String {
        points.map { "\(String($0.x)),\(String($0.y))" }.joined(separator: ";")
    }
}
