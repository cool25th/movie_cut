import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// CA-26 — LUT re-export behavior at the ViewModel level (P2 review fix).
///
/// Re-exporting an imported external LUT must copy the MANAGED ORIGINAL
/// FILE byte-for-byte. The previous parse → clamp → serialize path silently
/// dropped DOMAIN lines, comments, the original title, source precision,
/// and out-of-0…1 values — a normalized rewrite that must not be called
/// "lossless". The bake path (color correction → new LUT) stays serialized
/// by design; same source/destination must be a safe no-op.
@MainActor
@Suite("LUT export re-export (CA-26)")
struct LUTExportBehaviorTests {
    /// A cube the parser could NOT faithfully preserve: extended DOMAIN
    /// range, comments, and negative / >1 data values.
    private let managedCube = """
        TITLE "Managed Original"
        # export must preserve this comment line byte-for-byte
        DOMAIN_MIN -0.25 -0.1 0.0
        DOMAIN_MAX 1.5 1.2 1.0

        LUT_3D_SIZE 2
        -0.100000 1.250000 0.500000
        0.123456 0.654321 0.111111
        0.999000 0.500000 0.250000
        1.400000 -0.200000 0.800000
        0.100000 0.900000 0.400000
        0.600000 0.200000 1.100000
        0.750000 0.750000 0.750000
        0.325000 0.125000 0.975000
        """

    private func makeViewModel(lutPath: String?) -> EditorViewModel {
        var effects: [Effect] = []
        if let lutPath {
            effects.append(Effect(
                type: .externalLUT,
                parameters: ["intensity": 1.0],
                lutPath: lutPath
            ))
        }
        let clip = Clip(
            assetId: UUID(),
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1),
            effects: effects
        )
        let vm = EditorViewModel(project: Project(
            name: "lut-export",
            mediaLibrary: MediaLibrary(assets: [:]),
            timeline: Timeline(canvasSize: CGSize(width: 100, height: 100), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
            ])
        ))
        vm.selectedClipIds = [clip.id]
        return vm
    }

    @Test("re-export copies the managed original byte-for-byte, DOMAIN/comments/out-of-range intact")
    func reExportIsByteForByte() async throws {
        let managedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca26-managed-\(UUID().uuidString).cube")
        try managedCube.write(to: managedURL, atomically: true, encoding: .utf8)

        let vm = makeViewModel(lutPath: managedURL.path)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca26-reexport-\(UUID().uuidString).cube")

        await vm.exportLUTForSelectedClip(to: destination)
        #expect(vm.lastErrorMessage == nil, "export failed: \(vm.lastErrorMessage ?? "")")

        let original = try Data(contentsOf: managedURL)
        let exported = try Data(contentsOf: destination)
        #expect(exported == original, "re-export must be a byte-for-byte copy of the managed file")
        #expect(String(data: exported, encoding: .utf8)?.contains("DOMAIN_MIN -0.25") == true)
        #expect(String(data: exported, encoding: .utf8)?.contains("# export must preserve") == true)

        try? FileManager.default.removeItem(at: managedURL)
        try? FileManager.default.removeItem(at: destination)
    }

    @Test("re-exporting onto the managed original itself is a safe no-op")
    func sameSourceAndDestinationIsSafe() async throws {
        let managedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca26-same-\(UUID().uuidString).cube")
        try managedCube.write(to: managedURL, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: managedURL)

        let vm = makeViewModel(lutPath: managedURL.path)
        await vm.exportLUTForSelectedClip(to: managedURL)

        #expect(vm.lastErrorMessage == nil,
                "same source/destination must succeed, not throw: \(vm.lastErrorMessage ?? "")")
        let after = try Data(contentsOf: managedURL)
        #expect(after == before, "the managed original must be untouched")

        try? FileManager.default.removeItem(at: managedURL)
    }

    @Test("bake path writes a normalized new LUT for color-correction clips")
    func bakePathSerializesNewLUT() async throws {
        var clip = Clip(
            assetId: UUID(),
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1)
        )
        clip.colorCorrection = ColorCorrection(brightness: 0.2, contrast: 1.15)
        let vm = EditorViewModel(project: Project(
            name: "lut-bake",
            mediaLibrary: MediaLibrary(assets: [:]),
            timeline: Timeline(canvasSize: CGSize(width: 100, height: 100), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
            ])
        ))
        vm.selectedClipIds = [clip.id]

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca26-bake-\(UUID().uuidString).cube")
        await vm.exportLUTForSelectedClip(to: destination)

        #expect(vm.lastErrorMessage == nil, "bake failed: \(vm.lastErrorMessage ?? "")")
        let text = try String(contentsOf: destination, encoding: .utf8)
        #expect(text.contains("LUT_3D_SIZE 33"))
        // A baked cube is generated content: parsed back it must be valid.
        let reparsed = try CubeLUTParser.parse(contentsOf: destination)
        #expect(reparsed.dimension == 33)

        try? FileManager.default.removeItem(at: destination)
    }
}
