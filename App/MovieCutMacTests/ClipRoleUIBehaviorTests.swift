import CoreGraphics
import MovieCutCore
import SwiftUI
import Testing
@testable import MovieCutMac

/// CA-20 stage 2-A: the Mac role UI's view-model surface — preset upsert +
/// selection assignment through the Core commands, lane-dominance math the
/// timeline tint reads, and the hex color parse. (Lane goldens/VoiceOver
/// walkthrough are the stage-2-B manual axis; these pin the logic beneath.)
@MainActor
@Suite("Clip role UI behavior (CA-20 2-A)")
struct ClipRoleUIBehaviorTests {
    private func makeViewModel(clipCount: Int = 3) -> EditorViewModel {
        let clips = (0..<clipCount).map { _ in
            Clip(assetId: nil, kind: .video,
                 sourceRange: TimeRange(start: 0, duration: 1),
                 timelineRange: TimeRange(start: 0, duration: 1))
        }
        return EditorViewModel(project: Project(
            name: "roles-ui",
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: clips)
            ])
        ))
    }

    @Test("role lanes are opt-in (off by default)")
    func toggleDefaultsOff() {
        #expect(makeViewModel().showRoleLanes == false)
    }

    @Test("hex parse: valid hex matches components, malformed falls back to black")
    func hexParse() {
        let valid = EditorViewModel.roleColor(fromHex: "#4C9BE8")
        let ns = NSColor(valid).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent - 0x4C / 255.0) < 0.005)
        #expect(abs(ns.greenComponent - 0x9B / 255.0) < 0.005)
        #expect(abs(ns.blueComponent - 0xE8 / 255.0) < 0.005)

        for malformed in ["", "#12345", "zzzzzz", "#GGHHII"] {
            let fallback = EditorViewModel.roleColor(fromHex: malformed)
            let fb = NSColor(fallback).usingColorSpace(.sRGB)!
            #expect(fb.redComponent == 0 && fb.greenComponent == 0 && fb.blueComponent == 0,
                    "\(malformed) must fall back to black, not crash")
        }
    }

    @Test("dominantRole: nil for untagged, majority wins, tie breaks by registry order")
    func dominance() async throws {
        let vm = makeViewModel(clipCount: 3)
        let track = vm.currentProject.timeline.tracks[0]
        #expect(vm.dominantRole(for: track) == nil, "untagged lane has no dominant role")

        // Tag 2/3 with Music, 1/3 with Dialogue (registry: Dialogue first).
        try await vm.assignRole(TimelineRole.presets[1], to: [track.clips[0].id, track.clips[1].id])
        try await vm.assignRole(TimelineRole.presets[0], to: [track.clips[2].id])

        let updated = vm.currentProject.timeline.tracks[0]
        #expect(vm.dominantRole(for: updated)?.name == "Music",
                "2-of-3 majority wins over registry order")

        // 1-1 tie (clear one Music): the tie-break is REGISTRY order — which
        // is insertion order (Music was assigned first), NOT preset-list
        // order. Either is fine; what matters is determinism (no BUG-ACC-04
        // coin-flip tint).
        try await vm.clearRole(from: [updated.clips[0].id])
        let tied = vm.currentProject.timeline.tracks[0]
        #expect(vm.dominantRole(for: tied)?.name == "Music",
                "a tie must break by registry (insertion) order, deterministically")
    }

    @Test("assignRoleToSelection upserts the preset registry and tags the selection")
    func assignmentThroughCommands() async throws {
        let vm = makeViewModel(clipCount: 2)
        let clipIds = vm.currentProject.timeline.tracks[0].clips.map(\.id)
        vm.selectedClipIds = [clipIds[0]]

        #expect(vm.timelineRoles.isEmpty, "registry starts empty")

        await vm.assignRoleToSelection(TimelineRole.presets[0])
        #expect(vm.timelineRoles.map(\.name) == ["Dialogue"],
                "picking an absent preset registers it exactly once")
        #expect(vm.selectedClipsRole?.name == "Dialogue")
        #expect(vm.lastErrorMessage == nil)
        #expect(vm.lastStatusMessage?.contains("Dialogue") == true)

        // Re-assigning the same preset must not duplicate the registry entry.
        await vm.assignRoleToSelection(TimelineRole.presets[0])
        #expect(vm.timelineRoles.count == 1)

        await vm.clearRoleOnSelection()
        #expect(vm.selectedClipsRole == nil)
        #expect(vm.timelineRoles.count == 1,
                "clearing tags keeps the registry entry (other clips may still use it)")
    }
}
