import Foundation
import Testing

/// U-08 regression lock only: the real completion evidence is produced by
/// scripts/ui_capture.sh and scripts/ui_regression.sh against image artifacts.
@Suite("UI Regression Infrastructure StaticContract")
struct UIRegressionInfrastructureStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("U-08 scripts keep committed goldens and generated artifacts separated")
    func u08ScriptsKeepCommittedGoldensAndGeneratedArtifactsSeparated() throws {
        let capture = try source("scripts/ui_capture.sh")
        let regression = try source("scripts/ui_regression.sh")

        #expect(capture.contains("artifacts/ui"))
        #expect(capture.contains("MOVIECUT_UITEST_IMPORT"))
        #expect(capture.contains("MOVIECUT_UITEST_TEXT_TEMPLATE_NAME"))
        #expect(capture.contains("screencapture -x -R"))
        #expect(capture.contains("moviecut_populated_editor_raw.png"))

        #expect(regression.contains("Tests/UIEvidence"))
        #expect(regression.contains("--update-golden"))
        #expect(regression.contains("golden_populated_editor.png"))
        #expect(regression.contains("scale=9:8,format=gray"))
        #expect(regression.contains("distance > threshold"))
    }

    @Test("U-08 committed populated editor golden exists")
    func u08CommittedPopulatedEditorGoldenExists() throws {
        let goldenURL = URL(fileURLWithPath: "Tests/UIEvidence/golden_populated_editor.png")
        #expect(FileManager.default.fileExists(atPath: goldenURL.path))
    }
}
