import AVFoundation
import Foundation
import Testing
@testable import MovieCutCore

/// F-17 text-to-speech: voice value types, option defaults, input validation,
/// and a guarded real-synthesis integration check.
@Suite("Text To Speech")
struct TextToSpeechTests {
    @Test("voice display name combines name and language")
    func voiceDisplayName() {
        let voice = TextToSpeechVoice(id: "x", name: "Samantha", language: "en-US")
        #expect(voice.displayName == "Samantha (en-US)")
    }

    @Test("available voices are sorted by language then name")
    func availableVoicesSorted() {
        let voices = TextToSpeechSynthesizer.availableVoices()
        // Platform may expose zero voices in a headless sandbox; only assert
        // ordering when at least two are present.
        guard voices.count >= 2 else { return }
        for (previous, next) in zip(voices, voices.dropFirst()) {
            let inOrder = previous.language < next.language
                || (previous.language == next.language && previous.name <= next.name)
            #expect(inOrder)
        }
    }

    @Test("default options match the documented neutral values")
    func defaultOptions() {
        let options = TextToSpeechSynthesizer.Options()
        #expect(options.voiceIdentifier == nil)
        #expect(options.rate == 0.5)
        #expect(options.pitchMultiplier == 1.0)
        #expect(options.volume == 1.0)
    }

    @Test("empty text throws before any synthesis")
    @MainActor
    func emptyTextThrows() async {
        let synthesizer = TextToSpeechSynthesizer()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-empty-\(UUID().uuidString).caf")

        // do/catch instead of `await #expect(throws:)`: Xcode 16's older
        // swift-testing macro sends the @MainActor closure into a nonisolated
        // macro implementation, which strict concurrency rejects.
        do {
            _ = try await synthesizer.synthesize(text: "   \n  ", to: url)
            Issue.record("expected synthesize to throw for blank text")
        } catch let error as TextToSpeechError {
            if case .emptyText = error {
                // expected
            } else {
                Issue.record("unexpected TextToSpeechError: \(error)")
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("real synthesis writes a playable audio file when voices exist")
    @MainActor
    func realSynthesisProducesAudio() async throws {
        // Guarded integration test: skip when the headless environment has no
        // installed voices or produces no audio (mirrors guarded-pixel tests).
        guard !TextToSpeechSynthesizer.availableVoices().isEmpty else {
            print("Skipping TTS synthesis: no system voices available.")
            return
        }

        let synthesizer = TextToSpeechSynthesizer()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tts-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let duration: TimeInterval
        do {
            duration = try await synthesizer.synthesize(text: "Hello from MovieCut.", to: url)
        } catch TextToSpeechError.noAudioProduced {
            print("Skipping TTS synthesis: platform produced no audio.")
            return
        }

        #expect(duration > 0)
        #expect(FileManager.default.fileExists(atPath: url.path))

        // The written file should be a readable audio asset with the same
        // approximate duration the synthesizer reported.
        let asset = AVURLAsset(url: url)
        let assetDuration = try await asset.load(.duration).seconds
        #expect(assetDuration > 0)
        #expect(abs(assetDuration - duration) < 0.5)
    }
}

/// Wiring visibility for the TTS UI (not a completion criterion by itself —
/// see spec DoD §1.3).
@Suite("Text To Speech Static Contract")
struct TextToSpeechStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("view model generates speech aligned to the text clip")
    func viewModelGeneratesSpeech() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("func generateSpeechFromSelectedText"))
        #expect(viewModel.contains("TextToSpeechSynthesizer"))
        #expect(viewModel.contains("timelineRange: TimeRange(start: textClip.timelineRange.start"))
        #expect(viewModel.contains("var canGenerateSpeechFromSelection"))
        #expect(viewModel.contains("func loadTTSVoices"))
    }

    @Test("inspector exposes a voice picker and generate button")
    func inspectorExposesTTS() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        #expect(inspector.contains("textToSpeechControls"))
        #expect(inspector.contains("Generate Voice"))
        #expect(inspector.contains("ttsVoices"))
    }
}
