import Foundation

/// Adds a page at a deterministic position in the card document.
public struct AddCardPageCommand: EditorCommand {
    public let id: UUID
    public let page: CardPage
    public let insertionIndex: Int?

    public init(id: UUID = UUID(), page: CardPage, insertionIndex: Int? = nil) {
        self.id = id
        self.page = page
        self.insertionIndex = insertionIndex
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        var document = try project.requiredCardDocument()
        try CardDocumentCommandValidation.validate(document)
        guard !document.pages.contains(where: { $0.id == page.id }) else {
            throw EditorCommandError.invalidCommand("Card page already exists: \(page.id)")
        }

        let index = insertionIndex ?? document.pages.endIndex
        guard index >= document.pages.startIndex, index <= document.pages.endIndex else {
            throw EditorCommandError.invalidCommand("Card page insertion index is out of bounds.")
        }

        let previousDocument = document
        document.pages.insert(page, at: index)
        try CardDocumentCommandValidation.validate(document)
        project.cardDocument = document

        return CommandResult(
            description: "Added card page \(page.id)",
            undoValues: ["cardDocument": .cardDocument(previousDocument)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RestoreCardDocumentCommand.from(result: result, fallbackDescription: "Removed added card page \(page.id)")
    }
}

/// Duplicates a page immediately after its source with stable fresh IDs.
public struct DuplicateCardPageCommand: EditorCommand {
    public let id: UUID
    public let pageId: UUID
    public let duplicatePageId: UUID

    public init(id: UUID = UUID(), pageId: UUID, duplicatePageId: UUID = UUID()) {
        self.id = id
        self.pageId = pageId
        self.duplicatePageId = duplicatePageId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        var document = try project.requiredCardDocument()
        try CardDocumentCommandValidation.validate(document)
        let sourceIndex = try document.pageIndex(for: pageId)
        guard !document.pages.contains(where: { $0.id == duplicatePageId }) else {
            throw EditorCommandError.invalidCommand("Card page already exists: \(duplicatePageId)")
        }

        let previousDocument = document
        var duplicate = document.pages[sourceIndex]
        duplicate.id = duplicatePageId
        duplicate.elements = duplicate.elements.enumerated().map { index, element in
            var copy = element
            copy.id = Self.duplicateElementId(
                pageId: duplicatePageId,
                sourceElementId: element.id,
                index: index
            )
            return copy
        }

        document.pages.insert(duplicate, at: sourceIndex + 1)
        try CardDocumentCommandValidation.validate(document)
        project.cardDocument = document

        return CommandResult(
            description: "Duplicated card page \(pageId)",
            undoValues: ["cardDocument": .cardDocument(previousDocument)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RestoreCardDocumentCommand.from(
            result: result,
            fallbackDescription: "Removed duplicated card page \(duplicatePageId)"
        )
    }

    private static func duplicateElementId(pageId: UUID, sourceElementId: UUID, index: Int) -> UUID {
        var pageUUID = pageId.uuid
        var sourceUUID = sourceElementId.uuid
        let pageBytes = withUnsafeBytes(of: &pageUUID) { Array($0) }
        let sourceBytes = withUnsafeBytes(of: &sourceUUID) { Array($0) }
        var bytes = zip(pageBytes, sourceBytes).enumerated().map { offset, pair in
            pair.0 ^ pair.1 ^ UInt8(truncatingIfNeeded: (index + 1) * (offset + 17))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Deletes a page while preserving the invariant that an established card set
/// retains at least one page.
public struct DeleteCardPageCommand: EditorCommand {
    public let id: UUID
    public let pageId: UUID

    public init(id: UUID = UUID(), pageId: UUID) {
        self.id = id
        self.pageId = pageId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        var document = try project.requiredCardDocument()
        try CardDocumentCommandValidation.validate(document)
        let pageIndex = try document.pageIndex(for: pageId)
        guard document.pages.count > 1 else {
            throw EditorCommandError.invalidCommand("The last card page cannot be deleted.")
        }

        let previousDocument = document
        document.pages.remove(at: pageIndex)
        project.cardDocument = document

        return CommandResult(
            description: "Deleted card page \(pageId)",
            undoValues: ["cardDocument": .cardDocument(previousDocument)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RestoreCardDocumentCommand.from(result: result, fallbackDescription: "Restored card page \(pageId)")
    }
}

/// Moves a page to a final index in the ordered card-page array.
public struct MoveCardPageCommand: EditorCommand {
    public let id: UUID
    public let pageId: UUID
    public let destinationIndex: Int

    public init(id: UUID = UUID(), pageId: UUID, destinationIndex: Int) {
        self.id = id
        self.pageId = pageId
        self.destinationIndex = destinationIndex
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        var document = try project.requiredCardDocument()
        try CardDocumentCommandValidation.validate(document)
        let sourceIndex = try document.pageIndex(for: pageId)
        guard document.pages.indices.contains(destinationIndex) else {
            throw EditorCommandError.invalidCommand("Card page destination index is out of bounds.")
        }
        guard destinationIndex != sourceIndex else {
            throw EditorCommandError.invalidCommand("Card page is already at the destination index.")
        }

        let previousDocument = document
        let page = document.pages.remove(at: sourceIndex)
        document.pages.insert(page, at: destinationIndex)
        project.cardDocument = document

        return CommandResult(
            description: "Moved card page \(pageId)",
            undoValues: ["cardDocument": .cardDocument(previousDocument)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RestoreCardDocumentCommand.from(result: result, fallbackDescription: "Restored card page order")
    }
}

/// Changes the document canvas format without rewriting normalized element
/// geometry or page/element identifiers.
public struct SetCardFormatCommand: EditorCommand {
    public let id: UUID
    public let format: CardFormat

    public init(id: UUID = UUID(), format: CardFormat) {
        self.id = id
        self.format = format
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        var document = try project.requiredCardDocument()
        try CardDocumentCommandValidation.validate(document)
        guard document.format != format else {
            throw EditorCommandError.invalidCommand("Card document already uses the requested format.")
        }

        let previousDocument = document
        document.format = format
        project.cardDocument = document

        return CommandResult(
            description: "Changed card format to \(format.rawValue)",
            undoValues: ["cardDocument": .cardDocument(previousDocument)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RestoreCardDocumentCommand.from(result: result, fallbackDescription: "Restored card format")
    }
}

/// Replaces one card element while retaining its stable identifier.
public struct UpdateCardElementCommand: EditorCommand {
    public let id: UUID
    public let pageId: UUID
    public let elementId: UUID
    public let element: CardElement

    public init(id: UUID = UUID(), pageId: UUID, elementId: UUID, element: CardElement) {
        self.id = id
        self.pageId = pageId
        self.elementId = elementId
        self.element = element
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        var document = try project.requiredCardDocument()
        try CardDocumentCommandValidation.validate(document)
        let pageIndex = try document.pageIndex(for: pageId)
        let elementIndex = try document.pages[pageIndex].elementIndex(for: elementId)
        guard element.id == elementId else {
            throw EditorCommandError.invalidCommand("A card element update cannot change its identifier.")
        }

        let previousDocument = document
        document.pages[pageIndex].elements[elementIndex] = element
        try CardDocumentCommandValidation.validate(document)
        project.cardDocument = document

        return CommandResult(
            description: "Updated card element \(elementId)",
            undoValues: ["cardDocument": .cardDocument(previousDocument)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RestoreCardDocumentCommand.from(result: result, fallbackDescription: "Restored card element \(elementId)")
    }
}

/// Imports or reuses one project image and points an image/logo card element at
/// it atomically. EditorSession therefore records one replacement gesture as one
/// undo/redo snapshot instead of separate import and element-update snapshots.
public struct ReplaceCardElementImageCommand: EditorCommand {
    public let id: UUID
    public let pageId: UUID
    public let elementId: UUID
    public let asset: MediaAsset

    public init(
        id: UUID = UUID(),
        pageId: UUID,
        elementId: UUID,
        asset: MediaAsset
    ) {
        self.id = id
        self.pageId = pageId
        self.elementId = elementId
        self.asset = asset
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        guard asset.kind == .image else {
            throw EditorCommandError.invalidCommand("Card elements only accept image media.")
        }

        var document = try project.requiredCardDocument()
        try CardDocumentCommandValidation.validate(document)
        let pageIndex = try document.pageIndex(for: pageId)
        let elementIndex = try document.pages[pageIndex].elementIndex(for: elementId)
        let existingElement = document.pages[pageIndex].elements[elementIndex]
        guard existingElement.kind == .image || existingElement.kind == .logo else {
            throw EditorCommandError.invalidCommand("Only image and logo card elements can replace media.")
        }

        if let existingAsset = project.mediaLibrary.assets[asset.id], existingAsset != asset {
            throw EditorCommandError.invalidCommand("A different media asset already uses the replacement identifier.")
        }

        let previousDocument = document
        let previousAsset = project.mediaLibrary.assets[asset.id]
        project.mediaLibrary.assets[asset.id] = asset
        document.pages[pageIndex].elements[elementIndex].mediaAssetID = asset.id
        try CardDocumentCommandValidation.validate(document)
        project.cardDocument = document

        var undoValues: [String: CommandResultValue] = [
            "cardDocument": .cardDocument(previousDocument),
            "replacementAssetID": .uuid(asset.id),
            "hadPreviousAsset": .int(previousAsset == nil ? 0 : 1)
        ]
        if let previousAsset {
            undoValues["previousAsset"] = .mediaAsset(previousAsset)
        }
        return CommandResult(
            description: "Replaced card element image \(elementId)",
            undoValues: undoValues
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        guard case .cardDocument(let document)? = result.undoValues["cardDocument"],
              case .uuid(let replacementAssetID)? = result.undoValues["replacementAssetID"],
              case .int(let hadPreviousAsset)? = result.undoValues["hadPreviousAsset"] else {
            return NoOpCommand(description: "Missing card image replacement snapshot for inverse")
        }
        let previousAsset: MediaAsset?
        if hadPreviousAsset == 1,
           case .mediaAsset(let asset)? = result.undoValues["previousAsset"] {
            previousAsset = asset
        } else {
            previousAsset = nil
        }
        return RestoreCardImageReplacementCommand(
            document: document,
            replacementAssetID: replacementAssetID,
            previousAsset: previousAsset
        )
    }
}

private struct RestoreCardImageReplacementCommand: EditorCommand {
    let id: UUID
    let document: CardDocument?
    let replacementAssetID: UUID
    let previousAsset: MediaAsset?

    init(
        id: UUID = UUID(),
        document: CardDocument?,
        replacementAssetID: UUID,
        previousAsset: MediaAsset?
    ) {
        self.id = id
        self.document = document
        self.replacementAssetID = replacementAssetID
        self.previousAsset = previousAsset
    }

    func apply(to project: inout Project) throws -> CommandResult {
        let currentDocument = project.cardDocument
        let currentAsset = project.mediaLibrary.assets[replacementAssetID]
        project.cardDocument = document
        if let previousAsset {
            project.mediaLibrary.assets[replacementAssetID] = previousAsset
        } else {
            project.mediaLibrary.assets.removeValue(forKey: replacementAssetID)
        }

        var undoValues: [String: CommandResultValue] = [
            "cardDocument": .cardDocument(currentDocument),
            "replacementAssetID": .uuid(replacementAssetID),
            "hadPreviousAsset": .int(currentAsset == nil ? 0 : 1)
        ]
        if let currentAsset {
            undoValues["previousAsset"] = .mediaAsset(currentAsset)
        }
        return CommandResult(description: "Restored card image replacement", undoValues: undoValues)
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        guard case .cardDocument(let document)? = result.undoValues["cardDocument"],
              case .uuid(let replacementAssetID)? = result.undoValues["replacementAssetID"],
              case .int(let hadPreviousAsset)? = result.undoValues["hadPreviousAsset"] else {
            return NoOpCommand(description: "Missing restored card image replacement snapshot")
        }
        let previousAsset: MediaAsset?
        if hadPreviousAsset == 1,
           case .mediaAsset(let asset)? = result.undoValues["previousAsset"] {
            previousAsset = asset
        } else {
            previousAsset = nil
        }
        return RestoreCardImageReplacementCommand(
            document: document,
            replacementAssetID: replacementAssetID,
            previousAsset: previousAsset
        )
    }
}

private struct RestoreCardDocumentCommand: EditorCommand {
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
        Self.from(result: result, fallbackDescription: "Restored card document")
    }

    static func from(result: CommandResult, fallbackDescription: String) -> any EditorCommand {
        guard case .cardDocument(let document)? = result.undoValues["cardDocument"] else {
            return NoOpCommand(description: "Missing card document snapshot for inverse")
        }
        return RestoreCardDocumentCommand(document: document, description: fallbackDescription)
    }
}

private enum CardDocumentCommandValidation {
    static func validate(_ document: CardDocument) throws {
        var pageIds = Set<UUID>()
        var elementIds = Set<UUID>()

        for page in document.pages {
            guard pageIds.insert(page.id).inserted else {
                throw EditorCommandError.invalidCommand("Card page identifiers must be unique.")
            }
            if let duration = page.duration,
               (!duration.isFinite || duration < 0) {
                throw EditorCommandError.invalidCommand("Card page duration must be finite and nonnegative.")
            }
            for element in page.elements where !elementIds.insert(element.id).inserted {
                throw EditorCommandError.invalidCommand("Card element identifiers must be unique.")
            }
        }
    }
}

private extension Project {
    func requiredCardDocument() throws -> CardDocument {
        guard let cardDocument else {
            throw EditorCommandError.cardDocumentMissing
        }
        return cardDocument
    }
}

private extension CardDocument {
    func pageIndex(for pageId: UUID) throws -> Int {
        guard let index = pages.firstIndex(where: { $0.id == pageId }) else {
            throw EditorCommandError.cardPageNotFound(pageId)
        }
        return index
    }
}

private extension CardPage {
    func elementIndex(for elementId: UUID) throws -> Int {
        guard let index = elements.firstIndex(where: { $0.id == elementId }) else {
            throw EditorCommandError.cardElementNotFound(elementId)
        }
        return index
    }
}
