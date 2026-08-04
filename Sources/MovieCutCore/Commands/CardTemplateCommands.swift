import Foundation

/// Replaces a card document's pages and master style with one resolved template
/// as a single EditorSession snapshot.
public struct ApplyCardTemplateCommand: EditorCommand {
    public let id: UUID
    public let template: CardTemplateSet
    public let seed: UInt64

    public init(id: UUID = UUID(), template: CardTemplateSet, seed: UInt64) {
        self.id = id
        self.template = template
        self.seed = seed
    }

    public func apply(to project: inout Project) throws {
        guard let previousDocument = project.cardDocument else {
            throw EditorCommandError.cardDocumentMissing
        }
        try CardTemplateResolver.validateResolvedDocument(previousDocument)
        let resolved = try CardTemplateResolver.instantiate(
            template,
            title: previousDocument.title,
            format: previousDocument.format,
            documentID: previousDocument.id,
            documentMasterStyle: nil,
            seed: seed
        )
        project.cardDocument = resolved    }

    }

/// Updates the document master and propagates inherited values while preserving
/// page-local overrides, as one EditorSession snapshot.
public struct SetCardMasterStyleCommand: EditorCommand {
    public let id: UUID
    public let masterStyle: CardMasterStyle

    public init(id: UUID = UUID(), masterStyle: CardMasterStyle) {
        self.id = id
        self.masterStyle = masterStyle
    }

    public func apply(to project: inout Project) throws {
        guard let previousDocument = project.cardDocument else {
            throw EditorCommandError.cardDocumentMissing
        }
        try CardTemplateResolver.validateResolvedDocument(previousDocument)
        let resolved = try CardTemplateResolver.applyingMasterStyle(masterStyle, to: previousDocument)
        guard resolved != previousDocument else {
            throw EditorCommandError.invalidCommand("Card document already uses the requested master style.")
        }
        project.cardDocument = resolved    }

    }

private struct RestoreTemplateCardDocumentCommand: EditorCommand {
    let id: UUID
    let document: CardDocument?
    let restoreDescription: String

    init(id: UUID = UUID(), document: CardDocument?, description: String) {
        self.id = id
        self.document = document
        self.restoreDescription = description
    }

    func apply(to project: inout Project) throws {
        project.cardDocument = document
    }
}
