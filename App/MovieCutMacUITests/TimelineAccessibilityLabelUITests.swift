import XCTest

/// Runtime replacement for the Korean-key StaticContract assertions that task
/// 1.3 deleted from `UIUXAccessibilityRegressionStaticContractTests`,
/// `R502TimelineZoomStaticContractTests`, `R503TrackHeaderStaticContractTests`,
/// `R504MainVideoTrackStaticContractTests`,
/// `Phase04TimelineEditToolbarStaticContractTests`, and
/// `Phase23TimelineToolbarIconOnlyStaticContractTests`.
///
/// Those assertions pinned source literals such as `"타임라인 축소"` and
/// `"%@ 클립 추가 영역"` — the exact localization defect requirement 1 removes.
/// Re-pinning them to the new English literals would add a fresh StaticContract
/// (requirement 15.6 forbids that) and would still prove nothing about what
/// VoiceOver actually reads. This suite reads `XCUIElement.label` from the
/// running app instead, so the surviving intent is checked against behaviour:
///
/// - every timeline element the deleted assertions covered still carries a
///   non-empty accessibility label,
/// - the icon-only zoom buttons carry *different* labels from each other (they
///   have no visible text, so the label is all VoiceOver has),
/// - a main video track reads differently from a plain video track and from an
///   audio track, and the main-track label embeds the track name,
/// - each lane's drop region derives its label from its own track header label.
///
/// **This suite is deliberately locale-independent.** These labels resolve
/// through `Localizable.xcstrings` at run time, so on a Korean-language host the
/// app legitimately reports `'타임라인 축소'`. Asserting a specific language here
/// would both duplicate and pre-empt task 1.4, which owns "English locale
/// exposes zero Hangul / Korean locale copy unchanged". Elements are therefore
/// located by accessibility identifier, never by label text.
///
/// `MOVIECUT_UITEST_QUIT` is intentionally left unset: the harness quit path
/// breaks the accessibility handshake (see `UnsavedChangesGuardUITests`), and
/// this suite exists precisely to read accessibility labels.
final class TimelineAccessibilityLabelUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Track IDs are fixed by the fixture so the test can address one specific
    /// lane instead of guessing at ordering.
    private enum FixtureTrack {
        static let mainVideo = "20000000-0000-4000-8000-000000000003"
        static let secondVideo = "20000000-0000-4000-8000-000000000004"
        static let audio = "20000000-0000-4000-8000-000000000005"
        static let mainVideoName = "Video 1"
    }

    /// Three tracks so every branch of `trackHeaderAccessibilityLabel(for:)`
    /// that the deleted assertions touched is reachable in one launch: the first
    /// video track resolves to the main-track label, the second video track
    /// falls through to the generic video-track label (this is what the deleted
    /// `"비디오 트랙 헤더"` assertion guarded), and the audio track covers the
    /// non-video branch.
    private var bootstrapFixture: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // MovieCutMacUITests/
            .deletingLastPathComponent()   // App/
            .deletingLastPathComponent()   // repo root
            .appending(path: "Tests/Fixtures/timeline_accessibility_bootstrap.moviecut")
    }

    @MainActor
    func testTimelineElementsExposeAccessibilityLabels() throws {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: bootstrapFixture.path),
            "Missing deterministic timeline accessibility bootstrap project."
        )

        let workingDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "MovieCutTimelineA11yUITest-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let workingProject = workingDirectory.appending(path: "timeline_accessibility_working.moviecut")
        try FileManager.default.copyItem(at: bootstrapFixture, to: workingProject)

        let app = XCUIApplication()
        app.launchEnvironment["MOVIECUT_BOOTSTRAP_PROJECT"] = workingProject.path
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "MovieCutMac did not reach the foreground.")

        // The timeline root stays a labeled accessibility container.
        let timelineRoot = element(identified: "timeline.root", in: app)
        XCTAssertTrue(timelineRoot.waitForExistence(timeout: 30), "Timeline root was not in the accessibility tree.")
        XCTAssertFalse(timelineRoot.label.isEmpty, "Timeline root exposed no accessibility label.")

        // Zoom controls: the toolbar renders these icon-only, so the
        // accessibility label is the only thing VoiceOver can announce. This is
        // the intent behind the deleted `"타임라인 축소"` / `"타임라인 확대"` markers in
        // R5-02, Phase 0-4, Phase 2-3, and UX-08. Reading them through
        // `timelineRoot` also proves the zoom cluster really is inside the
        // labeled timeline container.
        let zoomOut = element(identified: "timeline.zoomOut", in: timelineRoot)
        XCTAssertTrue(zoomOut.waitForExistence(timeout: 10), "Timeline zoom-out button was not inside the timeline container.")
        XCTAssertFalse(zoomOut.label.isEmpty, "Timeline zoom-out button exposed no accessibility label.")

        let zoomIn = element(identified: "timeline.zoomIn", in: timelineRoot)
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10), "Timeline zoom-in button was not inside the timeline container.")
        XCTAssertFalse(zoomIn.label.isEmpty, "Timeline zoom-in button exposed no accessibility label.")

        XCTAssertNotEqual(
            zoomOut.label,
            zoomIn.label,
            "Zoom in and zoom out must not share one accessibility label."
        )

        // Track header labels, including the generic video-track fallback that
        // only a non-first video track reaches.
        let mainVideoHeader = try labeledElement(
            identifier: "timeline.trackHeader.\(FixtureTrack.mainVideo)",
            in: app,
            description: "main video track header"
        )
        let secondVideoHeader = try labeledElement(
            identifier: "timeline.trackHeader.\(FixtureTrack.secondVideo)",
            in: app,
            description: "second video track header"
        )
        let audioHeader = try labeledElement(
            identifier: "timeline.trackHeader.\(FixtureTrack.audio)",
            in: app,
            description: "audio track header"
        )

        XCTAssertNotEqual(
            mainVideoHeader,
            secondVideoHeader,
            "The main video track must not read the same as a plain video track."
        )
        XCTAssertNotEqual(
            secondVideoHeader,
            audioHeader,
            "A video track header must not read the same as an audio track header."
        )
        XCTAssertTrue(
            mainVideoHeader.contains(FixtureTrack.mainVideoName),
            "The main video track label must embed the track name; got \(mainVideoHeader)."
        )

        // Lane drop regions: the deleted `"%@ 클립 추가 영역"` markers guarded that
        // each lane's drop target is labeled and that the label is derived from
        // *its own* track header label rather than a bare shared string.
        for (trackID, headerLabel) in [
            (FixtureTrack.mainVideo, mainVideoHeader),
            (FixtureTrack.secondVideo, secondVideoHeader),
            (FixtureTrack.audio, audioHeader)
        ] {
            let laneLabel = try labeledElement(
                identifier: "timeline.trackLane.\(trackID)",
                in: app,
                description: "track lane drop region for \(trackID)"
            )
            XCTAssertTrue(
                laneLabel.contains(headerLabel),
                "Lane drop region label \(laneLabel) is not derived from its track header label \(headerLabel)."
            )
            XCTAssertNotEqual(
                laneLabel,
                headerLabel,
                "Lane drop region must not reuse the track header label verbatim."
            )
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Task-1.3-Timeline-Accessibility-Labels"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func element(identified identifier: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }

    /// Returns the element's accessibility label, failing the test when the
    /// element is missing or unlabeled.
    @MainActor
    private func labeledElement(
        identifier: String,
        in app: XCUIApplication,
        description: String
    ) throws -> String {
        let element = element(identified: identifier, in: app)
        XCTAssertTrue(
            element.waitForExistence(timeout: 10),
            "\(description) was not in the accessibility tree (identifier \(identifier))."
        )
        let label = element.label
        XCTAssertFalse(label.isEmpty, "\(description) exposed no accessibility label.")
        return label
    }
}
