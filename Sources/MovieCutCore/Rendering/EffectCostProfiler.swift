import CoreImage
import Darwin
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

        // G-28 real measurement: the effect's memory cost is the peak
        // footprint its renders reach ABOVE the peak of rendering the SAME
        // frame UNFILTERED — a differential taken with the identical
        // harness, so the process's standing memory cancels. The OLD
        // value was a placeholder (physicalMemory × 0.001, identical for
        // every effect). The sampler polls task_vm_info.phys_footprint —
        // the same metric the T2-M harness uses — at ~1ms in parallel,
        // because CI's transient filter surfaces live INSIDE the render
        // call and between-render sampling misses them.
        let (baselinePeakBytes, _) = timedRenderPeak(frame, context: context, canvas: canvas, iterations: iterations)
        let (effectPeakBytes, median) = timedRenderPeak(applied, context: context, canvas: canvas, iterations: iterations)
        let effectMemory = max(0, Double(max(effectPeakBytes - baselinePeakBytes, 0)) / 1_000_000)

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

    /// Warm-up + timed renders of `image` with the footprint sampler
    /// running — returns (peak footprint bytes, median ms/frame).
    private static func timedRenderPeak(
        _ image: CIImage,
        context: CIContext,
        canvas: EffectCostProfile.ReferenceCanvas,
        iterations: Int
    ) -> (peakBytes: Int64, medianMs: Double) {
        let width = canvas.width
        let height = canvas.height
        var bitmap = [UInt8](repeating: 0, count: width * height * 4)

        // Warm up (first render compiles shaders).
        context.render(image, toBitmap: &bitmap, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: nil)

        let sampler = FootprintSampler()
        sampler.start()
        var times: [Double] = []
        for _ in 0..<iterations {
            let start = DispatchTime.now()
            context.render(image, toBitmap: &bitmap, rowBytes: width * 4, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: nil)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            times.append(elapsed)
        }
        let peak = sampler.stop()
        let median = times.sorted()[times.count / 2]
        return (peak, median)
    }

    /// The process's current physical footprint in bytes, or nil when the
    /// Mach call fails (callers treat nil as "no baseline").
    static func currentFootprintBytes() -> Int64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int64(info.phys_footprint)
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

/// Polls task_vm_info.phys_footprint on a background thread while the
/// profiler's timed renders run, keeping the maximum. CI filters allocate
/// transient intermediate surfaces inside the render call, so sampling
/// only BETWEEN renders misses the peaks; ~1ms polling catches them
/// without measurably perturbing the timing loop.
final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Int64 = 0
    private var thread: Thread?

    func start() {
        let thread = Thread { [weak self] in
            guard let self else { return }
            while true {
                let sample = EffectCostProfiler.currentFootprintBytes() ?? 0
                self.lock.lock()
                let stopped = self.peak < 0
                if !stopped, sample > self.peak {
                    self.peak = sample
                }
                self.lock.unlock()
                if stopped { return }
                usleep(1_000)
            }
        }
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    /// Stops the sampler and returns the peak footprint in bytes.
    func stop() -> Int64 {
        // Signal the loop by flipping the peak negative (the sentinel is
        // resolved back below), then join-ish: the loop exits on its next
        // 1ms tick. One extra tick of latency is fine — the renders are
        // done, nothing new can raise the true peak.
        lock.lock()
        let observed = peak
        peak = -1
        lock.unlock()
        return max(0, observed)
    }
}
