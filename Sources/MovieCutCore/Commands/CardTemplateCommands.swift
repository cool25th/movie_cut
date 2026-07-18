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

    public func apply(to project: inout Project) throws -> CommandResult {
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
        project.cardDocument = resolved
        return CommandResult(
            description: "Applied card template \(template.name)",
            undoValues: ["cardDocument": .cardDocument(previousDocument)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RestoreTemplateCardDocumentCommand.from(
            result: result,
            fallbackDescription: "Restored card document before template application"
        )
    }
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

    public func apply(to project: inout Project) throws -> CommandResult {
        guard let previousDocument = project.cardDocument else {
            throw EditorCommandError.cardDocumentMissing
        }
        try CardTemplateResolver.validateResolvedDocument(previousDocument)
        let resolved = try CardTemplateResolver.applyingMasterStyle(masterStyle, to: previousDocument)
        guard resolved != previousDocument else {
            throw EditorCommandError.invalidCommand("Card document already uses the requested master style.")
        }
        project.cardDocument = resolved
        return CommandResult(
            description: "Updated card master style",
            undoValues: ["cardDocument": .cardDocument(previousDocument)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RestoreTemplateCardDocumentCommand.from(
            result: result,
            fallbackDescription: "Restored previous card master style"
        )
    }
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

    func apply(to project: inout Project) throws -> CommandResult {
        let previousDocument = project.cardDocument
        project.cardDocument = document
        return CommandResult(
            description: restoreDescription,
            undoValues: ["cardDocument": .cardDocument(previousDocument)]
        )
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        Self.from(result: result, fallbackDescription: "Restored card template snapshot")
    }

    static func from(result: CommandResult, fallbackDescription: String) -> any EditorCommand {
        guard case .cardDocument(let document)? = result.undoValues["cardDocument"] else {
            return NoOpCommand(description: "Missing card template snapshot for inverse")
        }
        return RestoreTemplateCardDocumentCommand(
            document: document,
            description: fallbackDescription
        )
    }
}
