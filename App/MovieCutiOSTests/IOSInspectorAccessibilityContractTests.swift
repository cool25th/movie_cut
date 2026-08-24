import Foundation
import Testing

/// A11Y-01 (CA-06 matrix): the iOS inspector sub-views carried no explicit
/// accessibility labels — sliders announced as bare "slider" and the filter
/// picker's selection checkmark was invisible to VoiceOver. These contracts
/// pin the presence of the fix at the source level (the same pinning pattern
/// as the Mac UX-08 contracts).
@Suite("iOS inspector accessibility contract (A11Y-01)")
struct IOSInspectorAccessibilityContractTests {
    /// Simulator test hosts don't run with the repo root as CWD (unlike the
    /// Mac hosted tests) — resolve sources relative to this file instead.
    private func source(_ path: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MovieCutiOSTests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // repo root
        return try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("effects inspector sliders are labeled with values")
    func effectsInspectorSlidersLabeled() throws {
        let view = try source("App/MovieCutiOS/Views/IOSEffectsInspectorView.swift")
        #expect(view.contains(".accessibilityLabel(Text(title))"))
        #expect(view.contains(".accessibilityLabel(Text(opacityTitle))"))
        #expect(view.contains(".accessibilityLabel(Text(speedTitle))"))
        #expect(view.components(separatedBy: ".accessibilityValue").count - 1 >= 3)
    }

    @Test("chroma key sliders are labeled with percent values")
    func chromaKeySlidersLabeled() throws {
        let view = try source("App/MovieCutiOS/Views/IOSChromaKeyView.swift")
        #expect(view.contains(".accessibilityLabel(Text(title))"))
        #expect(view.contains(".accessibilityValue(Text("))
    }

    @Test("filter picker announces selection state")
    func filterPickerAnnouncesSelection() throws {
        let view = try source("App/MovieCutiOS/Views/IOSFilterPickerView.swift")
        #expect(view.contains(".accessibilityLabel(filter.name)"))
        #expect(view.contains(".accessibilityValue(isSelected(filter) ? \"Selected\" : \"\")"))
    }

    @Test("export progress sheet exposes progress value and cancel semantics")
    func exportProgressSheetAccessible() throws {
        let view = try source("App/MovieCutiOS/iOSContentView.swift")
        #expect(view.contains(".accessibilityLabel(\"Export progress\")"))
        #expect(view.contains(".accessibilityValue(exportProgressAccessibilityValue)"))
        #expect(view.contains("Button(\"Cancel Export\", role: .destructive"))
    }
}
