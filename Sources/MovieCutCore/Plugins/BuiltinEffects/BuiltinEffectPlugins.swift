import Foundation

struct GrayscaleEffectPlugin: EffectPlugin {
    let wrappedEffect: Effect = .grayscale

    var manifest: PluginManifest {
        PluginManifest(
            identifier: "com.moviecut.plugin.effect.grayscale",
            name: "Grayscale",
            version: "1.0.0",
            author: "MovieCut",
            description: "Converts RGB pixels to grayscale.",
            entryPoint: "GrayscaleEffectPlugin",
            pluginTypes: [.effect]
        )
    }

    func apply(
        to pixelBuffer: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        time: TimeInterval
    ) throws {
        let pixels = pixelBuffer.assumingMemoryBound(to: UInt8.self)
        let byteCount = max(0, width * height * 4)

        for offset in stride(from: 0, to: byteCount, by: 4) {
            let red = Double(pixels[offset])
            let green = Double(pixels[offset + 1])
            let blue = Double(pixels[offset + 2])
            let gray = UInt8(clamping: Int((0.299 * red + 0.587 * green + 0.114 * blue).rounded()))

            pixels[offset] = gray
            pixels[offset + 1] = gray
            pixels[offset + 2] = gray
        }
    }

    static func register(into registry: PluginRegistry) {
        registry.register(plugin: Self())
    }
}

struct SepiaEffectPlugin: EffectPlugin {
    let wrappedEffect: Effect = .sepia

    var manifest: PluginManifest {
        PluginManifest(
            identifier: "com.moviecut.plugin.effect.sepia",
            name: "Sepia",
            version: "1.0.0",
            author: "MovieCut",
            description: "Applies a warm sepia tone to RGB pixels.",
            entryPoint: "SepiaEffectPlugin",
            pluginTypes: [.effect]
        )
    }

    func apply(
        to pixelBuffer: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        time: TimeInterval
    ) throws {
        let pixels = pixelBuffer.assumingMemoryBound(to: UInt8.self)
        let byteCount = max(0, width * height * 4)

        for offset in stride(from: 0, to: byteCount, by: 4) {
            let red = Double(pixels[offset])
            let green = Double(pixels[offset + 1])
            let blue = Double(pixels[offset + 2])

            pixels[offset] = UInt8(clamping: Int((0.393 * red + 0.769 * green + 0.189 * blue).rounded()))
            pixels[offset + 1] = UInt8(clamping: Int((0.349 * red + 0.686 * green + 0.168 * blue).rounded()))
            pixels[offset + 2] = UInt8(clamping: Int((0.272 * red + 0.534 * green + 0.131 * blue).rounded()))
        }
    }

    static func register(into registry: PluginRegistry) {
        registry.register(plugin: Self())
    }
}

struct BlurEffectPlugin: EffectPlugin {
    let wrappedEffect: Effect = .blur

    var manifest: PluginManifest {
        PluginManifest(
            identifier: "com.moviecut.plugin.effect.blur",
            name: "Blur",
            version: "1.0.0",
            author: "MovieCut",
            description: "Applies a simple 3x3 box blur to RGBA pixels.",
            entryPoint: "BlurEffectPlugin",
            pluginTypes: [.effect]
        )
    }

    func apply(
        to pixelBuffer: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        time: TimeInterval
    ) throws {
        guard width > 1, height > 1 else { return }

        let pixels = pixelBuffer.assumingMemoryBound(to: UInt8.self)
        let byteCount = width * height * 4
        let source = Array(UnsafeBufferPointer(start: pixels, count: byteCount))

        for y in 0 ..< height {
            for x in 0 ..< width {
                let targetOffset = ((y * width) + x) * 4
                var red = 0
                var green = 0
                var blue = 0
                var alpha = 0
                var samples = 0

                for sampleY in max(0, y - 1) ... min(height - 1, y + 1) {
                    for sampleX in max(0, x - 1) ... min(width - 1, x + 1) {
                        let sourceOffset = ((sampleY * width) + sampleX) * 4
                        red += Int(source[sourceOffset])
                        green += Int(source[sourceOffset + 1])
                        blue += Int(source[sourceOffset + 2])
                        alpha += Int(source[sourceOffset + 3])
                        samples += 1
                    }
                }

                pixels[targetOffset] = UInt8(clamping: red / samples)
                pixels[targetOffset + 1] = UInt8(clamping: green / samples)
                pixels[targetOffset + 2] = UInt8(clamping: blue / samples)
                pixels[targetOffset + 3] = UInt8(clamping: alpha / samples)
            }
        }
    }

    static func register(into registry: PluginRegistry) {
        registry.register(plugin: Self())
    }
}
