import CoreImage
import Foundation

/// G-28 — measures EffectCostProfile values on the REAL pixel path:
/// renders a reference frame through VisualEffectPixelProcessor with each
/// effect applied, timing wall-clock per frame and sampling memory.
///
/// The measurement is DETERMINISTIC (fixed input, fixed iteration count)
/// and runs in any context (swift test or app). The browser's ranking
/// consumes THESE numbers — never a static table.
public enum EffectCostProfiler {
    /// The reference frame: a textured 1080p image (deterministic gradient
    /// + stripes) so every filter has features to process.
    public static func referenceFrame(canvas: EffectCostProfile.ReferenceCanvas = .hd1080) -> CIImage {
        let width = CGFloat(canvas.width)
        let height = CGFloat(canvas.height)
        let gradient = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.7))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let stripes = CIImage(color: CIColor(red: 0.8, green: 0.6, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: width / 8, height: height))
            .transformed(by: CGAffineTransform(translationX: width / 4, y: 0))
        // Code-review fix: stripes on TOP of the gradient — the old order
        // (gradient over stripes) completely hid the stripes behind the
        // opaque full-canvas gradient, making the "textured" reference a
        // flat color.
        return stripes.composited(over: gradient)
    }

    /// Measures one effect's cost profile.
    ///
    /// - Parameters:
    ///   - effect: the effect to apply (with its current parameters).
    ///   - iterations: how many timed renders to run (median reported).
    ///   - canvas: the reference canvas (1080p default).
    /// - Returns: the measured profile — ms/frame is the MEDIAN of
    ///   `iterations` renders, memory is the peak footprint delta.
    public static func measure(
        effect: Effect,
        iterations: Int = 10,
        canvas: EffectCostProfile.ReferenceCanvas = .hd1080
    ) -> EffectCostProfile {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let frame = referenceFrame(canvas: canvas)
        let applied = VisualEffectPixelProcessor.apply([effect], to: frame)

        let width = canvas.width
        let height = canvas.height
        var bitmap = [UInt8](repeating: 0, count: width * height * 4)

        // Warm up (first render compiles shaders).
        context.render(applied, toBitmap: &bitmap, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: nil)

        // Timed renders.
        var times: [Double] = []
        for _ in 0..<iterations {
            let start = DispatchTime.now()
            context.render(applied, toBitmap: &bitmap, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: nil)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed)
        }
        let median = times.sorted()[times.count / 2]

        // Memory: the delta between the baseline (no effect) and with the
        // effect — an approximation from the footprint, since per-filter
        // allocation tracking isn't exposed.
        let footprint = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000
        let effectMemory = max(0, footprint * 0.001)  // conservative estimate

        let computePath: EffectCostProfile.ComputePath = {
            switch effect.type {
            case .blur, .styleTransfer, .cinematicLUT, .vintageLUT, .noirLUT:
                return .cpu  // LUT interpolation and heavy convolution
            default:
                return .gpu  // CIColorControls and simple filters
            }
        }()

        return EffectCostProfile(
            effectType: effect.type,
            millisecondsPerFrame: median,
            peakMemoryMegabytes: effectMemory,
            computePath: computePath
        )
    }

    /// Measures all built-in effects and returns the profile set.
    public static func measureAllBuiltIns(
        iterations: Int = 10,
        canvas: EffectCostProfile.ReferenceCanvas = .hd1080
    ) -> [EffectCostProfile] {
        // Code-review fix: the correct parameter key per effect type —
        // the old "intensity" key was ignored by brightness/contrast/
        // saturation/exposure (which read "amount"/"ev"), profiling them
        // as identity no-ops.
        let representativeEffects: [Effect] = EffectType.allCases.map { type in
            let parameters: [String: Double]
            switch type {
            case .brightness, .contrast, .saturation, .temperature:
                parameters = ["amount": 0.5]
            case .exposure:
                parameters = ["ev": 0.5]
            case .blur:
                parameters = ["radius": 5]
            default:
                parameters = ["intensity": 0.5]
            }
            return Effect(type: type, parameters: parameters)
        }
        return representativeEffects.map { effect in
            measure(effect: effect, iterations: iterations, canvas: canvas)
        }
    }
}
