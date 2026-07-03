import Foundation

// Shared display-name extensions for model enums.
// These live in Core (not App/MovieCutMac) so both Mac and iOS targets can use them.

extension EffectType {
    public var displayName: String {
        switch self {
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .temperature: return "Temperature"
        case .exposure: return "Exposure"
        case .fadeIn: return "Fade In"
        case .fadeOut: return "Fade Out"
        case .crossDissolve: return "Cross Dissolve"
        case .grayscale: return "Grayscale"
        case .sepia: return "Sepia"
        case .blur: return "Blur"
        case .styleTransfer: return "Style Transfer"
        case .cinematicLUT: return "Cinematic LUT"
        case .vintageLUT: return "Vintage LUT"
        case .noirLUT: return "Noir LUT"
        case .vividLUT: return "Vivid LUT"
        case .coolLUT: return "Cool LUT"
        case .externalLUT: return "Imported LUT"
        }
    }
}

extension MaskShape {
    public var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .triangle: return "Triangle"
        case .diamond: return "Diamond"
        case .linear: return "Linear"
        case .brush: return "Brush"
        }
    }
}

extension TransitionType {
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .crossDissolve: return "Cross Dissolve"
        case .fadeThroughBlack: return "Fade Through Black"
        case .wipeRight: return "Wipe Right"
        case .wipeLeft: return "Wipe Left"
        case .wipeUp: return "Wipe Up"
        case .wipeDown: return "Wipe Down"
        case .slideLeft: return "Slide Left"
        case .slideRight: return "Slide Right"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .glitch: return "Glitch"
        }
    }
}
