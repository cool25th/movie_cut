import Foundation
import Testing

/// P3 documentation cleanup keeps the CapCut handoff docs aligned with the
/// implemented IA/P0/P1/P2 polish state without overclaiming fresh verification.
@Suite("P3 Docs Cleanup StaticContract")
struct P3DocsCleanupStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw P3DocsCleanupStaticContractError.missingMarker(start)
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw P3DocsCleanupStaticContractError.missingMarker(end)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Parity requirements have no stale R1-02 or R2-04 failure rows")
    func parityRequirementsHaveNoStaleCompletedFailureRows() throws {
        let requirements = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")
        let currentState = try section(
            in: requirements,
            from: "**핵심 상태:**",
            to: "**IA/menu-position pass (2026-06-19):**"
        )

        #expect(!requirements.contains("| R1-02 | 프로젝트명 + **저장상태** 인디케이터 | ❌"))
        #expect(!requirements.contains("| R2-04 | hover 미리듣기/미리보기 | ❌"))
        #expect(!currentState.contains("- ❌ 라이브러리 **hover 미리보기**."))
        #expect(!currentState.contains("- ❌ 상단 바 **프로젝트명·저장상태**."))
        #expect(currentState.contains("상단 바 **프로젝트명·저장상태**(R1-02"))
        #expect(currentState.contains("라이브러리 **hover 미리듣기/미리보기**(R2-04"))
    }

    @Test("Latest Loop 6 metric evidence and caveat are recorded")
    func latestLoop6MetricEvidenceAndCaveatAreRecorded() throws {
        let requirements = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")
        let showcase = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        for docs in [requirements, showcase] {
            #expect(docs.contains("/tmp/moviecut-ui-evidence/current-loop/resume-20260619-004321/metrics_capcut_vs_moviecut_loop6_text_selected.json"))
            #expect(docs.contains("0.7528 >= 0.75"))
            #expect(docs.contains("0.0850 <= 0.15"))
            #expect(docs.contains("fresh"))
            #expect(docs.contains("populated"))
            #expect(docs.contains("recapture"))
        }

        #expect(requirements.contains("Loop 3/4 blockers(mean 0.6746, worst dark_fill 0.1996, preview_center 0.488, right_inspector 0.624)는 resolved metric history"))
        #expect(showcase.contains("Historical Loop 3 note"))
        #expect(showcase.contains("Historical Loop 4 note"))
        #expect(showcase.contains("does **not** claim a fresh matching populated side-by-side recapture after P2"))
    }

    @Test("IA P0 P1 P2 and P3 cleanup notes are recorded")
    func iaPolishAndP3CleanupNotesAreRecorded() throws {
        let requirements = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")
        let uiux = try source("docs/UIUX_HANDOFF.md")
        let showcase = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")
        let audit = try source("docs/MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md")

        for docs in [requirements, uiux, showcase] {
            #expect(docs.contains("IA/menu-position"))
            #expect(docs.contains("P0/P1/P2 polish"))
            #expect(docs.contains("matching populated side-by-side recapture/metrics"))
            #expect(docs.contains("standard workflow"))
        }

        #expect(uiux.contains("P3 docs cleanup performed"))
        #expect(audit.contains("P3 documentation cleanup refreshed"))
        #expect(audit.contains("Static contracts should guard against reverting the recommended next prompt to P0 implementation"))
    }

    @Test("Recommended next prompt prioritizes verification not P0 implementation")
    func recommendedNextPromptPrioritizesVerificationNotP0Implementation() throws {
        let audit = try source("docs/MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md")
        let prompt = try section(
            in: audit,
            from: "## Recommended next implementation prompt",
            to: "Main goals:"
        )
        let goals = String(audit[audit.range(of: "Main goals:")!.lowerBound...])

        #expect(prompt.contains("Continue with prioritized verification/backlog cleanup, not P0 implementation."))
        #expect(prompt.contains("Docs/tests only"))
        #expect(prompt.contains("Do not claim fresh post-P2 populated visual verification until matching recapture evidence exists."))
        #expect(prompt.contains("git diff --check"))
        #expect(prompt.contains("swift build"))
        #expect(prompt.contains("swift test --filter StaticContract"))
        #expect(!prompt.contains("Implement P0: left browser + timeline populated-state polish."))
        #expect(!goals.contains("Make left browser feel like a CapCut-style content browser"))
        #expect(goals.contains("Rebuild matching populated side-by-side evidence after IA/P0/P1/P2"))
        #expect(goals.contains("Complete standard workflow walkthroughs"))
        #expect(goals.contains("Decide optional scope"))
    }

    @Test("Remaining backlog is explicit without overclaiming verification")
    func remainingBacklogIsExplicitWithoutOverclaimingVerification() throws {
        let requirements = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")
        let uiux = try source("docs/UIUX_HANDOFF.md")
        let showcase = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(requirements.contains("P2 선택 backlog"))
        #expect(requirements.contains("R2-01 9탭 확장과 Captions/Adjust panel depth"))
        #expect(requirements.contains("Verification backlog"))
        #expect(requirements.contains("optional iOS sync decision"))
        #expect(uiux.contains("optional iOS sync decision"))
        #expect(showcase.contains("Evidence caveat"))
        #expect(requirements.contains("fresh populated recapture를 완료했다고 주장하지 않음"))
        #expect(!uiux.contains("fresh post-P2 populated recapture complete"))
        #expect(!showcase.contains("fresh post-P2 populated recapture complete"))
    }
}

private enum P3DocsCleanupStaticContractError: Error {
    case missingMarker(String)
}
