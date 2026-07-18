import Foundation
import Testing
@testable import MovieCutCore

@Suite("Card Template Resolver and Commands")
struct CardTemplateTests {
    @Test("Resolver creates five filled pages with all semantic roles and fresh IDs")
    func resolverCreatesFiveFilledPages() throws {
        let template = makeTemplate()
        let resolved = try CardTemplateResolver.instantiate(template, seed: 19)

        #expect(resolved.pages.count == 5)
        #expect(resolved.pages.map(\.role) == [.cover, .body, .body, .emphasis, .closing])
        #expect(Set(resolved.pages.map(\.role)) == Set([.cover, .body, .emphasis, .closing]))
        #expect(CardTemplateResolver.emptyRequiredSlotCount(in: resolved.pages) == 0)
        #expect(Set(resolved.pages.map(\.id)).count == 5)
        #expect(Set(resolved.pages.flatMap(\.elements).map(\.id)).count == resolved.pages.flatMap(\.elements).count)
        #expect(Set(resolved.pages.flatMap(\.elements).map(\.id)).isDisjoint(
            with: template.pages.flatMap(\.elements).map(\.id)
        ))
    }

    @Test("Resolver IDs are deterministic for a seed and change with a different seed")
    func deterministicIDs() throws {
        let template = makeTemplate()
        let first = try CardTemplateResolver.instantiate(template, seed: 42)
        let second = try CardTemplateResolver.instantiate(template, seed: 42)
        let different = try CardTemplateResolver.instantiate(template, seed: 43)

        #expect(first == second)
        #expect(first.id != different.id)
        #expect(first.pages.map(\.id) != different.pages.map(\.id))
        #expect(first.pages.flatMap(\.elements).map(\.id) != different.pages.flatMap(\.elements).map(\.id))
    }

    @Test("Style resolution honors page override then document master then template default")
    func styleOverridePriority() throws {
        let template = makeTemplate(includeCoverOverride: true)
        let documentStyle = style(
            font: "Document Font",
            primary: "#123456",
            secondary: "#654321",
            logo: frame(0.6, 0.04, 0.3, 0.1)
        )
        let resolved = try CardTemplateResolver.instantiate(
            template,
            documentMasterStyle: documentStyle,
            seed: 7
        )
        let coverText = try #require(resolved.pages[0].elements.first(where: { $0.kind == .text })?.text)
        let bodyText = try #require(resolved.pages[1].elements.first(where: { $0.kind == .text })?.text)
        let coverLogo = try #require(resolved.pages[0].elements.first(where: { $0.kind == .logo }))
        let override = try #require(template.pages[0].masterOverride)

        #expect(coverText.fontFamily == override.fontFamily)
        #expect(coverText.fontColor == override.primaryColorHex)
        #expect(coverLogo.normalizedFrame == override.logoPlacement)
        #expect(bodyText.fontFamily == documentStyle.fontFamily)
        #expect(bodyText.fontColor == documentStyle.primaryColorHex)
        #expect(CardTemplateResolver.effectiveMasterStyle(
            pageOverride: nil,
            documentMasterStyle: nil,
            templateDefaultMasterStyle: template.defaultMasterStyle
        ) == template.defaultMasterStyle)
    }

    @Test("Legacy card decode without master or page override uses the template default")
    func legacyDecodeUsesTemplateDefault() throws {
        let legacy = """
        {
          "id":"90000000-0000-4000-8000-000000000001",
          "title":"Legacy Card",
          "format":"portrait",
          "pages":[{
            "id":"90000000-0000-4000-8000-000000000002",
            "role":"body",
            "elements":[]
          }]
        }
        """
        let decoded = try JSONDecoder().decode(CardDocument.self, from: Data(legacy.utf8))
        let template = makeTemplate()
        let resolved = try CardTemplateResolver.instantiate(
            template,
            title: decoded.title,
            format: decoded.format,
            documentID: decoded.id,
            documentMasterStyle: decoded.masterStyle,
            seed: 11
        )

        #expect(decoded.masterStyle == nil)
        #expect(decoded.pages[0].masterOverride == nil)
        #expect(resolved.masterStyle == template.defaultMasterStyle)
        #expect(resolved.pages.flatMap(\.elements).filter { $0.kind == .text }.allSatisfy {
            $0.text?.fontFamily == template.defaultMasterStyle.fontFamily
                && $0.text?.fontColor == template.defaultMasterStyle.primaryColorHex
        })
    }

    @Test("Template application is one exact undo and redo snapshot")
    func applyTemplateUndoRedo() async throws {
        let initial = makeProject()
        let session = EditorSession(project: initial)

        try await session.dispatch(ApplyCardTemplateCommand(template: makeTemplate(), seed: 91))
        let applied = await session.snapshot()
        #expect(applied.cardDocument?.pages.count == 5)
        #expect(applied.cardDocument?.masterStyle == makeTemplate().defaultMasterStyle)

        try await session.undo()
        #expect(await session.snapshot() == initial)
        try await session.redo()
        #expect(await session.snapshot() == applied)
    }

    @Test("Master style propagation is one exact undo and redo snapshot and preserves page override")
    func masterStyleUndoRedo() async throws {
        let template = makeTemplate(includeCoverOverride: true)
        let resolved = try CardTemplateResolver.instantiate(template, seed: 31)
        let initial = makeProject(document: resolved)
        let session = EditorSession(project: initial)
        let changed = style(
            font: "Changed Font",
            primary: "#0A0B0C",
            secondary: "#F0E0D0",
            logo: frame(0.73, 0.07, 0.2, 0.08)
        )

        try await session.dispatch(SetCardMasterStyleCommand(masterStyle: changed))
        let applied = await session.snapshot()
        let coverOverride = try #require(template.pages[0].masterOverride)
        let coverText = try #require(applied.cardDocument?.pages[0].elements.first(where: { $0.kind == .text })?.text)
        let bodyText = try #require(applied.cardDocument?.pages[1].elements.first(where: { $0.kind == .text })?.text)
        let closingLogo = try #require(applied.cardDocument?.pages[4].elements.first(where: { $0.kind == .logo }))

        #expect(applied.cardDocument?.masterStyle == changed)
        #expect(coverText.fontFamily == coverOverride.fontFamily)
        #expect(coverText.fontColor == coverOverride.primaryColorHex)
        #expect(bodyText.fontFamily == changed.fontFamily)
        #expect(bodyText.fontColor == changed.primaryColorHex)
        #expect(closingLogo.normalizedFrame == changed.logoPlacement)

        try await session.undo()
        #expect(await session.snapshot() == initial)
        try await session.redo()
        #expect(await session.snapshot() == applied)
    }

    @Test("Empty pages and missing roles fail closed")
    func emptyPagesAndMissingRolesFailClosed() throws {
        var emptyPage = makeTemplate()
        emptyPage.pages[1].elements = []
        #expect(throws: CardTemplateError.emptyPage("body")) {
            _ = try CardTemplateResolver.instantiate(emptyPage, seed: 1)
        }

        var missingRole = makeTemplate()
        missingRole.pages.removeAll { $0.role == .closing }
        #expect(throws: CardTemplateError.missingRole(.closing)) {
            _ = try CardTemplateResolver.instantiate(missingRole, seed: 1)
        }
    }

    @Test("Duplicate page and element IDs fail closed")
    func duplicateTemplateIDsFailClosed() throws {
        var duplicatePage = makeTemplate()
        duplicatePage.pages[1].id = duplicatePage.pages[0].id
        #expect(throws: CardTemplateError.duplicatePageIdentifier("cover")) {
            try CardTemplateResolver.validate(duplicatePage)
        }

        var duplicateElement = makeTemplate()
        duplicateElement.pages[1].elements[0].id = duplicateElement.pages[0].elements[0].id
        #expect(throws: CardTemplateError.duplicateElementIdentifier(duplicateElement.pages[0].elements[0].id)) {
            try CardTemplateResolver.validate(duplicateElement)
        }
    }

    @Test("Empty text and image slots fail closed")
    func emptyRequiredSlotsFailClosed() throws {
        var emptyText = makeTemplate()
        emptyText.pages[0].elements[0].text?.text = "  "
        #expect(throws: CardTemplateError.self) {
            try CardTemplateResolver.validate(emptyText)
        }

        var emptyImage = makeTemplate()
        let bodyImage = try #require(emptyImage.pages[1].elements.firstIndex(where: { $0.kind == .image }))
        emptyImage.pages[1].elements[bodyImage].mediaAssetID = nil
        #expect(throws: CardTemplateError.self) {
            try CardTemplateResolver.validate(emptyImage)
        }
    }

    @Test("Both template commands reject timeline-only projects without mutation")
    func nonCardProjectsFailClosed() throws {
        let commands: [any EditorCommand] = [
            ApplyCardTemplateCommand(template: makeTemplate(), seed: 3),
            SetCardMasterStyleCommand(masterStyle: makeTemplate().defaultMasterStyle)
        ]
        for command in commands {
            var project = Project(name: "Timeline only")
            let initial = project
            #expect(throws: EditorCommandError.cardDocumentMissing) {
                _ = try command.apply(to: &project)
            }
            #expect(project == initial)
        }
    }

    @Test("Both template commands reject duplicate document IDs without mutation")
    func duplicateDocumentIDsFailClosed() throws {
        let commands: [any EditorCommand] = [
            ApplyCardTemplateCommand(template: makeTemplate(), seed: 3),
            SetCardMasterStyleCommand(masterStyle: makeTemplate().defaultMasterStyle)
        ]
        for command in commands {
            var project = makeProject()
            var duplicatedDocument = project.cardDocument!
            duplicatedDocument.pages[1].id = duplicatedDocument.pages[0].id
            project.cardDocument = duplicatedDocument
            let initial = project
            #expect(throws: CardTemplateError.self) {
                _ = try command.apply(to: &project)
            }
            #expect(project == initial)
        }
    }

    private func makeTemplate(includeCoverOverride: Bool = false) -> CardTemplateSet {
        let mediaID = uuid("91000000-0000-4000-8000-000000000001")
        let logoID = uuid("91000000-0000-4000-8000-000000000002")
        let defaultStyle = style(
            font: "Template Font",
            primary: "#102030",
            secondary: "#E0D0C0",
            logo: frame(0.72, 0.84, 0.2, 0.08)
        )
        let override = includeCoverOverride ? style(
            font: "Override Font",
            primary: "#AA1100",
            secondary: "#0011AA",
            logo: frame(0.05, 0.05, 0.18, 0.09)
        ) : nil
        return CardTemplateSet(
            id: "editorial-set",
            name: "Editorial Set",
            pages: [
                CardTemplatePage(
                    id: "cover",
                    role: .cover,
                    elements: [
                        element("92000000-0000-4000-8000-000000000001", .text, frame(0.1, 0.12, 0.8, 0.25), text: "Cover headline"),
                        element("92000000-0000-4000-8000-000000000002", .logo, frame(0.7, 0.84, 0.2, 0.08), mediaID: logoID)
                    ],
                    masterOverride: override
                ),
                CardTemplatePage(
                    id: "body",
                    role: .body,
                    elements: [
                        element("92000000-0000-4000-8000-000000000003", .text, frame(0.08, 0.08, 0.84, 0.2), text: "Body copy"),
                        element("92000000-0000-4000-8000-000000000004", .image, frame(0.08, 0.34, 0.84, 0.54), mediaID: mediaID)
                    ]
                ),
                CardTemplatePage(
                    id: "emphasis",
                    role: .emphasis,
                    elements: [
                        element("92000000-0000-4000-8000-000000000005", .text, frame(0.12, 0.3, 0.76, 0.32), text: "Key point")
                    ]
                ),
                CardTemplatePage(
                    id: "closing",
                    role: .closing,
                    elements: [
                        element("92000000-0000-4000-8000-000000000006", .text, frame(0.12, 0.25, 0.76, 0.2), text: "Closing message"),
                        element("92000000-0000-4000-8000-000000000007", .logo, frame(0.7, 0.84, 0.2, 0.08), mediaID: logoID)
                    ]
                )
            ],
            defaultMasterStyle: defaultStyle
        )
    }

    private func makeProject(document: CardDocument? = nil) -> Project {
        let fallbackDocument = CardDocument(
            id: uuid("93000000-0000-4000-8000-000000000001"),
            title: "Before Template",
            format: .portrait,
            pages: [
                CardPage(
                    id: uuid("93000000-0000-4000-8000-000000000002"),
                    role: .cover,
                    elements: [element(
                        "93000000-0000-4000-8000-000000000003",
                        .text,
                        frame(0.1, 0.1, 0.8, 0.2),
                        text: "Original"
                    )]
                ),
                CardPage(
                    id: uuid("93000000-0000-4000-8000-000000000004"),
                    role: .closing,
                    elements: [element(
                        "93000000-0000-4000-8000-000000000005",
                        .text,
                        frame(0.1, 0.7, 0.8, 0.2),
                        text: "Original closing"
                    )]
                )
            ]
        )
        return Project(
            id: uuid("93000000-0000-4000-8000-000000000006"),
            name: "Card Template Tests",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            timeline: Timeline(tracks: [Track(kind: .video, name: "Unaffected")]),
            cardDocument: document ?? fallbackDocument
        )
    }

    private func style(
        font: String,
        primary: String,
        secondary: String,
        logo: NormalizedRect
    ) -> CardMasterStyle {
        CardMasterStyle(
            fontFamily: font,
            primaryColorHex: primary,
            secondaryColorHex: secondary,
            logoPlacement: logo
        )
    }

    private func element(
        _ id: String,
        _ kind: CardElementKind,
        _ frame: NormalizedRect,
        text: String? = nil,
        mediaID: UUID? = nil
    ) -> CardElement {
        CardElement(
            id: uuid(id),
            kind: kind,
            normalizedFrame: frame,
            text: text.map { TextClipContent(text: $0) },
            mediaAssetID: mediaID
        )
    }

    private func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> NormalizedRect {
        NormalizedRect(x: x, y: y, width: width, height: height)!
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
