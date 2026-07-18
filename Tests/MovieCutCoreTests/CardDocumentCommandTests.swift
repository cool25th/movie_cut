import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

@Suite("Card document commands")
struct CardDocumentCommandTests {
    @Test("Card document model round trip preserves the published schema")
    func modelCodableRoundTrip() throws {
        let project = makeProject(format: .story, masterStyle: CardMasterStyle(
            fontFamily: "Avenir Next",
            primaryColorHex: "#112233",
            secondaryColorHex: "#DDEEFF",
            logoPlacement: frame(x: 0.72, y: 0.05, width: 0.2, height: 0.1)
        ))

        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))

        #expect(decoded == project)
        #expect(decoded.cardDocument?.format == .story)
        #expect(decoded.cardDocument?.masterStyle == project.cardDocument?.masterStyle)
    }

    @Test("Pre-card legacy fixture decodes nil card document without changing timeline or export data")
    func preCardLegacyFixturePreservesTimelineAndExport() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/project_pre_card_v1.json")
        let decoded = try JSONDecoder().decode(Project.self, from: Data(contentsOf: fixtureURL))
        let expectedTrack = Track(
            id: uuid("10000000-0000-4000-8000-000000000003"),
            kind: .video,
            name: "Legacy Video",
            isLocked: true,
            zIndex: 3
        )
        let expectedTimeline = Timeline(
            id: uuid("10000000-0000-4000-8000-000000000002"),
            frameRate: Rational(numerator: 24, denominator: 1),
            canvasSize: CGSize(width: 1080, height: 1920),
            aspectRatio: .portrait9x16,
            tracks: [expectedTrack]
        )
        let expectedExport = ExportSettings(
            resolution: .p4K,
            frameRate: .fps24,
            codec: .hevc,
            audioCodec: .pcm,
            containerFormat: .mov,
            quality: .custom,
            videoBitrateMbps: 42,
            includeChapters: false,
            includeBeatChapters: true
        )

        #expect(decoded.cardDocument == nil)
        #expect(decoded.timeline == expectedTimeline)
        #expect(decoded.exportSettings == expectedExport)
        #expect(decoded.canvas == CanvasPreset(aspectRatio: .portrait9x16, frameRate: .fps24))
    }

    @Test("Card editor bootstrap fixture decodes deterministic pages and normalized elements")
    func cardEditorBootstrapFixtureDecodes() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/card_editor_bootstrap.moviecut")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Project.self, from: Data(contentsOf: fixtureURL))

        #expect(decoded.cardDocument?.title == "Summer Launch")
        #expect(decoded.cardDocument?.format == .square)
        #expect(decoded.cardDocument?.pages.count == 3)
        #expect(decoded.cardDocument?.pages.flatMap(\.elements).count == 6)
        #expect(decoded.cardDocument?.pages[1].elements[0].normalizedFrame == frame(x: 0.09, y: 0.1, width: 0.82, height: 0.18))
    }

    @Test("Legacy card document without format defaults to square")
    func legacyCardDocumentDefaultsToSquare() throws {
        let data = """
        {
          "id": "20000000-0000-4000-8000-000000000001",
          "title": "Legacy cards",
          "pages": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CardDocument.self, from: data)

        #expect(decoded.format == .square)
        #expect(decoded.pages.isEmpty)
        #expect(decoded.masterStyle == nil)
    }

    @Test("Normalized geometry rejects out-of-bounds construction and decoding")
    func normalizedGeometryFailsClosed() throws {
        #expect(NormalizedRect(x: -0.01, y: 0, width: 0.5, height: 0.5) == nil)
        #expect(NormalizedRect(x: 0.8, y: 0, width: 0.3, height: 0.5) == nil)
        #expect(NormalizedRect(x: 0, y: 0, width: .infinity, height: 0.5) == nil)

        let invalidJSON = """
        {"x":0.8,"y":0.1,"width":0.3,"height":0.5}
        """.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(NormalizedRect.self, from: invalidJSON)
        }
    }

    @Test("Add page honors insertion index and preserves unaffected IDs")
    func addPagePreservesOrderAndIds() throws {
        var project = makeProject()
        let originalIds = project.cardDocument!.pages.map(\.id)
        let added = CardPage(id: uuid("30000000-0000-4000-8000-000000000004"), role: .closing)

        _ = try AddCardPageCommand(page: added, insertionIndex: 1).apply(to: &project)

        #expect(project.cardDocument?.pages.map(\.id) == [originalIds[0], added.id, originalIds[1], originalIds[2]])
        #expect(project.cardDocument?.pages[0].elements.map(\.id) == makeProject().cardDocument?.pages[0].elements.map(\.id))
    }

    @Test("Duplicate creates deterministic fresh page and element IDs while preserving content")
    func duplicatePageCreatesFreshStableIds() throws {
        let sourceProject = makeProject()
        let source = sourceProject.cardDocument!.pages[1]
        let duplicatePageId = uuid("40000000-0000-4000-8000-000000000001")
        let command = DuplicateCardPageCommand(pageId: source.id, duplicatePageId: duplicatePageId)
        var firstProject = sourceProject
        var secondProject = sourceProject

        _ = try command.apply(to: &firstProject)
        _ = try command.apply(to: &secondProject)

        let duplicate = firstProject.cardDocument!.pages[2]
        let secondDuplicate = secondProject.cardDocument!.pages[2]
        #expect(firstProject.cardDocument?.pages.map(\.id) == [
            sourceProject.cardDocument!.pages[0].id,
            source.id,
            duplicatePageId,
            sourceProject.cardDocument!.pages[2].id
        ])
        #expect(duplicate.id == duplicatePageId)
        #expect(duplicate.id != source.id)
        #expect(duplicate.elements.map(\.id) == secondDuplicate.elements.map(\.id))
        #expect(Set(duplicate.elements.map(\.id)).isDisjoint(with: source.elements.map(\.id)))
        #expect(duplicate.elements.map(\.kind) == source.elements.map(\.kind))
        #expect(duplicate.elements.map(\.normalizedFrame) == source.elements.map(\.normalizedFrame))
        #expect(duplicate.elements.map(\.text) == source.elements.map(\.text))
        #expect(duplicate.elements.map(\.mediaAssetID) == source.elements.map(\.mediaAssetID))
        #expect(duplicate.role == source.role)
        #expect(duplicate.duration == source.duration)
    }

    @Test("Delete removes only the target and preserves deterministic order")
    func deletePagePreservesSurvivors() throws {
        var project = makeProject()
        let original = project.cardDocument!.pages

        _ = try DeleteCardPageCommand(pageId: original[1].id).apply(to: &project)

        #expect(project.cardDocument?.pages == [original[0], original[2]])
    }

    @Test("Move uses a final array index and retains page values")
    func movePageUsesFinalIndex() throws {
        var project = makeProject()
        let original = project.cardDocument!.pages

        _ = try MoveCardPageCommand(pageId: original[0].id, destinationIndex: 2).apply(to: &project)

        #expect(project.cardDocument?.pages == [original[1], original[2], original[0]])
        #expect(project.cardDocument?.pages[2].elements[0].normalizedFrame == original[0].elements[0].normalizedFrame)
    }

    @Test("Format change preserves normalized layout and stable identifiers")
    func formatChangePreservesLayoutAndIds() async throws {
        let initial = makeProject(format: .square)
        let originalPages = initial.cardDocument!.pages
        let session = EditorSession(project: initial)

        try await session.dispatch(SetCardFormatCommand(format: .story))
        let changed = await session.snapshot()

        #expect(changed.cardDocument?.format == .story)
        #expect(changed.cardDocument?.pages == originalPages)
        #expect(changed.cardDocument?.pages.map(\.id) == originalPages.map(\.id))
        #expect(changed.cardDocument?.pages.flatMap(\.elements).map(\.id) == originalPages.flatMap(\.elements).map(\.id))
        #expect(changed.cardDocument?.pages.flatMap(\.elements).map(\.normalizedFrame) == originalPages.flatMap(\.elements).map(\.normalizedFrame))

        try await session.undo()
        #expect(await session.snapshot() == initial)
        try await session.redo()
        #expect(await session.snapshot() == changed)
    }

    @Test("Update replaces element content and geometry without changing its ID")
    func updateElementPreservesStableId() throws {
        var project = makeProject()
        let page = project.cardDocument!.pages[1]
        let original = page.elements[0]
        let updated = CardElement(
            id: original.id,
            kind: .text,
            normalizedFrame: frame(x: 0.12, y: 0.3, width: 0.76, height: 0.2),
            text: TextClipContent(text: "Updated inline text", fontColor: "#ABCDEF")
        )

        _ = try UpdateCardElementCommand(
            pageId: page.id,
            elementId: original.id,
            element: updated
        ).apply(to: &project)

        #expect(project.cardDocument?.pages[1].elements[0] == updated)
        #expect(project.cardDocument?.pages[1].elements[0].id == original.id)
    }

    @Test("Every page and element operation is exactly one undo and redo snapshot")
    func operationsUndoRedoInSingleStep() async throws {
        let initial = makeProject()
        let pages = initial.cardDocument!.pages
        let sourceElement = pages[1].elements[0]
        let updated = CardElement(
            id: sourceElement.id,
            kind: .text,
            normalizedFrame: frame(x: 0.2, y: 0.2, width: 0.6, height: 0.25),
            text: TextClipContent(text: "Undo me")
        )
        let operations: [any EditorCommand] = [
            AddCardPageCommand(
                page: CardPage(id: uuid("50000000-0000-4000-8000-000000000001"), role: .closing),
                insertionIndex: 1
            ),
            DuplicateCardPageCommand(
                pageId: pages[1].id,
                duplicatePageId: uuid("50000000-0000-4000-8000-000000000002")
            ),
            DeleteCardPageCommand(pageId: pages[1].id),
            MoveCardPageCommand(pageId: pages[0].id, destinationIndex: 2),
            SetCardFormatCommand(format: .story),
            UpdateCardElementCommand(pageId: pages[1].id, elementId: sourceElement.id, element: updated)
        ]

        for operation in operations {
            let session = EditorSession(project: initial)
            try await session.dispatch(operation)
            let applied = await session.snapshot()
            #expect(applied != initial)

            try await session.undo()
            #expect(await session.snapshot() == initial)

            try await session.redo()
            #expect(await session.snapshot() == applied)
        }
    }

    @Test("All card commands reject a missing card document without mutation")
    func missingDocumentFailsClosed() throws {
        let page = makeProject().cardDocument!.pages[0]
        let element = page.elements[0]
        let commands: [any EditorCommand] = [
            AddCardPageCommand(page: CardPage(role: .body)),
            DuplicateCardPageCommand(pageId: page.id),
            DeleteCardPageCommand(pageId: page.id),
            MoveCardPageCommand(pageId: page.id, destinationIndex: 0),
            SetCardFormatCommand(format: .story),
            UpdateCardElementCommand(pageId: page.id, elementId: element.id, element: element)
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

    @Test("Missing pages and elements report domain errors without mutation")
    func missingPageAndElementFailClosed() throws {
        let missingPageId = uuid("60000000-0000-4000-8000-000000000001")
        let missingElementId = uuid("60000000-0000-4000-8000-000000000002")
        var project = makeProject()
        let initial = project
        let existingPage = project.cardDocument!.pages[0]
        let existingElement = existingPage.elements[0]

        #expect(throws: EditorCommandError.cardPageNotFound(missingPageId)) {
            _ = try DuplicateCardPageCommand(pageId: missingPageId).apply(to: &project)
        }
        #expect(project == initial)
        #expect(throws: EditorCommandError.cardPageNotFound(missingPageId)) {
            _ = try UpdateCardElementCommand(
                pageId: missingPageId,
                elementId: existingElement.id,
                element: existingElement
            ).apply(to: &project)
        }
        #expect(project == initial)
        #expect(throws: EditorCommandError.cardElementNotFound(missingElementId)) {
            _ = try UpdateCardElementCommand(
                pageId: existingPage.id,
                elementId: missingElementId,
                element: existingElement
            ).apply(to: &project)
        }
        #expect(project == initial)
    }

    @Test("Invalid add and move indices fail closed")
    func invalidIndicesFailClosed() throws {
        let added = CardPage(role: .body)
        for invalidIndex in [-1, 4] {
            var project = makeProject()
            let initial = project
            #expect(throws: EditorCommandError.self) {
                _ = try AddCardPageCommand(page: added, insertionIndex: invalidIndex).apply(to: &project)
            }
            #expect(project == initial)
        }

        for invalidIndex in [-1, 3] {
            var project = makeProject()
            let initial = project
            let pageId = project.cardDocument!.pages[0].id
            #expect(throws: EditorCommandError.self) {
                _ = try MoveCardPageCommand(pageId: pageId, destinationIndex: invalidIndex).apply(to: &project)
            }
            #expect(project == initial)
        }

        var sameIndexProject = makeProject()
        let sameIndexInitial = sameIndexProject
        let middlePageId = sameIndexProject.cardDocument!.pages[1].id
        #expect(throws: EditorCommandError.self) {
            _ = try MoveCardPageCommand(pageId: middlePageId, destinationIndex: 1).apply(to: &sameIndexProject)
        }
        #expect(sameIndexProject == sameIndexInitial)
    }

    @Test("Deleting the final page is rejected and leaves the document intact")
    func lastPageCannotBeDeleted() throws {
        var project = makeProject()
        let onlyPage = project.cardDocument!.pages[0]
        project.cardDocument!.pages = [onlyPage]
        let initial = project

        #expect(throws: EditorCommandError.self) {
            _ = try DeleteCardPageCommand(pageId: onlyPage.id).apply(to: &project)
        }
        #expect(project == initial)
    }

    @Test("Duplicate IDs, invalid duration, and element ID replacement fail closed")
    func invalidValuesFailClosed() throws {
        var duplicatePageProject = makeProject()
        let duplicatePageInitial = duplicatePageProject
        let existingPage = duplicatePageProject.cardDocument!.pages[0]
        #expect(throws: EditorCommandError.self) {
            _ = try AddCardPageCommand(page: existingPage).apply(to: &duplicatePageProject)
        }
        #expect(duplicatePageProject == duplicatePageInitial)

        var invalidDurationProject = makeProject()
        let invalidDurationInitial = invalidDurationProject
        let invalidDurationPage = CardPage(role: .body, duration: .nan)
        #expect(throws: EditorCommandError.self) {
            _ = try AddCardPageCommand(page: invalidDurationPage).apply(to: &invalidDurationProject)
        }
        #expect(invalidDurationProject == invalidDurationInitial)

        var changedIdProject = makeProject()
        let changedIdInitial = changedIdProject
        let page = changedIdProject.cardDocument!.pages[0]
        let element = page.elements[0]
        var changedIdElement = element
        changedIdElement.id = UUID()
        #expect(throws: EditorCommandError.self) {
            _ = try UpdateCardElementCommand(
                pageId: page.id,
                elementId: element.id,
                element: changedIdElement
            ).apply(to: &changedIdProject)
        }
        #expect(changedIdProject == changedIdInitial)
    }

    private func makeProject(
        format: CardFormat = .portrait,
        masterStyle: CardMasterStyle? = nil
    ) -> Project {
        let mediaId = uuid("70000000-0000-4000-8000-000000000001")
        let pages = [
            CardPage(
                id: uuid("71000000-0000-4000-8000-000000000001"),
                role: .cover,
                elements: [
                    CardElement(
                        id: uuid("72000000-0000-4000-8000-000000000001"),
                        kind: .text,
                        normalizedFrame: frame(x: 0.1, y: 0.15, width: 0.8, height: 0.2),
                        text: TextClipContent(text: "Cover")
                    )
                ]
            ),
            CardPage(
                id: uuid("71000000-0000-4000-8000-000000000002"),
                role: .body,
                elements: [
                    CardElement(
                        id: uuid("72000000-0000-4000-8000-000000000002"),
                        kind: .text,
                        normalizedFrame: frame(x: 0.08, y: 0.12, width: 0.84, height: 0.18),
                        text: TextClipContent(text: "Body")
                    ),
                    CardElement(
                        id: uuid("72000000-0000-4000-8000-000000000003"),
                        kind: .image,
                        normalizedFrame: frame(x: 0.1, y: 0.38, width: 0.8, height: 0.5),
                        mediaAssetID: mediaId
                    )
                ],
                duration: 4
            ),
            CardPage(
                id: uuid("71000000-0000-4000-8000-000000000003"),
                role: .closing,
                elements: [
                    CardElement(
                        id: uuid("72000000-0000-4000-8000-000000000004"),
                        kind: .logo,
                        normalizedFrame: frame(x: 0.35, y: 0.8, width: 0.3, height: 0.1),
                        mediaAssetID: mediaId
                    )
                ]
            )
        ]
        let asset = MediaAsset(
            id: mediaId,
            originalURL: URL(fileURLWithPath: "/tmp/card-image.png"),
            kind: .image,
            metadata: MediaMetadata(width: 1080, height: 1350)
        )
        return Project(
            id: uuid("73000000-0000-4000-8000-000000000001"),
            name: "Card command tests",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            mediaLibrary: MediaLibrary(assets: [mediaId: asset]),
            timeline: Timeline(tracks: [Track(kind: .video, name: "Unaffected timeline")]),
            exportSettings: ExportSettings(resolution: .p4K, frameRate: .fps24, codec: .hevc),
            cardDocument: CardDocument(
                id: uuid("74000000-0000-4000-8000-000000000001"),
                title: "Campaign",
                format: format,
                pages: pages,
                masterStyle: masterStyle
            )
        )
    }

    private func frame(x: Double, y: Double, width: Double, height: Double) -> NormalizedRect {
        NormalizedRect(x: x, y: y, width: width, height: height)!
    }

    private func uuid(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}
