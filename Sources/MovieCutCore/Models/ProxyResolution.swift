import Foundation

/// The resolution a generated proxy is transcoded to.
///
/// `CAPCUT_BENCHMARK_STANDARD.md` B-I7 requires a resolution choice, with 720p
/// as the recommendation CapCut surfaces to its users.
///
/// Each case maps to an `AVAssetExportSession` preset. The presets are the only
/// sizes AVFoundation offers for this kind of downscale, so the menu mirrors
/// them exactly rather than inventing sizes that would silently snap to the
/// nearest preset.
public enum ProxyResolution: String, Codable, Sendable, CaseIterable, Equatable {
    case p480
    case p540
    case p720
    case p1080

    /// The resolution used when a project does not specify one.
    ///
    /// Deliberately 540p rather than the 720p CapCut recommends: proxy
    /// generation was hardwired to `AVAssetExportPreset960x540` before this
    /// setting existed, so defaulting anywhere else would silently change the
    /// output of every existing project the first time a proxy was regenerated.
    /// 720p is marked as recommended in the picker instead, which is where
    /// CapCut's guidance belongs.
    public static let `default`: ProxyResolution = .p540

    /// The longest edge, in pixels, the proxy is fitted into.
    public var maxDimension: CGFloat {
        switch self {
        case .p480: return 640
        case .p540: return 960
        case .p720: return 1280
        case .p1080: return 1920
        }
    }

    /// Short label for menus, e.g. "720p".
    public var shortLabel: String {
        switch self {
        case .p480: return "480p"
        case .p540: return "540p"
        case .p720: return "720p"
        case .p1080: return "1080p"
        }
    }

    /// The nominal frame size of the matching export preset.
    public var presetSize: CGSize {
        switch self {
        case .p480: return CGSize(width: 640, height: 480)
        case .p540: return CGSize(width: 960, height: 540)
        case .p720: return CGSize(width: 1280, height: 720)
        case .p1080: return CGSize(width: 1920, height: 1080)
        }
    }

    /// Whether this is the size CapCut recommends (B-I7).
    public var isRecommended: Bool { self == .p720 }

    /// Filename-safe token so proxies of different resolutions coexist on disk.
    ///
    /// Without this the target path would be identical across resolutions and
    /// `proxyInfoIfReady` would hand back the previously generated file, so
    /// changing the setting would appear to do nothing.
    public var fileToken: String { shortLabel }
}
