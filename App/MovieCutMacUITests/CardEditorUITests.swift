import XCTest

final class CardEditorUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
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

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "G18-Inc2-Card-Editor-Page-Rail"
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
}
