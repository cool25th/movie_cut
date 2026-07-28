#if os(iOS)
import MovieCutCore
import SwiftUI
import AVFoundation

struct IOSAutoSubtitlesView: View {
    @Bindable var viewModel: IOSEditorViewModel

    @State private var isTranscribing = false
    @State private var progress: Double = 0
    @State private var generatedSubtitleSegments: [TranscriptionSegment] = []
    @State private var pendingSubtitleClips: [Clip] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Speech Recognition") {
                    LabeledContent("Provider", value: "Apple Speech")

                    Button {
                        Task { await generateSubtitles() }
                    } label: {
                        Label("Generate Subtitles", systemImage: "waveform.and.mic")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canGenerateSubtitles || isTranscribing)

                    if isTranscribing {
                        ProgressView(value: progress)
                    }
                }

                if generatedSubtitleSegments.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Subtitles",
                            systemImage: "captions.bubble",
                            description: Text("Select an audio or video clip, then generate subtitles.")
                        )
                    }
                } else {
                    Section("Subtitles") {
                        ForEach(generatedSubtitleSegments) { segment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(segment.text)
                                    .font(.subheadline)
                                    .lineLimit(3)

                                Text(timeRangeText(for: segment))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Section {
                        Button {
                            Task { await applyGeneratedSubtitles() }
                        } label: {
                            Label("Apply to Timeline", systemImage: "text.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pendingSubtitleClips.isEmpty || isTranscribing)
                    }
                }
            }
            .navigationTitle("Auto Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Subtitles Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "MovieCut could not generate subtitles.")
            }
        }
    }

    private var selectedTranscribableClipAndAsset: (clip: Clip, asset: MediaAsset)? {
        guard
            let clip = viewModel.selectedClip,
            let assetId = clip.assetId,
            let asset = viewModel.currentProject.mediaLibrary.assets[assetId],
            asset.kind == .audio || asset.kind == .video
        else {
            return nil
        }

        return (clip, asset)
    }

    private var canGenerateSubtitles: Bool {
        selectedTranscribableClipAndAsset != nil
    }

    @MainActor
    private func generateSubtitles() async {
        guard let selected = selectedTranscribableClipAndAsset else {
            errorMessage = "Select an audio or video clip to generate subtitles."
            return
        }

        generatedSubtitleSegments = []
        pendingSubtitleClips = []
        isTranscribing = true
        progress = 0
        defer {
            isTranscribing = false
            progress = 1
        }

        do {
            let provider = SpeechTranscriptionProvider()
            progress = 0.1
            let result = try await provider.transcribe(audioURL: selected.asset.originalURL, language: nil)
            progress = 0.9
            generatedSubtitleSegments = result.segments
            pendingSubtitleClips = subtitleClips(from: result, alignedTo: selected.clip)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func applyGeneratedSubtitles() async {
        let clips = pendingSubtitleClips
        guard !clips.isEmpty else { return }

        for clip in clips {
            guard let textContent = clip.textContent else { continue }

            viewModel.playheadTime = clip.timelineRange.start
            await viewModel.addTextClip(
                text: textContent.text,
                fontName: textContent.fontFamily,
                fontSize: textContent.fontSize,
                color: textContent.fontColor
            )

            if let clipId = viewModel.selectedClipId {
                await viewModel.trimClip(
                    clipId: clipId,
                    newStart: clip.timelineRange.start,
                    newDuration: clip.timelineRange.duration
                )
            }
        }

        pendingSubtitleClips = []
    }

    private func subtitleClips(from result: TranscriptionResult, alignedTo clip: Clip) -> [Clip] {
        result.segments.compactMap { segment in
            let sourceRange = TimeRange(
                start: segment.startTime,
                duration: max(0, segment.endTime - segment.startTime)
            )
            guard let mapping = timelineMapping(for: sourceRange, in: clip) else {
                return nil
            }

            return Clip(
                kind: .text,
                sourceRange: mapping.sourceRange,
                timelineRange: mapping.timelineRange,
                textContent: TextClipContent(
                    text: segment.text,
                    fontFamily: "SFPro-Medium",
                    fontSize: 18,
                    fontColor: "#FFFFFF"
                )
            )
        }
    }

    private func timelineMapping(
        for sourceRange: TimeRange,
        in clip: Clip
    ) -> (sourceRange: TimeRange, timelineRange: TimeRange)? {
        guard
            sourceRange.start.isFinite,
            sourceRange.duration.isFinite,
            sourceRange.duration > 0
        else {
            return nil
        }

        let sourceStart = max(sourceRange.start, clip.sourceRange.start)
        let sourceEnd = min(sourceRange.end, clip.sourceRange.end)
        guard sourceEnd > sourceStart else { return nil }

        // Route through the canonical ClipTimeMapping (Step 7). Previously an
        // inline `/ playbackRate` formula duplicated from the macOS path.
        guard let mapping = clip.makeTimeMapping() else { return nil }
        let timelineStart = mapping.timelineTime(forSourceTime: sourceStart)
        let timelineEnd = min(clip.timelineRange.end, mapping.timelineTime(forSourceTime: sourceEnd))
        guard timelineEnd > timelineStart else { return nil }

        return (
            sourceRange: TimeRange(start: sourceStart, duration: sourceEnd - sourceStart),
            timelineRange: TimeRange(start: timelineStart, duration: timelineEnd - timelineStart)
        )
    }

    private func timeRangeText(for segment: TranscriptionSegment) -> String {
        "\(timeText(segment.startTime)) - \(timeText(segment.endTime))"
    }

    private func timeText(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
#endif
