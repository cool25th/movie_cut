import Foundation
import Testing
@testable import MovieCutCore

/// QAUTO-06 — seeded command torture: deterministic random command
/// sequences through `EditorSession`, asserting the session's core
/// contracts under ARBITRARY orderings (the order real users never
/// produce, and hand-written sequences never cover):
///
///   C1 — a dispatch that throws leaves the project EXACTLY unchanged
///        (invalid commands are rejections, not partial mutations);
///   C2 — undo after any applied command restores the pre-command project
///        exactly, and redo restores the post-command project exactly
///        (snapshot-based undo integrity);
///   C3 — the project JSON round-trips (encode → decode → equal) at
///        regular intervals regardless of what the sequence did.
///
/// Reproducibility: the RNG is SplitMix64 seeded per sequence; a failure
/// message carries `seed`/`step` so the exact failing sequence is a
/// regression fixture (rerun by pinning the seed).
@Suite("Seeded command torture (QAUTO-06)")
struct CommandTortureTests {

    /// SplitMix64 — small, deterministic, dependency-free.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A small but structurally rich project: video (3 clips), audio (1),
    /// text (1 word-timed card), one marker.
    private func makeProject() -> Project {
        let assetId = UUID()
        var clips: [Clip] = []
        for index in 0..<3 {
            clips.append(Clip(
                assetId: assetId,
                kind: .video,
                sourceRange: TimeRange(start: 0, duration: 4),
                timelineRange: TimeRange(start: Double(index) * 4, duration: 4)
            ))
        }
        let audio = Clip(
            assetId: assetId, kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 6),
            timelineRange: TimeRange(start: 0, duration: 6)
        )
        let text = Clip(
            kind: .text,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 1, duration: 2),
            textContent: TextClipContent(
                text: "torture words here",
                wordTimings: [
                    WordTiming(text: "torture", startTime: 0.0, endTime: 0.5, confidence: 1),
                    WordTiming(text: "words", startTime: 0.5, endTime: 1.0, confidence: 1),
                    WordTiming(text: "here", startTime: 1.0, endTime: 1.5, confidence: 1),
                ]
            )
        )
        var project = Project(
            name: "torture",
            mediaLibrary: MediaLibrary(assets: [
                assetId: MediaAsset(
                    originalURL: URL(fileURLWithPath: "/scratch/torture.mp4"),
                    kind: .video, duration: 12
                ),
            ]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: clips),
                Track(kind: .audio, name: "A", zIndex: 1, clips: [audio]),
                Track(kind: .text, name: "T", zIndex: 2, clips: [text]),
            ])
        )
        project.markers = [Marker(time: 2, name: "seed marker")]
        return project
    }

    /// Builds the next command from the CURRENT project state (so targets
    /// are always plausible) and the RNG — deterministic per (seed, step).
    private func nextCommand(
        for project: Project, rng: inout SeededRNG
    ) -> any EditorCommand {
        struct TrackClip {
            let trackId: UUID
            let clip: Clip
        }
        let targets = project.timeline.tracks.flatMap { track in
            track.clips.map { TrackClip(trackId: track.id, clip: $0) }
        }
        // Always-valid fallback when the timeline is empty.
        guard let target = targets.randomElement(using: &rng) else {
            return AddMarkerCommand(marker: Marker(
                time: Double.random(in: 0...5, using: &rng), name: "t"
            ))
        }
        let clip = target.clip
        let track = project.timeline.tracks.first { $0.id == target.trackId }!

        switch Int.random(in: 0..<8, using: &rng) {
        case 0:  // split inside the clip's span (sometimes at bad edges)
            let span = clip.timelineRange
            let time = Int.random(in: 0..<4, using: &rng) == 0
                ? span.start - 1  // deliberately invalid edge
                : Double.random(in: span.start..<(span.start + span.duration), using: &rng)
            return SplitClipCommand(
                clipId: clip.id, trackId: track.id, splitTime: time, newClipId: UUID()
            )
        case 1:
            return DeleteClipCommand(clipId: clip.id)
        case 2:
            return RippleDeleteCommand(clipId: clip.id)
        case 3:
            return MoveClipCommand(
                clipId: clip.id,
                targetTrackId: track.id,
                newTimelineRange: TimeRange(
                    start: Double.random(in: -2...10, using: &rng),
                    duration: clip.timelineRange.duration
                )
            )
        case 4:
            return SetVolumeCommand(clipId: clip.id, volume: Double.random(in: 0...2, using: &rng))
        case 5:
            return SetClipSpeedCommand(
                clipId: clip.id,
                trackId: track.id,
                change: .constantRate(Double.random(in: 0.5...2.0, using: &rng))
            )
        case 6:
            return AddMarkerCommand(marker: Marker(
                time: Double.random(in: 0...12, using: &rng), name: "t\(Int.random(in: 0..<99, using: &rng))"
            ))
        default:
            return SetColorCorrectionCommand(
                clipId: clip.id,
                colorCorrection: ColorCorrection(
                    brightness: Double.random(in: 0...1, using: &rng),
                    contrast: Double.random(in: 0...2, using: &rng)
                )
            )
        }
    }

    @Test("10 seeded sequences × 120 commands hold the session contracts")
    func seededTorture() async throws {
        for seed: UInt64 in 1...10 {
            var rng = SeededRNG(state: seed &* 0x2545_F491_4F6C_DD1D)
            let session = EditorSession(project: makeProject())

            for step in 0..<120 {
                let before = await session.snapshot()
                let command = nextCommand(for: before, rng: &rng)

                let applied: Bool
                do {
                    try await session.dispatch(command)
                    applied = true
                } catch {
                    // C1: a rejected command must not mutate anything.
                    let afterRejection = await session.snapshot()
                    #expect(afterRejection == before,
                            "seed \(seed) step \(step): a throwing dispatch mutated the project")
                    applied = false
                }
                guard applied else { continue }

                let after = await session.snapshot()

                // C2: undo/redo restore the exact neighboring states.
                try await session.undo()
                let undone = await session.snapshot()
                #expect(undone == before,
                        "seed \(seed) step \(step): undo did not restore the pre-command project")
                try await session.redo()
                let redone = await session.snapshot()
                #expect(redone == after,
                        "seed \(seed) step \(step): redo did not restore the post-command project")

                // C3: periodic persistence round-trip.
                if step % 10 == 0 {
                    let data = try JSONEncoder().encode(after)
                    let decoded = try JSONDecoder().decode(Project.self, from: data)
                    #expect(decoded == after,
                            "seed \(seed) step \(step): project did not round-trip through JSON")
                }
            }
        }
    }
}
