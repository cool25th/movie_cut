import XCTest

/// Requirement 1 acceptance evidence (task 1.4).
///
/// Task 1.2 replaced every Korean `NSLocalizedString` key with an English key
/// and re-keyed `Localizable.xcstrings`; task 1.3 promoted the deleted Korean
/// StaticContract assertions to a locale-independent runtime check. Neither
/// measured *which language* the running app actually speaks, because the
/// development host runs in a Korean locale. This suite does that measurement
/// by launching the app forced into a specific language and sweeping the whole
/// accessibility tree:
///
/// - `testEnglishLocale…TimelineSurface…` / `…CardSurface…` — acceptance
///   criterion 1.1: zero Hangul in any accessibility text the app publishes.
/// - `testKoreanLocaleKeepsCatalogKoreanCopy` — acceptance criterion 1.2: the
///   Korean copy still reads exactly what `Localizable.xcstrings` stores under
///   `ko`.
///
/// Two rules keep this from degenerating into another string contract:
///
/// 1. **The sweep is exhaustive, not a hand-picked list.** Every node of
///    `XCUIElementSnapshot` is visited and every human-readable attribute
///    (`label`, `title`, `value`, `placeholderValue`) is inspected. A new
///    Korean label added anywhere reachable fails the English tests without
///    anybody extending a list.
/// 2. **Expected strings are read from the catalog at run time**, never
///    hardcoded. The tests assert the app resolves to the catalog's `en` / `ko`
///    values, so re-wording a translation updates the expectation with it. What
///    is pinned is the *relationship* (running app == catalog for the requested
///    language), not the copy.
///
/// `MOVIECUT_UITEST_QUIT` is deliberately never set: the harness quit path
/// breaks the accessibility handshake (see `UnsavedChangesGuardUITests`), and
/// these tests exist to read accessibility text.
final class LocalizedAccessibilityLabelUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - Fixture identifiers

    /// Fixed by `Tests/Fixtures/timeline_localization_bootstrap.moviecut` so the
    /// tests can address one specific lane instead of relying on ordering.
    private enum FixtureTrack {
        static let mainVideo = "30000000-0000-4000-8000-000000000003"
        static let secondVideo = "30000000-0000-4000-8000-000000000004"
        static let audio = "30000000-0000-4000-8000-000000000005"
        static let text = "30000000-0000-4000-8000-000000000006"
        static let mainVideoName = "Video 1"
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // MovieCutMacUITests/
            .deletingLastPathComponent()   // App/
            .deletingLastPathComponent()   // repo root
    }

    private var timelineFixture: URL {
        repositoryRoot.appending(path: "Tests/Fixtures/timeline_localization_bootstrap.moviecut")
    }

    private var cardFixture: URL {
        repositoryRoot.appending(path: "Tests/Fixtures/card_editor_bootstrap.moviecut")
    }

    private var catalogURL: URL {
        repositoryRoot.appending(path: "App/MovieCutMac/Localizable.xcstrings")
    }

    // MARK: - Tests

    /// Acceptance criterion 1.1 on the timeline / inspector surface.
    @MainActor
    func testEnglishLocaleTimelineSurfaceExposesNoHangul() throws {
        let catalog = try LocalizationCatalog(url: catalogURL)
        let app = try launch(project: timelineFixture, language: "en", locale: "en_US")
        try waitForTimelineSurface(in: app)

        let sweep = try sweepAccessibilityText(of: app, locale: "en")
        assertNoHangul(in: sweep, locale: "en")
        try assertTimelineAnchors(sweep, catalog: catalog, language: "en")
        try assertTimelineReach(sweep, catalog: catalog, language: "en")
        attach(sweep, named: "Task-1.4-Sweep-en-timeline")
    }

    /// Acceptance criterion 1.1 on the card editor surface, which replaces the
    /// whole editor view and therefore publishes a disjoint set of labels.
    @MainActor
    func testEnglishLocaleCardSurfaceExposesNoHangul() throws {
        let app = try launch(project: cardFixture, language: "en", locale: "en_US")

        let pageCount = app.descendants(matching: .any)
            .matching(identifier: "cardEditor.pageCount")
            .firstMatch
        XCTAssertTrue(pageCount.waitForExistence(timeout: 40), "Card editor surface did not appear.")

        let sweep = try sweepAccessibilityText(of: app, locale: "en")
        assertNoHangul(in: sweep, locale: "en")
        attach(sweep, named: "Task-1.4-Sweep-en-card")
    }

    /// Acceptance criterion 1.2: the Korean copy is unchanged, checked against
    /// the catalog rather than against strings typed into this file.
    @MainActor
    func testKoreanLocaleKeepsCatalogKoreanCopy() throws {
        let catalog = try LocalizationCatalog(url: catalogURL)
        let app = try launch(project: timelineFixture, language: "ko", locale: "ko_KR")
        try waitForTimelineSurface(in: app)

        let sweep = try sweepAccessibilityText(of: app, locale: "ko")
        try assertTimelineAnchors(sweep, catalog: catalog, language: "ko")
        try assertTimelineReach(sweep, catalog: catalog, language: "ko")

        // Nothing above would notice a *silent* fallback on some other element,
        // so also check the sweep as a whole: any label that is byte-identical
        // to a catalog `en` value whose `ko` value differs means the Korean
        // translation exists but was not applied.
        let leaks = sweep.texts
            .filter { catalog.isUntranslatedEnglish($0.text) }
            .map { "\($0.attribute) \"\($0.text)\" at \($0.path)" }
        XCTAssertTrue(
            leaks.isEmpty,
            "Korean locale served \(leaks.count) English string(s) that the catalog translates:\n"
                + leaks.sorted().joined(separator: "\n")
        )

        let hangulCount = sweep.texts.filter { Self.containsHangul($0.text) }.count
        XCTAssertGreaterThan(
            hangulCount,
            0,
            "Korean locale published no Hangul at all, so this launch cannot have used the ko catalog."
        )
        print("[a11y-sweep] locale=ko hangulTexts=\(hangulCount)")

        attach(sweep, named: "Task-1.4-Sweep-ko-timeline")
    }

    // MARK: - Launch

    @MainActor
    private func launch(project fixture: URL, language: String, locale: String) throws -> XCUIApplication {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.path),
            "Missing bootstrap project \(fixture.lastPathComponent)."
        )

        let workingDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "MovieCutLocalizedA11yUITest-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: workingDirectory) }

        let workingProject = workingDirectory.appending(path: "localization_working.moviecut")
        try FileManager.default.copyItem(at: fixture, to: workingProject)

        let app = XCUIApplication()
        // `-AppleLanguages` / `-AppleLocale` land in the launched process's
        // argument defaults domain, which outranks the host's system language.
        // This is the only way to measure the English locale on a Korean host.
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchEnvironment["MOVIECUT_BOOTSTRAP_PROJECT"] = workingProject.path
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 40),
            "MovieCutMac did not reach the foreground for language \(language)."
        )
        return app
    }

    @MainActor
    private func waitForTimelineSurface(in app: XCUIApplication) throws {
        let timelineRoot = app.descendants(matching: .any)
            .matching(identifier: "timeline.root")
            .firstMatch
        XCTAssertTrue(timelineRoot.waitForExistence(timeout: 40), "Timeline surface did not appear.")

        // The bootstrap project loads asynchronously; wait until its clips are
        // in the tree so the sweep covers clip and trim-handle labels.
        let clipLane = app.descendants(matching: .any)
            .matching(identifier: "timeline.trackLane.\(FixtureTrack.text)")
            .firstMatch
        XCTAssertTrue(clipLane.waitForExistence(timeout: 40), "Bootstrap project tracks did not load.")
    }

    // MARK: - Assertions

    @MainActor
    private func assertNoHangul(in sweep: Sweep, locale: String) {
        let hits = sweep.texts
            .filter { Self.containsHangul($0.text) }
            .map { "\($0.attribute) \"\($0.text)\" at \($0.path)" }
        XCTAssertTrue(
            hits.isEmpty,
            "\(locale) locale exposed Hangul in \(hits.count) accessibility text(s):\n"
                + hits.sorted().prefix(40).joined(separator: "\n")
        )
    }

    /// Elements that carry a stable accessibility identifier, compared against
    /// the catalog value for the requested language.
    @MainActor
    private func assertTimelineAnchors(
        _ sweep: Sweep,
        catalog: LocalizationCatalog,
        language: String
    ) throws {
        let mainVideoHeader = try String(
            format: catalog.value("Main video track, %@", language: language),
            FixtureTrack.mainVideoName
        )
        let secondVideoHeader = try catalog.value("Video track header", language: language)
        let audioHeader = try catalog.value("Audio track header", language: language)
        let textHeader = try catalog.value("Text track header", language: language)
        let laneFormat = try catalog.value("%@ clip add region", language: language)

        var expected: [String: String] = [
            "timeline.root": try catalog.value("Timeline", language: language),
            "timeline.zoomOut": try catalog.value("Timeline zoom out", language: language),
            "timeline.zoomIn": try catalog.value("Timeline zoom in", language: language),
            "timeline.trackHeader.\(FixtureTrack.mainVideo)": mainVideoHeader,
            "timeline.trackHeader.\(FixtureTrack.secondVideo)": secondVideoHeader,
            "timeline.trackHeader.\(FixtureTrack.audio)": audioHeader,
            "timeline.trackHeader.\(FixtureTrack.text)": textHeader
        ]
        for (trackID, header) in [
            (FixtureTrack.mainVideo, mainVideoHeader),
            (FixtureTrack.secondVideo, secondVideoHeader),
            (FixtureTrack.audio, audioHeader),
            (FixtureTrack.text, textHeader)
        ] {
            expected["timeline.trackLane.\(trackID)"] = String(format: laneFormat, header)
        }

        for identifier in expected.keys.sorted() {
            guard let actual = sweep.labelsByIdentifier[identifier] else {
                XCTFail("\(language): element \(identifier) was not in the accessibility tree.")
                continue
            }
            XCTAssertEqual(
                actual,
                expected[identifier],
                "\(language): \(identifier) did not read its catalog value."
            )
        }
        print("[a11y-sweep] locale=\(language) anchorsChecked=\(expected.count)")
    }

    /// Labels the deleted Korean assertions and requirement 1's evidence named
    /// (`TimelineView.swift:788, 941, 950` — clip add region and both trim
    /// handles). These elements carry no identifier, so they are checked by
    /// presence of the catalog-derived string in the swept set.
    @MainActor
    private func assertTimelineReach(
        _ sweep: Sweep,
        catalog: LocalizationCatalog,
        language: String
    ) throws {
        let videoClip = try catalog.value("Video clip", language: language)
        var required = [
            videoClip,
            try catalog.value("Audio clip", language: language),
            try catalog.value("Text clip", language: language),
            try catalog.value("Playhead", language: language),
            try catalog.value("Timeline ruler", language: language),
            try catalog.value("Timeline zoom controls", language: language),
            try catalog.value("Timeline zoom slider", language: language),
            try catalog.value("Beat marker", language: language)
        ]
        required.append(try String(
            format: catalog.value("%@ left trim handle", language: language),
            videoClip
        ))
        required.append(try String(
            format: catalog.value("%@ right trim handle", language: language),
            videoClip
        ))

        let swept = Set(sweep.texts.map(\.text))
        let missing = required.filter { !swept.contains($0) }
        XCTAssertTrue(
            missing.isEmpty,
            "\(language): the sweep never reached \(missing.count) expected label(s): \(missing.sorted())"
        )
        print("[a11y-sweep] locale=\(language) reachLabelsChecked=\(required.count)")
    }

    // MARK: - Accessibility tree sweep

    private struct SweptText {
        let path: String
        let attribute: String
        let text: String
    }

    private struct Sweep {
        var elementCount = 0
        var texts: [SweptText] = []
        var labelsByIdentifier: [String: String] = [:]
        /// System-owned subtrees that were not descended into, recorded so the
        /// exclusion stays auditable instead of silent.
        var skippedSystemSubtrees: [String] = []
    }

    /// Walks the app's whole accessibility snapshot and collects every
    /// human-readable attribute. One snapshot call captures the entire subtree,
    /// so this sees elements a query-by-query approach would miss.
    ///
    /// Three kinds of subtree are skipped because the app neither owns nor can
    /// localize their text. All three were measured to be Korean on this host
    /// while the app's own labels were correctly English:
    ///
    /// - **The Apple menu** (the menu bar's first item). Its contents are the
    ///   system's — About This Mac, System Settings, Log Out, Shut Down — plus
    ///   the user's own Finder recent-items list, localized by the *system*
    ///   language and holding user file names.
    /// - **The Touch Bar strip**, which carries the active input method's typing
    ///   predictions, i.e. the host's Korean IME output.
    /// - **AppKit's private menu items**, identified by their private action
    ///   selector (`_toggleIPad:` and friends). AppKit builds their titles from
    ///   system and user data: the measured case here was
    ///   `Move to <user's iPad name>` in the Window menu, whose Hangul is the
    ///   device name. Publicly-selectored standard items (`undo:`, `cut:`, …)
    ///   and the app's own menu commands do not match this pattern and stay in
    ///   the sweep.
    ///
    /// The exclusion cannot be widened to hide a real defect: the anchor and
    /// reach assertions require the app's own timeline labels to be present in
    /// the same sweep, so dropping an app-owned subtree turns the tests red.
    @MainActor
    private func sweepAccessibilityText(of app: XCUIApplication, locale: String) throws -> Sweep {
        var sweep = Sweep()

        func visit(
            _ snapshot: XCUIElementSnapshot,
            parentPath: String,
            parentType: XCUIElement.ElementType,
            indexInParent: Int
        ) {
            var node = "t\(snapshot.elementType.rawValue)"
            if !snapshot.identifier.isEmpty {
                node += "#\(snapshot.identifier)"
            }
            let path = parentPath.isEmpty ? node : "\(parentPath) > \(node)"

            let isAppleMenu = snapshot.elementType == .menuBarItem
                && parentType == .menuBar
                && indexInParent == 0
            let isAppKitPrivateItem = snapshot.identifier.hasPrefix("_")
                && snapshot.identifier.hasSuffix(":")
            if let reason = isAppleMenu ? "apple-menu"
                : snapshot.elementType == .touchBar ? "touch-bar"
                : isAppKitPrivateItem ? "appkit-private-menu-item"
                : nil {
                sweep.skippedSystemSubtrees.append("\(reason)\t\(path)")
                return
            }

            sweep.elementCount += 1

            var attributes: [(String, String?)] = [
                ("label", snapshot.label),
                ("title", snapshot.title),
                ("placeholderValue", snapshot.placeholderValue)
            ]
            if let stringValue = snapshot.value as? String {
                attributes.append(("value", stringValue))
            }
            for (attribute, text) in attributes {
                guard let text, !text.isEmpty else { continue }
                sweep.texts.append(SweptText(path: path, attribute: attribute, text: text))
            }

            if !snapshot.identifier.isEmpty,
               !snapshot.label.isEmpty,
               sweep.labelsByIdentifier[snapshot.identifier] == nil {
                sweep.labelsByIdentifier[snapshot.identifier] = snapshot.label
            }

            for (index, child) in snapshot.children.enumerated() {
                visit(child, parentPath: path, parentType: snapshot.elementType, indexInParent: index)
            }
        }

        visit(try app.snapshot(), parentPath: "", parentType: .any, indexInParent: 0)

        let labels = sweep.texts.filter { $0.attribute == "label" }.count
        XCTAssertGreaterThan(sweep.elementCount, 1, "Accessibility sweep found no elements.")
        print(
            "[a11y-sweep] locale=\(locale) elements=\(sweep.elementCount)"
                + " texts=\(sweep.texts.count) labels=\(labels)"
                + " distinctTexts=\(Set(sweep.texts.map(\.text)).count)"
                + " identifiedLabels=\(sweep.labelsByIdentifier.count)"
                + " skippedSystemSubtrees=\(sweep.skippedSystemSubtrees.count)"
        )
        return sweep
    }

    @MainActor
    private func attach(_ sweep: Sweep, named name: String) {
        let body = sweep.texts
            .map { "\($0.attribute)\t\($0.text)\t\($0.path)" }
            .joined(separator: "\n")
        let skipped = sweep.skippedSystemSubtrees.joined(separator: "\n")
        let attachment = XCTAttachment(
            string: """
            elements=\(sweep.elementCount) texts=\(sweep.texts.count)
            [skipped system-owned subtrees]
            \(skipped)
            [swept text]
            \(body)
            """
        )
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Hangul detection

    /// Syllables, both jamo blocks, and both extension blocks — not just
    /// AC00–D7A3 — so decomposed or archaic input is caught too.
    private static let hangulScalarRanges: [ClosedRange<UInt32>] = [
        0x1100...0x11FF,
        0x3130...0x318F,
        0xA960...0xA97F,
        0xAC00...0xD7A3,
        0xD7B0...0xD7FF
    ]

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            hangulScalarRanges.contains { $0.contains(scalar.value) }
        }
    }

    // MARK: - Catalog

    /// Minimal reader for the string catalog the app ships. Reading the source
    /// catalog keeps the expectations in one place: the tests cannot drift from
    /// the shipped copy, and re-translating a string does not require a test
    /// edit.
    private struct LocalizationCatalog {
        private let valuesByKey: [String: [String: String]]
        private let untranslatedEnglish: Set<String>

        init(url: URL) throws {
            let data = try Data(contentsOf: url)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let strings = root["strings"] as? [String: Any] else {
                throw CatalogError.malformed(url.lastPathComponent)
            }

            var valuesByKey: [String: [String: String]] = [:]
            var untranslatedEnglish: Set<String> = []
            for (key, entry) in strings {
                guard let entry = entry as? [String: Any],
                      let localizations = entry["localizations"] as? [String: Any] else {
                    continue
                }
                var values: [String: String] = [:]
                for (language, localization) in localizations {
                    guard let localization = localization as? [String: Any],
                          let unit = localization["stringUnit"] as? [String: Any],
                          let value = unit["value"] as? String else {
                        continue
                    }
                    values[language] = value
                }
                valuesByKey[key] = values
                if let english = values["en"], let korean = values["ko"], english != korean {
                    untranslatedEnglish.insert(english)
                }
            }
            self.valuesByKey = valuesByKey
            self.untranslatedEnglish = untranslatedEnglish
        }

        func value(_ key: String, language: String) throws -> String {
            guard let value = valuesByKey[key]?[language] else {
                throw CatalogError.missing(key: key, language: language)
            }
            return value
        }

        /// True when the text is a catalog `en` value that has a *different*
        /// `ko` value, i.e. a translation that exists but was not applied.
        func isUntranslatedEnglish(_ text: String) -> Bool {
            untranslatedEnglish.contains(text)
        }

        enum CatalogError: Error, CustomStringConvertible {
            case malformed(String)
            case missing(key: String, language: String)

            var description: String {
                switch self {
                case .malformed(let name):
                    return "\(name) is not a readable string catalog."
                case .missing(let key, let language):
                    return "Catalog has no \(language) value for '\(key)'."
                }
            }
        }
    }
}
