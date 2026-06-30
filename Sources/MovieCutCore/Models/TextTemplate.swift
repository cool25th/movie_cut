import CoreGraphics
import Foundation

public struct TextTemplate: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var content: TextClipContent
    public var animation: TextAnimation?

    public init(
        id: UUID = UUID(),
        name: String,
        content: TextClipContent,
        animation: TextAnimation? = nil
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.animation = animation
    }

    public static var builtIn: [TextTemplate] {
        [
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002001")!,
                name: "Title",
                content: TextClipContent(
                    text: "Title",
                    fontFamily: "Helvetica Neue",
                    fontSize: 104,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 540),
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 4, y: 4),
                    shadowBlur: 8,
                    isBold: true
                ),
                animation: TextAnimation(preset: .zoomIn, duration: 0.5)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002002")!,
                name: "Subtitle",
                content: TextClipContent(
                    text: "Subtitle",
                    fontFamily: "SF Pro",
                    fontSize: 42,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 920),
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 2, y: 2),
                    shadowBlur: 5
                ),
                animation: TextAnimation(type: .fadeIn, duration: 0.4)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002003")!,
                name: "Lower Third",
                content: TextClipContent(
                    text: "Name\nDescription",
                    fontFamily: "Avenir Next",
                    fontSize: 44,
                    fontColor: "#FFFFFF",
                    alignment: .leading,
                    backgroundColor: "#111111",
                    position: CGPoint(x: 360, y: 820),
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 2, y: 2),
                    shadowBlur: 4,
                    isBold: true
                ),
                animation: TextAnimation(preset: .slideInLeft, duration: 0.55)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002004")!,
                name: "Caption",
                content: TextClipContent(
                    text: "Caption",
                    fontFamily: "SF Pro",
                    fontSize: 44,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    backgroundColor: "#000000",
                    position: CGPoint(x: 960, y: 860)
                ),
                animation: TextAnimation(type: .fadeIn, duration: 0.3)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002005")!,
                name: "Credits",
                content: TextClipContent(
                    text: "Credits",
                    fontFamily: "Helvetica Neue",
                    fontSize: 48,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 980)
                ),
                animation: TextAnimation(preset: .slideInUp, duration: 2.0)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002006")!,
                name: "News Banner",
                content: TextClipContent(
                    text: "Breaking News",
                    fontFamily: "Helvetica Neue",
                    fontSize: 48,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    backgroundColor: "#B00020",
                    position: CGPoint(x: 960, y: 118),
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 2, y: 2),
                    shadowBlur: 3,
                    isBold: true
                ),
                animation: TextAnimation(preset: .slideInDown, duration: 0.45)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002007")!,
                name: "Quote",
                content: TextClipContent(
                    text: "\"A quote worth sharing\"",
                    fontFamily: "Georgia",
                    fontSize: 58,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 540),
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 3, y: 3),
                    shadowBlur: 6,
                    isItalic: true
                ),
                animation: TextAnimation(preset: .fadeInOut, duration: 0.7)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002008")!,
                name: "Callout",
                content: TextClipContent(
                    text: "Callout ->",
                    fontFamily: "SF Pro Rounded",
                    fontSize: 46,
                    fontColor: "#111111",
                    alignment: .leading,
                    backgroundColor: "#FFD447",
                    position: CGPoint(x: 420, y: 360),
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 3, y: 3),
                    shadowBlur: 5,
                    isBold: true
                ),
                animation: TextAnimation(preset: .popIn, duration: 0.35)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002009")!,
                name: "Kinetic",
                content: TextClipContent(
                    text: "KINETIC",
                    fontFamily: "Futura",
                    fontSize: 94,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 540),
                    strokeColor: "#111111",
                    strokeWidth: 4,
                    shadowColor: "#FF3B30",
                    shadowOffset: CGPoint(x: 4, y: 4),
                    shadowBlur: 4,
                    isBold: true
                ),
                animation: TextAnimation(preset: .bounceIn, duration: 0.65)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002010")!,
                name: "Handwritten",
                content: TextClipContent(
                    text: "Handwritten",
                    fontFamily: "Snell Roundhand",
                    fontSize: 74,
                    fontColor: "#FFF0D6",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 610),
                    shadowColor: "#3A2415",
                    shadowOffset: CGPoint(x: 2, y: 3),
                    shadowBlur: 4,
                    isItalic: true
                ),
                animation: TextAnimation(preset: .wave, duration: 1.0)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002011")!,
                name: "Neon Glow",
                content: TextClipContent(
                    text: "NEON",
                    fontFamily: "Helvetica Neue",
                    fontSize: 86,
                    fontColor: "#36D7FF",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 540),
                    strokeColor: "#FFFFFF",
                    strokeWidth: 1.5,
                    shadowColor: "#FF2BD6",
                    shadowOffset: CGPoint(x: 0, y: 0),
                    shadowBlur: 14,
                    isBold: true
                ),
                animation: TextAnimation(preset: .fadeInOut, duration: 0.65)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002012")!,
                name: "Outline",
                content: TextClipContent(
                    text: "OUTLINE",
                    fontFamily: "Helvetica Neue",
                    fontSize: 86,
                    fontColor: "#0F0F10",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 540),
                    strokeColor: "#FFFFFF",
                    strokeWidth: 5,
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 2, y: 2),
                    shadowBlur: 3,
                    isBold: true
                ),
                animation: TextAnimation(preset: .zoomIn, duration: 0.45)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002013")!,
                name: "Typewriter",
                content: TextClipContent(
                    text: "typing...",
                    fontFamily: "Menlo",
                    fontSize: 52,
                    fontColor: "#F5F5F5",
                    alignment: .leading,
                    backgroundColor: "#111111",
                    position: CGPoint(x: 420, y: 600),
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 2, y: 2),
                    shadowBlur: 3
                ),
                animation: TextAnimation(preset: .typewriter, duration: 1.2)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002014")!,
                name: "Social Handle",
                content: TextClipContent(
                    text: "@username",
                    fontFamily: "Avenir Next",
                    fontSize: 48,
                    fontColor: "#FFFFFF",
                    alignment: .leading,
                    backgroundColor: "#1DA1F2",
                    position: CGPoint(x: 420, y: 900),
                    shadowColor: "#000000",
                    shadowOffset: CGPoint(x: 2, y: 2),
                    shadowBlur: 4,
                    isBold: true
                ),
                animation: TextAnimation(preset: .slideInLeft, duration: 0.5)
            )
        ]
    }
}
