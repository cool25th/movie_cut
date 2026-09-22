import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// CA-20 stage 2-B: the timeline index's view-model surface — entry
/// build/filter correctness and the reveal path. The 30-minute p95 number
/// in the DoD is measured here as an automated proxy (filter latency over
/// a 30-minute synthetic timeline); the human walkthrough (VoiceOver
/// navigation, W4-editor task timing) stays the DoD's manual (U) axis.
@MainActor
@Suite("Timeline index behavior (CA-20 2-B)")
struct TimelineIndexBehaviorTests {
    private func makeViewModel(clipCount: Int = 3, markers: [Marker] = []) -> EditorViewModel {
        var assets: [UUID: MediaAsset] = [:]
        var clips: [Clip] = []
        for i in 0..<clipCount {
            let assetId = UUID()
            assets[assetId] = MediaAsset(
                originalURL: URL(fileURLWithPath: "/scratch/scene_\(i).mp4"),
                kind: .video, duration: 5
            )
            clips.append(Clip(
                assetId: assetId, kind: .video,
                sourceRange: TimeRange(start: 0, duration: 5),
                timelineRange: TimeRange(start: TimeInterval(i) * 5, duration: 5)
            ))
        }
        var project = Project(
            name: "index",
            mediaLibrary: MediaLibrary(assets: assets),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: clips)
            ])
        )
        project.markers = markers
        return EditorViewModel(project: project)
    }

    @Test("index panel is opt-in (off by default)")
    func toggleDefaultsOff() {
        #expect(makeViewModel().showTimelineIndex == false)
    }

    @Test("entries list clips and markers in timeline order; beat markers are excluded")
    func entryBuild() {
        let marker = Marker(time: 2, name: "Intro")
        let beat = Marker(time: 3, name: "b1", kind: .beat)
        let vm = makeViewModel(clipCount: 3, markers: [marker, beat])

        let entries = vm.timelineIndexEntries()
        #expect(entries.count == 4, "3 clips + 1 user marker (beat excluded)")
        #expect(entries.map(\.title).contains("scene_0"))
        #expect(entries.map(\.title).contains("Intro"))
        #expect(!entries.map(\.title).contains("b1"))
        #expect(entries.map(\.time) == entries.map(\.time).sorted(),
                "entries are in timeline order")
    }

    @Test("filter matches title, track name, and role name case-insensitively")
    func filtering() async throws {
        let vm = makeViewModel(clipCount: 3)
        try await vm.assignRole(TimelineRole.presets[1], to: [vm.currentProject.timeline.tracks[0].clips[1].id])

        #expect(vm.timelineIndexEntries(filter: "SCENE_1").count == 1,
                "title match is case-insensitive")
        #expect(vm.timelineIndexEntries(filter: "music").map(\.title) == ["scene_1"],
                "role name matches only the tagged clip")
        #expect(vm.timelineIndexEntries(filter: "v").map(\.title).count == 3,
                "track name matches every clip on that track")
        #expect(vm.timelineIndexEntries(filter: "zzz").isEmpty)

        let markerVM = makeViewModel(markers: [Marker(time: 9, name: "Outro")])
        #expect(markerVM.timelineIndexEntries(filter: "outro").count == 1)
    }

    @Test("reveal selects and jumps clips; markers jump via the marker path")
    func reveal() {
        let marker = Marker(time: 12, name: "Intro")
        let vm = makeViewModel(clipCount: 4, markers: [marker])

        let clipEntry = vm.timelineIndexEntries().first { $0.clipId != nil }!
        vm.revealTimelineIndexEntry(clipEntry)
        #expect(vm.selectedClipIds == [clipEntry.clipId!])
        #expect(vm.playheadTime == clipEntry.time)

        let markerEntry = vm.timelineIndexEntries().first { $0.kind == .marker }!
        vm.revealTimelineIndexEntry(markerEntry)
        #expect(vm.playheadTime == 12)
        #expect(vm.selectedClipIds == [clipEntry.clipId!],
                "marker reveal moves the playhead without disturbing the selection")
    }

    @Test("30-minute timeline: filter latency p95 stays far below budget (automated proxy)")
    func thirtyMinuteP95() {
        // 360 clips x 5s = 30 minutes, plus 30 user markers — the DoD's
        // long-form scale. Pre-registered budget: p95 <= 50ms per search
        // (pure in-memory filtering; the human walkthrough timing is U).
        var markers: [Marker] = []
        for i in 0..<30 {
            markers.append(Marker(time: TimeInterval(i) * 60, name: "marker_\(i)"))
        }
        let vm = makeViewModel(clipCount: 360, markers: markers)
        #expect(vm.timelineIndexEntries().count == 390)

        let queries = (0..<200).map { i in
            if i.isMultiple(of: 3) { return "scene_\(i % 360)" }
            if i.isMultiple(of: 5) { return "marker" }
            return "s"
        }
        var samples: [Double] = []
        let clock = ContinuousClock()
        for q in queries {
            let start = clock.now
            _ = vm.timelineIndexEntries(filter: q)
            let c = start.duration(to: clock.now).components
            samples.append(Double(c.seconds) + Double(c.attoseconds) / 1e18)
        }
        samples.sort()
        let p95 = samples[Int((Double(samples.count - 1) * 0.95).rounded(.down))]
        print(String(format: "INDEXP95 entries=390 queries=%d p95=%.3fms", samples.count, p95 * 1000))
        #expect(p95 <= 0.050, "p95 exceeds the 50ms budget — measured value on the INDEXP95 line above")
    }
}

