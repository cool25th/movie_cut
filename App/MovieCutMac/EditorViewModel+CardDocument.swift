import Foundation
import MovieCutCore

/// Card-news document authoring boundary of the EditorViewModel decomposition.
/// Pure method moves from `EditorViewModel.swift`; all mutations flow through
/// Core `EditorCommand` dispatch so undo/redo and autosave stay unified.
extension EditorViewModel {
    /// Whether the active project is a card-news document (rather than a
    /// video timeline project). Existing card projects still open into their
    /// dedicated editor.
    var isCardEditorMode: Bool {
        currentProject.cardDocument != nil
    }

    /// Applies a complete template set through one Core command. The gallery
    /// and DEBUG actual-app harness share this entry point.
    @discardableResult
    func applyCardTemplate(_ template: CardTemplateSet) async -> Bool {
        await applyCardTemplate(template, seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    /// Seeded overload used by deterministic actual-app evidence.
    @discardableResult
    func applyCardTemplate(_ template: CardTemplateSet, seed: UInt64) async -> Bool {
        await dispatchCardMutation(
            ApplyCardTemplateCommand(template: template, seed: seed),
            successMessage: "Applied \(template.name)."
        )
    }

    /// Applies one document-wide master style through one Core command while
    /// retaining page-local overrides.
    @discardableResult
    func setCardMasterStyle(_ masterStyle: CardMasterStyle) async -> Bool {
        await dispatchCardMutation(
            SetCardMasterStyleCommand(masterStyle: masterStyle),
            successMessage: "Updated the card master style."
        )
    }

    /// Adds a blank body page after the selected page, or at the end when no
    /// selection is supplied. The returned identifier is the persisted page ID.
    @discardableResult
    func addCardPage(after pageId: UUID?, pageID: UUID = UUID()) async -> UUID? {
        let snapshot = await session.snapshot()
        guard let document = snapshot.cardDocument else {
            lastErrorMessage = "This project does not contain a card document."
            return nil
        }

        let insertionIndex: Int
        if let pageId {
            guard let sourceIndex = document.pages.firstIndex(where: { $0.id == pageId }) else {
                lastErrorMessage = "The selected card page no longer exists."
                return nil
            }
            insertionIndex = sourceIndex + 1
        } else {
            insertionIndex = document.pages.endIndex
        }

        let page = CardPage(id: pageID, role: .body)
        let didApply = await dispatchCardMutation(
            AddCardPageCommand(page: page, insertionIndex: insertionIndex),
            successMessage: "Added page \(insertionIndex + 1)."
        )
        return didApply ? page.id : nil
    }

    /// Duplicates a page through the Core command layer and returns the fresh,
    /// stable identifier selected by the command.
    @discardableResult
    func duplicateCardPage(_ pageId: UUID, duplicatePageID: UUID = UUID()) async -> UUID? {
        let didApply = await dispatchCardMutation(
            DuplicateCardPageCommand(pageId: pageId, duplicatePageId: duplicatePageID),
            successMessage: "Duplicated the selected page."
        )
        return didApply ? duplicatePageID : nil
    }

    /// Deletes a page and returns the adjacent surviving page that the UI should
    /// select. The final page remains protected by the Core command invariant.
    @discardableResult
    func deleteCardPage(_ pageId: UUID) async -> UUID? {
        let snapshot = await session.snapshot()
        guard let pages = snapshot.cardDocument?.pages,
              let deletedIndex = pages.firstIndex(where: { $0.id == pageId }) else {
            lastErrorMessage = "The selected card page no longer exists."
            return nil
        }

        let didApply = await dispatchCardMutation(
            DeleteCardPageCommand(pageId: pageId),
            successMessage: "Deleted page \(deletedIndex + 1)."
        )
        guard didApply, let remainingPages = currentProject.cardDocument?.pages, !remainingPages.isEmpty else {
            return nil
        }
        return remainingPages[min(deletedIndex, remainingPages.count - 1)].id
    }

    /// Reorders a page to its final array index. Drag/drop and accessible move
    /// controls intentionally share this single command-backed entry point.
    @discardableResult
    func moveCardPage(_ pageId: UUID, to destinationIndex: Int) async -> Bool {
        let snapshot = await session.snapshot()
        guard let pages = snapshot.cardDocument?.pages,
              let sourceIndex = pages.firstIndex(where: { $0.id == pageId }) else {
            lastErrorMessage = "The selected card page no longer exists."
            return false
        }
        guard sourceIndex != destinationIndex else { return true }

        return await dispatchCardMutation(
            MoveCardPageCommand(pageId: pageId, destinationIndex: destinationIndex),
            successMessage: "Moved page to position \(destinationIndex + 1)."
        )
    }

    /// Changes the card aspect preset while leaving normalized element frames
    /// and all stable page/element identifiers untouched.
    @discardableResult
    func setCardFormat(_ format: CardFormat) async -> Bool {
        let snapshot = await session.snapshot()
        guard let document = snapshot.cardDocument else {
            lastErrorMessage = "This project does not contain a card document."
            return false
        }
        guard document.format != format else { return true }

        return await dispatchCardMutation(
            SetCardFormatCommand(format: format),
            successMessage: "Changed card format to \(format.accessibilityTitle)."
        )
    }

    /// Commits one completed card-canvas interaction. Gesture ticks and inline
    /// IME composition stay local to CardCanvasView; callers invoke this only at
    /// move/resize/edit completion so the session records exactly one snapshot.
    @discardableResult
    func updateCardElement(pageId: UUID, element: CardElement) async -> Bool {
        await dispatchCardMutation(
            UpdateCardElementCommand(
                pageId: pageId,
                elementId: element.id,
                element: element
            ),
            successMessage: "Updated card element \(element.id.uuidString)."
        )
    }

    /// Imports or reuses an image and updates the selected image/logo element in
    /// one Core command. Non-image inputs fail before any project mutation.
    @discardableResult
    func replaceCardElementImage(
        pageId: UUID,
        elementId: UUID,
        with url: URL
    ) async -> Bool {
        let probedAsset: MediaAsset
        do {
            probedAsset = try await mediaAssetWithAppProbe(for: url)
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
            return false
        }
        guard probedAsset.kind == .image else {
            lastStatusMessage = nil
            lastErrorMessage = "Card image replacement requires an image file."
            return false
        }

        let replacementAsset = currentProject.mediaLibrary.assets.values.first {
            $0.kind == .image && $0.originalURL.standardizedFileURL == url.standardizedFileURL
        } ?? probedAsset

        let didApply = await dispatchCardMutation(
            ReplaceCardElementImageCommand(
                pageId: pageId,
                elementId: elementId,
                asset: replacementAsset
            ),
            successMessage: "Replaced the selected card image with \(url.lastPathComponent)."
        )
        if didApply {
            selectedAssetId = replacementAsset.id
        }
        return didApply
    }

    private func dispatchCardMutation(
        _ command: any EditorCommand,
        successMessage: String
    ) async -> Bool {
        do {
            try await session.dispatch(command)
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = successMessage
            return true
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
            return false
        }
    }
}
