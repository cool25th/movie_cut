import Foundation
import Testing

/// U-08 regression lock only: the real completion evidence is produced by
/// scripts/ui_capture.sh and scripts/ui_regression.sh against image artifacts.
///
/// The capture/regression scripts were generalized to NAMED editor states
/// (moviecut_<state>_raw.png / golden_<state>.png), so these checks look for
/// the parametrized pattern rather than a single hardcoded filename. The real
/// proof that the gate works is the dhash comparison running in nightly, not
/// these string checks.
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
        #expect(capture.contains("screencapture -x -R"))
        // Parametrized per-state output: moviecut_<state>_raw.png
        #expect(capture.contains("moviecut_${state}_raw.png"))

        #expect(regression.contains("Tests/UIEvidence"))
        #expect(regression.contains("--update-golden"))
        // Parametrized per-state golden: golden_<state>.png
        #expect(regression.contains("golden_${state}.png"))
        #expect(regression.contains("scale=9:8,format=gray"))
        #expect(regression.contains("distance > threshold"))
        #expect(regression.contains("FAIL (no capture"))
        #expect(regression.contains("FAIL (no committed golden"))
        #expect(regression.contains("for golden in \"$GOLDEN_DIR\"/golden_*.png"))
        #expect(!regression.contains("SKIP (no capture"))
        #expect(!regression.contains("SKIP (no committed golden"))
    }

    @Test("U-08 committed editor goldens exist")
    func u08CommittedEditorGoldensExist() throws {
        // At least the baseline states must have committed goldens under
        // Tests/UIEvidence/. This is a real filesystem check, not a string one.
        for state in ["import_only", "populated_editor"] {
            let url = URL(fileURLWithPath: "Tests/UIEvidence/golden_\(state).png")
            #expect(FileManager.default.fileExists(atPath: url.path),
                    "missing committed golden for state '\(state)' at \(url.path)")
        }
    }
}