/// N1-A 1차: transcript phrase search through the index surface — the VM
/// adapter feeds subtitle cards (with karaoke word timings) into the Core
/// corpus, and reveal selects the card + seeks to the matched WORD second.
@MainActor
@Suite("Timeline index transcript search (N1-A)")
struct TimelineIndexTranscriptSearchTests {

    private func textClip(
        id: UUID = UUID(),
        text: String,
        start: TimeInterval,
        words: [WordTiming]? = nil
    ) -> Clip {
        Clip(
            id: id,
            kind: .text,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: start, duration: 2),
            textContent: TextClipContent(text: text, wordTimings: words)
        )
    }

    @Test("A cross-card phrase hits with word-level time and reveal seeks to it")
    func crossCardSearchAndReveal() {
        let firstCard = UUID()
        var project = Project(
            name: "n1",
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .text, name: "Subtitles", zIndex: 0, clips: [
                    textClip(
                        id: firstCard,
                        text: "and that is exactly why we",
                        start: 10,
                        words: [
                            WordTiming(text: "and", startTime: 0.0, endTime: 0.2, confidence: 1),
                            WordTiming(text: "that", startTime: 0.2, endTime: 0.4, confidence: 1),
                            WordTiming(text: "is", startTime: 0.4, endTime: 0.5, confidence: 1),
                            WordTiming(text: "exactly", startTime: 0.5, endTime: 0.9, confidence: 1),
                            WordTiming(text: "why", startTime: 0.9, endTime: 1.1, confidence: 1),
                            WordTiming(text: "we", startTime: 1.1, endTime: 1.3, confidence: 1),
                        ]
                    ),
                    textClip(id: UUID(), text: "shipped it early", start: 14),
                ])
            ])
        )
        project.mediaLibrary = MediaLibrary(assets: [:])
        let vm = EditorViewModel(project: project)

        let matches = vm.transcriptMatches(for: "EXACTLY why we shipped")
        #expect(matches.count == 1, "cross-card phrase must match once")
        #expect(matches[0].clipId == firstCard)
        #expect(matches[0].time == 10.5, "word-level second (exactly = 10 + 0.5), got \(matches[0].time)")

        vm.revealTranscriptMatch(matches[0])
        #expect(vm.selectedClipIds == [firstCard])
        #expect(abs(vm.playheadTime - 10.5) < 0.0001)
    }

    @Test("The transcript section never matches sticker clips")
    func stickersAreExcluded() {
        let sticker = Clip(
            kind: .text,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1),
            textContent: TextClipContent(
                text: "sparkle",
                contentKind: .sticker
            )
        )
        var project = Project(
            name: "n1-sticker",
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .text, name: "Subtitles", zIndex: 0, clips: [sticker])
            ])
        )
        project.mediaLibrary = MediaLibrary(assets: [:])
        let vm = EditorViewModel(project: project)
        #expect(vm.transcriptMatches(for: "sparkle").isEmpty)
    }
}

