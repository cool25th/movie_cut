import Foundation

extension TemplateStore {
    static var builtInTemplateBundles: [TemplateBundle] {
        [
            shortsReelsTemplate,
            landscapeTutorialTemplate,
            squareSocialTemplate,
            photoSlideshowTemplate
        ]
    }

    static var shortsReelsTemplate: TemplateBundle {
        let textDefaults = TextClipContent(
            text: "Your headline",
            fontSize: 56,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#00000099",
            position: CGPoint(x: 540, y: 1440)
        )

        return TemplateBundle(
            identifier: "com.moviecut.template.shorts-reels",
            name: "Shorts/Reels",
            description: "Portrait social video with a text overlay placeholder.",
            author: "MovieCut",
            canvasPreset: CanvasPreset(aspectRatio: .portrait9x16, frameRate: .fps30),
            tracks: [
                TemplateTrack(
                    kind: .text,
                    name: "Text 1",
                    placeholderClips: [
                        TemplateClip(kind: .text, duration: 8, textContent: textDefaults)
                    ]
                )
            ],
            textStyleDefaults: textDefaults,
            exportPreset: ExportSettings(resolution: .p1080, frameRate: .fps30)
        )
    }

    static var landscapeTutorialTemplate: TemplateBundle {
        let textDefaults = TextClipContent(
            text: "Step title",
            fontSize: 44,
            fontColor: "#FFFFFF",
            alignment: .leading,
            backgroundColor: "#111111CC",
            position: CGPoint(x: 160, y: 880)
        )

        return TemplateBundle(
            identifier: "com.moviecut.template.landscape-tutorial",
            name: "Landscape Tutorial",
            description: "16:9 tutorial layout with video, narration, and title tracks.",
            author: "MovieCut",
            canvasPreset: CanvasPreset(aspectRatio: .landscape16x9, frameRate: .fps30),
            tracks: [
                TemplateTrack(
                    kind: .video,
                    name: "Video 1",
                    placeholderClips: [
                        TemplateClip(kind: .video, duration: 12)
                    ]
                ),
                TemplateTrack(
                    kind: .audio,
                    name: "Audio 1",
                    placeholderClips: [
                        TemplateClip(kind: .audio, duration: 12)
                    ]
                ),
                TemplateTrack(
                    kind: .text,
                    name: "Text 1",
                    placeholderClips: [
                        TemplateClip(kind: .text, duration: 4, textContent: textDefaults)
                    ]
                )
            ],
            textStyleDefaults: textDefaults,
            exportPreset: ExportSettings(resolution: .p1080, frameRate: .fps30)
        )
    }

    static var squareSocialTemplate: TemplateBundle {
        let textDefaults = TextClipContent(
            text: "Post title",
            fontSize: 48,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#0A0A0ACC",
            position: CGPoint(x: 540, y: 900)
        )

        return TemplateBundle(
            identifier: "com.moviecut.template.square-social",
            name: "Square Social",
            description: "1:1 social post template with image and text placeholders.",
            author: "MovieCut",
            canvasPreset: CanvasPreset(aspectRatio: .square1x1, frameRate: .fps30),
            tracks: [
                TemplateTrack(
                    kind: .video,
                    name: "Image 1",
                    placeholderClips: [
                        TemplateClip(kind: .image, duration: 6)
                    ]
                ),
                TemplateTrack(
                    kind: .text,
                    name: "Text 1",
                    placeholderClips: [
                        TemplateClip(kind: .text, duration: 6, textContent: textDefaults)
                    ]
                )
            ],
            textStyleDefaults: textDefaults,
            exportPreset: ExportSettings(resolution: .p1080, frameRate: .fps30)
        )
    }

    /// A 9:16 photo-slideshow template (G-21 partial): one video track of
    /// image placeholders plus an empty audio track ready for BGM. The app
    /// layer replaces the image placeholders with the user's chosen photos.
    static var photoSlideshowTemplate: TemplateBundle {
        let textDefaults = TextClipContent(
            text: "Your title",
            fontSize: 64,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#00000099",
            position: CGPoint(x: 540, y: 1620)
        )

        let imagePlaceholders = (0..<3).map { _ in
            TemplateClip(kind: .image, duration: PhotoSlideshowDefaults.clipDuration)
        }

        return TemplateBundle(
            identifier: "com.moviecut.template.photo-slideshow",
            name: "Photo to Video",
            description: "Turn your photos into a 9:16 short. Add photos, then export — transitions and a music slot are ready.",
            author: "MovieCut",
            canvasPreset: CanvasPreset(aspectRatio: .portrait9x16, frameRate: .fps30),
            tracks: [
                TemplateTrack(
                    kind: .video,
                    name: "Photos",
                    placeholderClips: imagePlaceholders
                ),
                TemplateTrack(
                    kind: .audio,
                    name: "Music",
                    placeholderClips: []
                ),
                TemplateTrack(
                    kind: .text,
                    name: "Title",
                    placeholderClips: [
                        TemplateClip(kind: .text, duration: PhotoSlideshowDefaults.clipDuration, textContent: textDefaults)
                    ]
                )
            ],
            textStyleDefaults: textDefaults,
            exportPreset: ExportSettings(resolution: .p1080, frameRate: .fps30)
        )
    }
}

/// Shared defaults for the photo-to-video slideshow workflow.
public enum PhotoSlideshowDefaults {
    /// Duration of each image clip on the timeline, in seconds.
    public static let clipDuration: TimeInterval = 3.0

    /// Default transition duration applied between adjacent photos, in seconds.
    public static let transitionDuration: TimeInterval = 0.5
}

/// Pace preset controlling how long each photo stays on screen.
public enum PhotoSlideshowPace: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    /// Each photo shows for ~5 seconds.
    case slow
    /// Each photo shows for ~3 seconds (default).
    case normal
    /// Each photo shows for ~1.5 seconds.
    case fast

    public var id: String { rawValue }

    /// Per-photo duration in seconds.
    public var clipDuration: TimeInterval {
        switch self {
        case .slow: return 5.0
        case .normal: return PhotoSlideshowDefaults.clipDuration
        case .fast: return 1.5
        }
    }

    /// User-visible display name.
    public var displayName: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }
}

/// Transition style preset applied between adjacent photos.
public enum PhotoSlideshowTransition: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    /// Hard cut — no transition between photos.
    case none
    /// Smooth cross-dissolve between photos (default).
    case crossDissolve
    /// Fade through black between photos.
    case fadeThroughBlack

    public var id: String { rawValue }

    /// The core transition type applied to each non-first photo, or nil for a
    /// hard cut.
    public var transitionType: TransitionType? {
        switch self {
        case .none: return nil
        case .crossDissolve: return .crossDissolve
        case .fadeThroughBlack: return .fadeThroughBlack
        }
    }

    /// User-visible display name.
    public var displayName: String {
        switch self {
        case .none: return "None"
        case .crossDissolve: return "Cross Dissolve"
        case .fadeThroughBlack: return "Fade"
        }
    }
}
