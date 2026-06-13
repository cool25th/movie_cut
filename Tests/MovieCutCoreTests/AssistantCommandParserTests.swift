import Foundation
import Testing
@testable import MovieCutCore

/// F-21 assistant: rule-based intent parsing. The AC requires 20 intent
/// scenarios to map correctly and unrecognized input to return guidance.
@Suite("Assistant Command Parser")
struct AssistantCommandParserTests {
    private func intent(_ text: String) -> AssistantIntent? {
        if case .recognized(let intent) = AssistantCommandParser.parse(text) {
            return intent
        }
        return nil
    }

    @Test("20 intent scenarios map to the expected target and action")
    func twentyScenarios() {
        // (input, expected target, expected action)
        let scenarios: [(String, AssistantTarget, AssistantAction)] = [
            ("Apply a cinematic filter to all clips", .allClips, .applyFilter(.cinematicLUT)),
            ("Give every clip a vintage look", .allClips, .applyFilter(.vintageLUT)),
            ("Make all video noir", .videoClips, .applyFilter(.noirLUT)),
            ("Apply a vivid filter", .selection, .applyFilter(.vividLUT)),
            ("Use a cool tone on all clips", .allClips, .applyFilter(.coolLUT)),
            ("Add a sepia look", .selection, .applyFilter(.sepia)),
            ("Blur the selected clip", .selection, .applyFilter(.blur)),
            ("Convert all clips to black and white", .allClips, .applyFilter(.grayscale)),
            ("Remove all filters", .allClips, .removeFilters),
            ("Clear the effects on this clip", .selection, .removeFilters),
            ("Mute all audio", .audioClips, .setVolume(0)),
            ("Set volume to 50%", .selection, .setVolume(0.5)),
            ("Add a 2 second fade to all clips", .allClips, .setFade(2)),
            ("Fade the selected clip", .selection, .setFade(1)),
            ("Remove the fade", .selection, .removeFade),
            ("Make everything brighter", .allClips, .adjustBrightness(0.2)),
            ("Darken all video", .videoClips, .adjustBrightness(-0.2)),
            ("Increase contrast on all clips", .allClips, .adjustContrast(0.2)),
            ("Make the video more vivid", .videoClips, .adjustSaturation(0.2)),
            ("Add a marker", .selection, .addMarker)
        ]

        #expect(scenarios.count == 20)
        for (text, target, action) in scenarios {
            let parsed = intent(text)
            #expect(parsed != nil, "Failed to parse: \(text)")
            #expect(parsed?.target == target, "Wrong target for: \(text) → \(String(describing: parsed?.target))")
            #expect(parsed?.action == action, "Wrong action for: \(text) → \(String(describing: parsed?.action))")
        }
    }

    @Test("unrecognized instructions return example suggestions")
    func unrecognizedReturnsSuggestions() {
        for text in ["", "do something cool", "xyzzy", "teleport the clip"] {
            switch AssistantCommandParser.parse(text) {
            case .unrecognized(let suggestions):
                #expect(!suggestions.isEmpty)
            case .recognized:
                Issue.record("Expected \"\(text)\" to be unrecognized")
            }
        }
    }

    @Test("percentage and bare ratio volume parsing")
    func volumeParsing() {
        #expect(intent("set volume to 75%")?.action == .setVolume(0.75))
        #expect(intent("set volume to 120%")?.action == .setVolume(1.2))
        // Bare numbers > 2 are treated as percentages.
        #expect(intent("set volume to 80")?.action == .setVolume(0.8))
    }

    @Test("fade seconds parsing accepts several phrasings")
    func fadeSecondsParsing() {
        #expect(intent("add a 1.5s fade")?.action == .setFade(1.5))
        #expect(intent("add a 3 second fade to all clips")?.action == .setFade(3))
        #expect(intent("fade everything")?.action == .setFade(1))
    }

    @Test("targets resolve from synonyms")
    func targetSynonyms() {
        #expect(intent("mute the music")?.target == .audioClips)
        #expect(intent("blur all titles")?.target == .textClips)
        #expect(intent("brighten everything")?.target == .allClips)
        #expect(intent("blur this")?.target == .selection)
    }

    @Test("example commands are non-empty and stable")
    func exampleCommandsExist() {
        #expect(AssistantCommandParser.exampleCommands.count >= 5)
    }
}

/// Wiring visibility for the assistant UI (not a completion criterion by
/// itself — see spec DoD §1.3).
@Suite("Assistant Static Contract")
struct AssistantStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("view model parses and executes assistant intents")
    func viewModelExecutes() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("func runAssistantCommand"))
        #expect(viewModel.contains("AssistantCommandParser.parse"))
        #expect(viewModel.contains("func executeAssistantIntent"))
        #expect(viewModel.contains("assistantTargetClips"))
    }

    @Test("inspector exposes the assistant panel")
    func inspectorExposesPanel() throws {
        let inspector = try source("App/MovieCutMac/InspectorPanel.swift")
        #expect(inspector.contains("AssistantSection"))
        #expect(inspector.contains("runAssistantCommand"))
        #expect(inspector.contains("AI Assistant"))
    }
}