/// N1-B: transcript-driven deletion — "delete this sentence" and "delete
/// between two matches" both go through `AutoCutCommand`, so each pass is
/// ONE undo unit that restores the timeline exactly.
@MainActor
@Suite("Timeline index transcript delete (N1-B)")
struct TimelineIndexTranscriptDeleteTests {

    private func makeProject() -> (EditorViewModel, UUID, UUID) {
        // One 10 s video clip + two subtitle cards ([2,4) "hello world",
        // [6,8) "goodbye now") with word timings.
        let videoId = UUID()
        let assets = [videoId: MediaAsset(
            originalURL: URL(fileURLWithPath: "/scratch/talk.mp4"),
            kind: .video, duration: 10
        )]
        func card(_ text: String, _ start: TimeInterval, words: [WordTiming]) -> Clip {
            Clip(
                kind: .text,
                sourceRange: TimeRange(start: 0, duration: 2),
                timelineRange: TimeRange(start: start, duration: 2),
                textContent: TextClipContent(text: text, wordTimings: words)
            )
        }
        let hello = card("hello world", 2, words: [
            WordTiming(text: "hello", startTime: 0.0, endTime: 0.5, confidence: 1),
            WordTiming(text: "world", startTime: 0.5, endTime: 1.0, confidence: 1),
        ])
        let goodbye = card("goodbye now", 6, words: [
            WordTiming(text: "goodbye", startTime: 0.0, endTime: 0.5, confidence: 1),
            WordTiming(text: "now", startTime: 0.5, endTime: 1.0, confidence: 1),
        ])
        var project = Project(
            name: "n1b",
            mediaLibrary: MediaLibrary(assets: assets),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: [
                    Clip(
                        assetId: videoId, kind: .video,
                        sourceRange: TimeRange(start: 0, duration: 10),
                        timelineRange: TimeRange(start: 0, duration: 10)
                    ),
                ]),
                Track(kind: .text, name: "Subtitles", zIndex: 1, clips: [hello, goodbye]),
            ])
        )
        project.mediaLibrary = MediaLibrary(assets: assets)
        return (EditorViewModel(project: project), hello.id, goodbye.id)
    }

    @Test("Delete Sentence removes the card's span from every track in one undo")
    func deleteSentence() async {
        let (vm, helloId, _) = makeProject()
        let matches = vm.transcriptMatches(for: "hello world")
        #expect(matches.count == 1)
        #expect(matches[0].time == 2.0, "word 'hello' at card start")

        await vm.deleteTranscriptSentence(matches[0])

        let clips = vm.currentProject.timeline.tracks.flatMap(\.clips)
        // Nothing remains on the timeline inside [2,4).
        for clip in clips {
            #expect(!clip.timelineRange.overlaps(TimeRange(start: 2, duration: 2)),
                    "clip \(clip.timelineRange) still overlaps the deleted sentence span")
        }
        // The video clip was split around the span: two parts remain.
        let videoClips = clips.filter { $0.kind == .video }
        #expect(videoClips.count == 2, "expected the video split into 2 parts, got \(videoClips.count)")
        // ONE undo restores the exact original (F-18 AC③ atomicity).
        await vm.undo()
        let restored = vm.currentProject.timeline.tracks.flatMap(\.clips)
        #expect(restored.count == 3, "expected 3 clips back, got \(restored.count)")
        #expect(restored.contains { $0.id == helloId })
        #expect(vm.transcriptMatches(for: "hello world").count == 1)
    }

    @Test("Delete Range between two matches cuts [start, end) and one undo restores")
    func deleteRange() async {
        let (vm, _, goodbyeId) = makeProject()
        let hello = vm.transcriptMatches(for: "hello").first!
        let goodbye = vm.transcriptMatches(for: "goodbye").first!
        #expect(hello.time == 2.0)
        #expect(goodbye.time == 6.0)

        await vm.deleteTranscriptRange(from: hello, to: goodbye)

        let clips = vm.currentProject.timeline.tracks.flatMap(\.clips)
        // [2,6) is gone: the "hello world" card fell inside and was removed,
        // the goodbye card survives.
        #expect(!clips.contains { $0.id == goodbyeId && $0.timelineRange.start != 6 })
        for clip in clips where clip.id != goodbyeId {
            #expect(!clip.timelineRange.overlaps(TimeRange(start: 2, duration: 4)),
                    "clip \(clip.timelineRange) still overlaps the deleted range")
        }
        await vm.undo()
        #expect(vm.currentProject.timeline.tracks.flatMap(\.clips).count == 3)
    }

    @Test("Two matches at the same moment refuse with an explicit error")
    func sameMomentRefuses() async {
        let (vm, _, _) = makeProject()
        let hello = vm.transcriptMatches(for: "hello").first!
        await vm.deleteTranscriptRange(from: hello, to: hello)
        #expect(vm.lastErrorMessage != nil)
        #expect(vm.currentProject.timeline.tracks.flatMap(\.clips).count == 3,
                "no mutation on refusal")
    }
}

