import Foundation
import MovieCutCore
import Testing

/// The macOS recorder UI and app Info.plist live outside the SwiftPM core
/// target. These checks keep the real microphone recording workflow visible in
/// the faster static contract loop.
@Suite("Voiceover Recording StaticContract")
struct VoiceoverRecordingStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw VoiceoverRecordingStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw VoiceoverRecordingStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Mac app declares microphone usage description")
    func macInfoPlistContainsMicrophoneUsageDescription() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "App/MovieCutMac/Info.plist"))
        let rawPlist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let plist = try #require(rawPlist as? [String: Any])
        let description = try #require(plist["NSMicrophoneUsageDescription"] as? String)

        #expect(!description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(description.localizedCaseInsensitiveContains("microphone"))
        #expect(description.localizedCaseInsensitiveContains("voiceover"))
    }

    @Test("Mac voiceover view records with VoiceoverRecorder and saves measured duration")
    func macVoiceoverViewUsesRealRecorderWorkflow() throws {
        let source = try source("App/MovieCutMac/Recording/VoiceoverRecordingView.swift")
        let stopRecording = try section(
            in: source,
            from: "private func stopRecording()",
            to: "private func cancelRecording()"
        )
        let saveToTimeline = try section(
            in: source,
            from: "private func addVoiceoverToTimeline",
            to: "private func requestMicrophoneAccessIfNeeded"
        )

        #expect(source.contains("@State private var recorder: VoiceoverRecorder?"))
        #expect(source.contains("try newRecorder.startRecording(to: url)"))
        #expect(stopRecording.contains("let finalDuration = max(recorder.currentTime, elapsedTime)"))
        #expect(stopRecording.contains("let url = try recorder.stopRecording()"))
        #expect(stopRecording.contains("self.recorder = nil"))
        #expect(stopRecording.contains("await addVoiceoverToTimeline(url: url, fallbackDuration: finalDuration)"))
        #expect(source.contains("recorder?.cancelRecording()"))
        #expect(source.contains(".onDisappear"))
        #expect(source.contains("cancelRecording()"))

        #expect(source.contains("@State private var isSavingToTimeline = false"))
        #expect(source.contains("ProgressView()"))
        #expect(source.contains(".disabled(isSavingToTimeline)"))
        #expect(saveToTimeline.contains("defer { isSavingToTimeline = false }"))
        #expect(saveToTimeline.contains("viewModel.addVoiceoverAudio(from: url, fallbackDuration: fallbackDuration)"))

        #expect(source.contains("AVCaptureDevice.authorizationStatus(for: .audio)"))
        #expect(source.contains("AVCaptureDevice.requestAccess(for: .audio)"))
        #expect(source.contains("microphoneHelpMessage"))
        #expect(!source.contains("AVAudioSession"))

        #expect(source.contains(".accessibilityLabel(\"Record voiceover\")"))
        #expect(source.contains(".accessibilityHint(\"Starts recording from the default microphone.\")"))
        #expect(source.contains(".accessibilityLabel(\"Stop and save voiceover\")"))
        #expect(source.contains(".accessibilityLabel(\"Cancel voiceover recording\")"))
        #expect(source.contains(".accessibilityLabel(\"Voiceover timer"))
        #expect(source.contains(".accessibilityLabel(\"Input level\")"))
        #expect(source.contains(".accessibilityValue(\"\\(Int((audioLevel * 100).rounded())) percent\")"))
    }

    @Test("Editor voiceover import uses readable audio duration then fallback")
    func editorVoiceoverAudioUsesReadableDurationThenFallback() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        let resolver = try section(
            in: source,
            from: "private func resolvedVoiceoverDuration",
            to: "private func defaultTrackName"
        )
        let addVoiceover = try section(
            in: source,
            from: "func addVoiceoverAudio(from url: URL, fallbackDuration: TimeInterval? = nil) async",
            to: "// MARK: - Phase 3-2"
        )

        #expect(source.contains("private static let minimumVoiceoverDuration: TimeInterval = 0.1"))
        #expect(resolver.contains("audioDuration(for: url)"))
        #expect(resolver.contains("sanitizedDuration(fallbackDuration)"))
        #expect(resolver.contains("Self.minimumVoiceoverDuration"))
        #expect(addVoiceover.contains("var asset = MediaImporter.probe(url: url)"))
        #expect(addVoiceover.contains("let duration = resolvedVoiceoverDuration(for: url, fallbackDuration: fallbackDuration)"))
        #expect(addVoiceover.contains("asset.duration = duration"))
        #expect(addVoiceover.contains("sourceRange: TimeRange(start: 0, duration: duration)"))
        #expect(addVoiceover.contains("timelineRange: TimeRange(start: playheadTime, duration: duration)"))
        #expect(addVoiceover.contains("selectedClipId = clip.id"))
        #expect(!addVoiceover.contains("asset.duration ?? 5"))
        #expect(!addVoiceover.contains("?? 5"))
    }

    @Test("Voiceover CAF recordings import as audio assets")
    func voiceoverCAFRecordingsImportAsAudioAssets() {
        let asset = MediaImporter.probe(url: URL(fileURLWithPath: "/tmp/moviecut_voiceover.caf"))

        #expect(asset.kind == .audio)
    }

    @Test("Backlog marks voiceover complete and moves next P1 away from voiceover")
    func backlogMarksVoiceoverCompleteAndMovesNextPriority() throws {
        let backlog = try source("docs/CAPCUT_FEATURE_BACKLOG.md")
        let handoff = try source("docs/SESSION_HANDOFF.md")

        #expect(backlog.contains("- [x] ✅ 보이스오버 실제 마이크 녹음 (P1)"))
        #expect(backlog.contains("Mac `VoiceoverRecordingView`"))
        #expect(backlog.contains("NSMicrophoneUsageDescription"))
        #expect(backlog.contains("fallbackDuration"))
        #expect(backlog.contains("다음 1순위는 F-01 실제 Photos/Safari GUI 드래그 검증"))
        #expect(!backlog.contains("- [ ] 🟡 보이스오버 실제 마이크 녹음 (P1)"))
        #expect(!backlog.contains("다음 1순위는 보이스오버 실녹음"))

        #expect(handoff.contains("보이스오버 실녹음 배치"))
        #expect(handoff.contains("macOS Microphone 권한"))
        #expect(handoff.contains("실제 입력 하드웨어"))
        #expect(handoff.contains("| 완료 | ✅ **보이스오버 실녹음**"))
        #expect(handoff.contains("| 1 | **F-01 실기기 검증**"))
    }
}

private enum VoiceoverRecordingStaticContractError: Error {
    case missingMarker(String)
}
