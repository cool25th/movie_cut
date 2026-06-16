import Foundation
import Testing

/// R1-02 keeps the project identity and save/autosave status in the native
/// macOS toolbar title area without changing persistence behavior.
@Suite("R1-02 Project Status StaticContract")
struct R102ProjectStatusStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R102ProjectStatusStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R102ProjectStatusStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("ContentView toolbar has a principal project status item before primary actions")
    func contentViewToolbarHasPrincipalProjectStatusItem() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let toolbar = try section(
            in: content,
            from: ".toolbar {",
            to: "        .sheet(isPresented: Binding("
        )

        #expect(toolbar.contains("ToolbarItem(placement: .principal)"))
        #expect(toolbar.contains("projectStatusToolbarItem"))
        #expect(toolbar.contains("ToolbarItemGroup(placement: .primaryAction)"))

        let principal = try #require(toolbar.range(of: "ToolbarItem(placement: .principal)"))
        let primary = try #require(toolbar.range(of: "ToolbarItemGroup(placement: .primaryAction)"))
        #expect(principal.lowerBound < primary.lowerBound)
    }

    @Test("Project status cluster renders name status icon and accessibility markers")
    func projectStatusClusterRendersNameStatusAndAccessibilityMarkers() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let cluster = try section(
            in: content,
            from: "private var projectStatusToolbarItem: some View",
            to: "    private var exportToolbarControl"
        )

        #expect(cluster.contains("Text(viewModel.projectDisplayName)"))
        #expect(cluster.contains("Text(viewModel.projectSaveStatusLabel)"))
        #expect(cluster.contains("Image(systemName: viewModel.projectSaveStatusSystemImage)"))
        #expect(cluster.contains(".accessibilityElement(children: .ignore)"))
        #expect(cluster.contains(#".accessibilityLabel(NSLocalizedString("Project save status", comment: ""))"#))
        #expect(cluster.contains(#".accessibilityValue("\(viewModel.projectDisplayName), \(viewModel.projectSaveStatusLabel)")"#))
        #expect(cluster.contains(#".accessibilityHint(NSLocalizedString("Shows the current project name and save or autosave status.", comment: ""))"#))
    }

    @Test("EditorViewModel exposes read-only presentation status without save side effects")
    func editorViewModelExposesPresentationStatusWithoutSaveSideEffects() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        let statusProperties = try section(
            in: viewModel,
            from: "var projectDisplayName: String",
            to: "    var mediaAssets"
        )

        #expect(statusProperties.contains("currentProject.name.trimmingCharacters(in: .whitespacesAndNewlines)"))
        #expect(statusProperties.contains(#"return trimmedName.isEmpty ? "Untitled" : trimmedName"#))
        #expect(statusProperties.contains("var projectSaveStatusLabel: String"))
        #expect(statusProperties.contains("if isSavingCurrentProject"))
        #expect(statusProperties.contains(#"return "Saving…""#))
        #expect(statusProperties.contains("if currentProjectURL != nil"))
        #expect(statusProperties.contains(#"return "Saved""#))
        #expect(statusProperties.contains(#"return "Autosave on""#))
        #expect(statusProperties.contains("var projectSaveStatusSystemImage: String"))
        #expect(statusProperties.contains(#"return "arrow.triangle.2.circlepath""#))
        #expect(statusProperties.contains(#"return "checkmark.circle""#))
        #expect(statusProperties.contains(#"return "arrow.clockwise.circle""#))
        #expect(viewModel.contains("private var currentProjectURL: URL?"))
        #expect(viewModel.contains("private var isSavingCurrentProject = false"))
        #expect(!viewModel.contains("@ObservationIgnored private var currentProjectURL"))
        #expect(!viewModel.contains("@ObservationIgnored private var isSavingCurrentProject"))
        #expect(!statusProperties.contains("projectStore.save"))
        #expect(!statusProperties.contains("saveCurrentProject()"))
        #expect(!statusProperties.contains("saveProject("))
    }

    @Test("R1-02 docs are implemented without overclaiming R1-03")
    func r102DocsAreImplementedWithoutOverclaimingR103() throws {
        let docs = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")
        let r102Row = try section(
            in: docs,
            from: "| R1-02 | 프로젝트명 + **저장상태** 인디케이터 |",
            to: "| R1-03 | 비율/해상도 배지 |"
        )

        #expect(r102Row.contains("✅ 구현(2026-06-16, Codex R1-02):"))
        #expect(r102Row.contains("`ContentView.swift` principal toolbar"))
        #expect(r102Row.contains("`EditorViewModel.swift` read-only presentation properties"))
        #expect(r102Row.contains("검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(168 tests / 43 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED"))
        #expect(docs.contains("| R1-03 | 비율/해상도 배지 | 🟡 canvas picker |"))
        #expect(!docs.contains("| R1-03 | 비율/해상도 배지 | ✅"))
        #expect(docs.contains("- **P1 완료** — R1-02, R2-02, R2-03, R2-05, R4-02, R5-02, R5-03."))
        #expect(docs.contains("- **P1 인터랙션** — R2-04, R3-01 세부 마감."))
        #expect(!docs.contains("R3-01 세부 마감, R1-02"))
    }
}

private enum R102ProjectStatusStaticContractError: Error {
    case missingMarker(String)
}