/// N1 on-demand transcription + keep-only.
@MainActor
@Suite("Timeline index on-demand transcription & keep-only (N1)")
struct TimelineIndexOnDemandTests {

    /// A deterministic in-memory provider so the on-demand pass runs the
    /// REAL subtitle-generation flow without device speech recognition.
    private struct FakeSpeechProvider: TranscriptionProvider {
        var isAvailable: Bool { true }
        var providerName: String { "Fake" }
        func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
            TranscriptionResult(segments: [
                TranscriptionSegment(
                    text: "hello world",
                    startTime: 1.0,
                    endTime: 2.0,
                    confidence: 1,
                    words: [
                        WordTiming(text: "hello", startTime: 1.0, endTime: 1.5, confidence: 1),
                        WordTiming(text: "world", startTime: 1.5, endTime: 2.0, confidence: 1),
                    ]
                ),
            ], language: language)
        }
    }

    private func makeProject() -> EditorViewModel {
        let videoId = UUID()
        let assets = [videoId: MediaAsset(
            originalURL: URL(fileURLWithPath: "/scratch/talk.mp4"),
            kind: .video, duration: 10
        )]
        var project = Project(
            name: "n1-ondemand",
            mediaLibrary: MediaLibrary(assets: assets),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: [
                    Clip(
                        assetId: videoId, kind: .video,
                        sourceRange: TimeRange(start: 0, duration: 10),
                        timelineRange: TimeRange(start: 0, duration: 10)
                    ),
                ]),
            ])
        )
        project.mediaLibrary = MediaLibrary(assets: assets)
        return EditorViewModel(project: project)
    }

    @Test("Transcribe & Search: on-demand pass creates searchable subtitles end to end")
    func onDemandTranscriptionFlow() async {
        let vm = makeProject()
        // Speech present, no subtitles → the offer is available, and a
        // phrase search finds nothing yet.
        #expect(vm.canOfferTranscriptSearchTranscription)
        #expect(vm.transcriptMatches(for: "hello world").isEmpty)

        vm.transcriptionService.currentProvider = FakeSpeechProvider()
        await vm.transcribeForTranscriptSearch()

        #expect(vm.lastErrorMessage == nil, "on-demand pass failed: \(vm.lastErrorMessage ?? "?")")
        let matches = vm.transcriptMatches(for: "hello world")
        #expect(matches.count == 1, "expected the fresh subtitles to be searchable")
        // With subtitles on the timeline the offer disappears.
        #expect(!vm.canOfferTranscriptSearchTranscription)
    }

    @Test("The offer requires speech clips and the absence of subtitles")
    func offerGating() {
        let vm = makeProject()
        #expect(vm.canOfferTranscriptSearchTranscription)

        // A project with no speech clips offers nothing and has no target.
        let empty = EditorViewModel(project: Project(
            name: "empty",
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [])
        ))
        #expect(!empty.canOfferTranscriptSearchTranscription)
        #expect(empty.transcriptSearchTranscriptionTarget() == nil)

        // With subtitle cards on the timeline there is already material to
        // search — the offer disappears.
        let (withSubtitles, _, _) = makeDeleteFixture()
        #expect(!withSubtitles.canOfferTranscriptSearchTranscription)
    }

    @Test("Keep-only between two matches keeps the span and one undo restores all")
    func keepOnlyRange() async {
        let (vm, _, _) = makeDeleteFixture()
        let hello = vm.transcriptMatches(for: "hello").first!
        let goodbye = vm.transcriptMatches(for: "goodbye").first!

        await vm.keepTranscriptRangeOnly(from: hello, to: goodbye)

        let clips = vm.currentProject.timeline.tracks.flatMap(\.clips)
        #expect(!clips.isEmpty)
        for clip in clips {
            #expect(clip.timelineRange.start >= 2.0 - 0.001 && clip.timelineRange.end <= 6.0 + 0.001,
                    "clip \(clip.timelineRange) survived outside the kept span [2,6)")
        }
        await vm.undo()
        #expect(vm.currentProject.timeline.tracks.flatMap(\.clips).count == 3)
    }

    @Test("Keep-only sentence keeps just the card span")
    func keepOnlySentence() async {
        let (vm, helloId, goodbyeId) = makeDeleteFixture()
        let hello = vm.transcriptMatches(for: "hello world").first!

        await vm.keepTranscriptSentenceOnly(hello)

        let clips = vm.currentProject.timeline.tracks.flatMap(\.clips)
        #expect(clips.contains { $0.id == helloId })
        #expect(!clips.contains { $0.id == goodbyeId })
        for clip in clips {
            #expect(clip.timelineRange.start >= 2.0 - 0.001 && clip.timelineRange.end <= 4.0 + 0.001,
                    "clip \(clip.timelineRange) survived outside the sentence span [2,4)")
        }
        await vm.undo()
        #expect(vm.currentProject.timeline.tracks.flatMap(\.clips).count == 3)
    }

    /// The N1-B delete fixture (10 s video + two subtitle cards).
    private func makeDeleteFixture() -> (EditorViewModel, UUID, UUID) {
        let videoId = UUID()
        let assets = [videoId: MediaAsset(
            originalURL: URL(fileURLWithPath: "/scratch/talk.mp4"),
            kind: .video, duration: 10
        )]
        func card(_ text: String, _ start: TimeInterval, words: [WordTiming]) -> Clip {
            Clip(
                kind: .text,
                sourceRange: TimeRange(start: 0, duration: 2),
                timelineRange: TimeRange(start: start, duration: 2),
                textContent: TextClipContent(text: text, wordTimings: words)
            )
        }
        let hello = card("hello world", 2, words: [
            WordTiming(text: "hello", startTime: 0.0, endTime: 0.5, confidence: 1),
            WordTiming(text: "world", startTime: 0.5, endTime: 1.0, confidence: 1),
        ])
        let goodbye = card("goodbye now", 6, words: [
            WordTiming(text: "goodbye", startTime: 0.0, endTime: 0.5, confidence: 1),
            WordTiming(text: "now", startTime: 0.5, endTime: 1.0, confidence: 1),
        ])
        var project = Project(
            name: "n1-keep",
            mediaLibrary: MediaLibrary(assets: assets),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: [
                    Clip(
                        assetId: videoId, kind: .video,
                        sourceRange: TimeRange(start: 0, duration: 10),
                        timelineRange: TimeRange(start: 0, duration: 10)
                    ),
                ]),
                Track(kind: .text, name: "Subtitles", zIndex: 1, clips: [hello, goodbye]),
            ])
        )
        project.mediaLibrary = MediaLibrary(assets: assets)
        return (EditorViewModel(project: project), hello.id, goodbye.id)
    }
}
