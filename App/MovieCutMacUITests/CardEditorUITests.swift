import Carbon.HIToolbox
import XCTest

final class CardEditorUITests: XCTestCase {
    /// XCUITest turns `typeText` into synthesized key events that the *host's*
    /// active keyboard input source interprets. With a CJK input method
    /// selected — this host's default selection is
    /// `com.apple.inputmethod.Korean.2SetKorean` — individual characters are
    /// swallowed by the input method before they ever reach the app: measured on
    /// this host, every `f` typed into the focused inline editor was lost while
    /// every other character arrived (`"of"` produced `"o"`, `"gh"` produced
    /// `"gh"`). Pin an ASCII-capable keyboard layout for the duration of the
    /// test and restore the user's selection afterwards so text entry is
    /// deterministic and independent of the developer's input source.
    private var inputSourceToRestore: TISInputSource?

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        inputSourceToRestore = Self.pinASCIICapableKeyboardLayout()
    }

    override func tearDown() {
        if let inputSourceToRestore {
            TISSelectInputSource(inputSourceToRestore)
        }
        inputSourceToRestore = nil
        super.tearDown()
    }

    /// Selects an ASCII-capable keyboard layout and returns the previously
    /// selected source so `tearDown` can restore it. Returns `nil` when the
    /// current source is already a keyboard layout or when no switch happened.
    private static func pinASCIICapableKeyboardLayout() -> TISInputSource? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        let currentID = inputSourceID(current) ?? "<unknown>"
        guard !currentID.hasPrefix("com.apple.keylayout.") else {
            print("[input-source] already a keyboard layout: \(currentID)")
            return nil
        }
        guard let candidates = TISCreateASCIICapableInputSourceList()?
            .takeRetainedValue() as? [TISInputSource] else {
            print("[input-source] no ASCII-capable sources; keeping \(currentID)")
            return nil
        }
        let preferred = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        let replacement = candidates.first { preferred.contains(inputSourceID($0) ?? "") }
            ?? candidates.first { (inputSourceID($0) ?? "").hasPrefix("com.apple.keylayout.") }
        guard let replacement else {
            print("[input-source] no ASCII keyboard layout enabled; keeping \(currentID)")
            return nil
        }
        let status = TISSelectInputSource(replacement)
        print("[input-source] \(currentID) -> \(inputSourceID(replacement) ?? "<unknown>") status=\(status)")
        return status == noErr ? current : nil
    }

    private static func inputSourceID(_ source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private var cardProjectFixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Tests/Fixtures/card_editor_bootstrap.moviecut")
    }

    @MainActor
    func testCardEditorPageRailActionsAndFormatPicker() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: cardProjectFixture.path),
            "Missing deterministic card editor bootstrap project."
        )

        let workingDirectory = FileManager.default.temporaryDirectory
            .appending(path: "MovieCutCardEditorUITest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let workingProject = workingDirectory.appending(path: "card_editor_working.moviecut")
        try FileManager.default.copyItem(at: cardProjectFixture, to: workingProject)

        let app = XCUIApplication()
        app.launchEnvironment["MOVIECUT_BOOTSTRAP_PROJECT"] = workingProject.path
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "MovieCutMac did not reach the foreground.")
        XCTAssertTrue(app.staticTexts["Card Editor"].waitForExistence(timeout: 20), "Card editor mode did not appear.")

        let pageCount = app.staticTexts["cardEditor.pageCount"]
        XCTAssertTrue(pageCount.waitForExistence(timeout: 10), "Page count was not exposed to accessibility.")
        XCTAssertEqual(pageCount.label, "3 pages")

        let secondPage = app.buttons["cardEditor.page.2"]
        XCTAssertTrue(secondPage.waitForExistence(timeout: 10), "Second page thumbnail was not accessible.")
        secondPage.click()

        let selectionStatus = app.staticTexts["cardEditor.selectionStatus"]
        XCTAssertTrue(waitForLabel("Selected page 2 of 3", on: selectionStatus), "Selecting page 2 did not update visible selection state.")

        let duplicateButton = app.buttons["cardEditor.duplicatePage"]
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 5), "Duplicate control was not accessible.")
        duplicateButton.click()
        XCTAssertTrue(waitForLabel("4 pages", on: pageCount), "Duplicate did not increase the persisted page count.")
        XCTAssertTrue(waitForLabel("Selected page 3 of 4", on: selectionStatus), "The duplicated page was not selected.")

        // The accessible reorder control exercises the same ViewModel and
        // MoveCardPageCommand path as drag/drop without relying on CI drag timing.
        let moveEarlierButton = app.buttons["cardEditor.moveEarlier"]
        XCTAssertTrue(moveEarlierButton.waitForExistence(timeout: 5), "Accessible reorder control was not exposed.")
        moveEarlierButton.click()
        XCTAssertTrue(waitForLabel("Selected page 2 of 4", on: selectionStatus), "Reorder did not update the visible final page index.")

        let storySegment = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "9:16"))
            .firstMatch
        XCTAssertTrue(storySegment.waitForExistence(timeout: 10), "9:16 format segment was not accessible.")
        storySegment.click()

        let formatStatus = app.staticTexts["cardEditor.formatStatus"]
        XCTAssertTrue(waitForLabel("Format: 9:16", on: formatStatus), "Format picker did not update visible persisted format state.")
        XCTAssertEqual(pageCount.label, "4 pages", "Format change unexpectedly changed the page sequence.")

        let inlineTextElement = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "cardCanvas.element.",
                "Three ideas for better stories"
            ))
            .firstMatch
        XCTAssertTrue(inlineTextElement.waitForExistence(timeout: 10), "A real canvas text element was not accessible.")
        inlineTextElement.doubleClick()

        let inlineEditor = app.descendants(matching: .any)
            .matching(identifier: "cardCanvas.inlineEditor")
            .firstMatch
        XCTAssertTrue(inlineEditor.waitForExistence(timeout: 5), "Double-click did not open the inline editor.")
        inlineEditor.click()
        inlineEditor.typeKey("a", modifierFlags: .command)
        inlineEditor.typeText("Inline canvas proof")
        app.buttons["cardCanvas.inlineCommit"].click()

        XCTAssertTrue(
            waitForLabelContaining("Inline canvas proof", on: inlineTextElement),
            "Committed inline text was not visible on the same element."
        )
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            waitForLabelContaining("Three ideas for better stories", on: inlineTextElement),
            "One undo did not restore the original inline text."
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "G18-Inc3-Inline-Card-Canvas"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func waitForLabel(
        _ expectedLabel: String,
        on element: XCUIElement,
        timeout: TimeInterval = 10
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label == expectedLabel {
                return true
            }
            usleep(100_000)
        }
        return element.exists && element.label == expectedLabel
    }

    @MainActor
    private func waitForLabelContaining(
        _ expectedText: String,
        on element: XCUIElement,
        timeout: TimeInterval = 10
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists, element.label.contains(expectedText) {
                return true
            }
            usleep(100_000)
        }
        return element.exists && element.label.contains(expectedText)
    }
}
