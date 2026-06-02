import Foundation

extension TemplateStore {
    static var builtInTemplateBundles: [TemplateBundle] {
        [
            shortsReelsTemplate,
            landscapeTutorialTemplate,
            squareSocialTemplate
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
}
