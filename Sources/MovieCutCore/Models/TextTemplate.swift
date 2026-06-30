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
                    fontSize: 96,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 540)
                ),
                animation: TextAnimation(type: .fadeIn, duration: 0.6)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002002")!,
                name: "Subtitle",
                content: TextClipContent(
                    text: "Subtitle",
                    fontSize: 36,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 920)
                ),
                animation: TextAnimation(type: .fadeIn, duration: 0.4)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002003")!,
                name: "Lower Third",
                content: TextClipContent(
                    text: "Name\nDescription",
                    fontSize: 42,
                    fontColor: "#FFFFFF",
                    alignment: .leading,
                    backgroundColor: "#111111CC",
                    position: CGPoint(x: 160, y: 820)
                ),
                animation: TextAnimation(preset: .slideInUp, duration: 0.5)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002004")!,
                name: "Caption",
                content: TextClipContent(
                    text: "Caption",
                    fontSize: 44,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    backgroundColor: "#00000099",
                    position: CGPoint(x: 960, y: 860)
                ),
                animation: TextAnimation(type: .fadeIn, duration: 0.3)
            ),
            TextTemplate(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000002005")!,
                name: "Credits",
                content: TextClipContent(
                    text: "Credits",
                    fontSize: 48,
                    fontColor: "#FFFFFF",
                    alignment: .center,
                    position: CGPoint(x: 960, y: 980)
                ),
                animation: TextAnimation(preset: .slideInUp, duration: 2.0)
            )
        ]
    }
}
