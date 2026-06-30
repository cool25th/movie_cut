import Foundation
import Testing
import MovieCutCore

@Suite("Text Template Library")
struct TextTemplateLibraryTests {
    @Test("Built-in library includes CapCut-style title categories")
    func builtInLibraryIncludesAdvancedTitleTemplates() {
        let templates = MovieCutCore.TextTemplate.builtIn
        let names = Set(templates.map(\.name))

        #expect(templates.count >= 12)
        #expect(names.isSuperset(of: [
            "Title",
            "Subtitle",
            "Lower Third",
            "News Banner",
            "Quote",
            "Callout",
            "Kinetic",
            "Handwritten",
            "Neon Glow",
            "Outline",
            "Typewriter",
            "Social Handle"
        ]))
    }

    @Test("Built-in templates carry complete style and animation settings")
    func builtInTemplatesCarryRenderableStyleSettings() {
        let templates = MovieCutCore.TextTemplate.builtIn
        let ids = Set(templates.map(\.id))

        #expect(ids.count == templates.count)

        for template in templates {
            #expect(!template.name.isEmpty)
            #expect(!template.content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!template.content.fontFamily.isEmpty)
            #expect(template.content.fontSize > 0)
            #expect(isHexRGB(template.content.fontColor))
            #expect(template.animation != nil || template.content.animation != nil)

            if let backgroundColor = template.content.backgroundColor {
                #expect(isHexRGB(backgroundColor))
            }

            if let strokeColor = template.content.strokeColor {
                #expect(isHexRGB(strokeColor))
                #expect((template.content.strokeWidth ?? 0) > 0)
            }

            if let shadowColor = template.content.shadowColor {
                #expect(isHexRGB(shadowColor))
                #expect((template.content.shadowBlur ?? 0) >= 0)
            }
        }
    }

    @Test("Specialized templates use expected CapCut-style effects")
    func specializedTemplatesUseExpectedEffects() throws {
        let templates = Dictionary(uniqueKeysWithValues: MovieCutCore.TextTemplate.builtIn.map { ($0.name, $0) })

        let kinetic = try #require(templates["Kinetic"])
        #expect(kinetic.content.isBold)
        #expect(kinetic.animation?.preset == .bounceIn)

        let handwritten = try #require(templates["Handwritten"])
        #expect(handwritten.content.isItalic)
        #expect(handwritten.animation?.preset == .wave)

        let neon = try #require(templates["Neon Glow"])
        #expect(neon.content.shadowColor != nil)
        #expect((neon.content.shadowBlur ?? 0) >= 10)

        let outline = try #require(templates["Outline"])
        #expect(outline.content.strokeColor != nil)
        #expect((outline.content.strokeWidth ?? 0) >= 4)

        let typewriter = try #require(templates["Typewriter"])
        #expect(typewriter.content.fontFamily == "Menlo")
        #expect(typewriter.animation?.preset == .typewriter)
    }

    private func isHexRGB(_ value: String) -> Bool {
        let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return clean.count == 6 && UInt64(clean, radix: 16) != nil
    }
}
