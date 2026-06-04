#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSAutoAssistantView: View {
    @Bindable var viewModel: IOSEditorViewModel

    @State private var isAnalyzing = false
    @State private var isApplying = false
    @State private var analysisResult: AnalysisResult?
    @State private var analyzedClipId: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Analysis") {
                    if isAnalyzing {
                        HStack {
                            ProgressView()
                            Text("Analyzing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let result = analysisResult {
                        LabeledContent("Provider", value: result.providerName)
                        LabeledContent("Suggestions", value: "\(result.suggestions.count)")
                    } else {
                        ContentUnavailableView(
                            "No Analysis",
                            systemImage: "sparkles",
                            description: Text("Select an audio or video clip, then run analysis.")
                        )
                    }

                    Button {
                        Task { await runAnalysis() }
                    } label: {
                        Label("Analyze", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAnalyzing || isApplying || selectedTranscribableClipAndAsset == nil)

                    if analysisResult != nil {
                        Button("Clear", systemImage: "xmark.circle") {
                            analysisResult = nil
                            analyzedClipId = nil
                        }
                    }
                }

                if let result = analysisResult {
                    Section("Suggestions") {
                        if result.suggestions.isEmpty {
                            Text("No suggestions found.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(result.suggestions.enumerated()), id: \.offset) { index, suggestion in
                                suggestionRow(suggestion, index: index)
                            }

                            Button {
                                Task { await applyAll(result.suggestions) }
                            } label: {
                                Label("Apply All", systemImage: "checkmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isAnalyzing || isApplying)
                        }
                    }
                }
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: AnalysisSuggestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: iconForSuggestion(suggestion))
                    .foregroundStyle(colorForSuggestion(suggestion))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleForSuggestion(suggestion))
                        .font(.subheadline.bold())

                    Text(descriptionForSuggestion(suggestion))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button {
                Task { await applySuggestion(suggestion) }
            } label: {
                Label("Apply", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isAnalyzing || isApplying)
        }
        .padding(.vertical, 4)
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

    @MainActor
    private func runAnalysis() async {
        guard let selected = selectedTranscribableClipAndAsset else {
            viewModel.lastErrorMessage = "Select an audio or video clip to analyze."
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let result = try await analyze(asset: selected.asset, in: viewModel.currentProject)
            analysisResult = align(result, to: selected.clip)
            analyzedClipId = selected.clip.id
            viewModel.lastErrorMessage = nil
        } catch {
            viewModel.lastErrorMessage = error.localizedDescription
        }
    }

    private func analyze(asset: MediaAsset, in project: Project) async throws -> AnalysisResult {
        let silenceResult = try await SilenceDetectionProvider().analyze(asset: asset, in: project)
        var suggestions = silenceResult.suggestions
        var providerNames = [silenceResult.providerName]

        if asset.kind == .video {
            let sceneResult = try await SceneChangeProvider().analyze(asset: asset, in: project)
            suggestions.append(contentsOf: sceneResult.suggestions)
            providerNames.append(sceneResult.providerName)
        }

        return AnalysisResult(
            suggestions: suggestions,
            sourceAssetID: asset.id.uuidString,
            providerName: providerNames.joined(separator: " + ")
        )
    }

    private func align(_ result: AnalysisResult, to clip: Clip) -> AnalysisResult {
        AnalysisResult(
            suggestions: timelineSuggestions(from: result.suggestions, alignedTo: clip),
            sourceAssetID: result.sourceAssetID,
            providerName: result.providerName
        )
    }

    @MainActor
    private func applySuggestion(_ suggestion: AnalysisSuggestion) async {
        guard analyzedClipId != nil else { return }

        isApplying = true
        defer { isApplying = false }

        switch suggestion {
        case .silenceRemoval(let ranges):
            await removeRanges(ranges)
        case .sceneChanges(let times):
            await splitClips(at: times)
        case .autoCut(let editedRanges):
            await removeRanges(editedRanges)
        }
    }

    @MainActor
    private func applyAll(_ suggestions: [AnalysisSuggestion]) async {
        for suggestion in suggestions {
            await applySuggestion(suggestion)
        }
    }

    @MainActor
    private func removeRanges(_ ranges: [TimeRange]) async {
        for range in normalizedRanges(ranges) where range.duration > 0 {
            await splitClips(at: [range.start, range.end])

            let clipIds = clipIds(containedIn: range)
            for clipId in clipIds {
                viewModel.selectedClipId = clipId
                await viewModel.deleteClip()
            }
        }
    }

    @MainActor
    private func splitClips(at times: [TimeInterval]) async {
        for time in normalizedTimes(times) {
            let clipIds = clipIds(crossing: time)
            for clipId in clipIds {
                viewModel.selectedClipId = clipId
                viewModel.playheadTime = time
                await viewModel.splitClip()
            }
        }
    }

    private func clipIds(crossing time: TimeInterval) -> [UUID] {
        viewModel.currentProject.timeline.tracks.flatMap { track in
            track.clips.compactMap { clip in
                guard
                    clip.timelineRange.contains(time),
                    time > clip.timelineRange.start,
                    time < clip.timelineRange.end
                else {
                    return nil
                }

                return clip.id
            }
        }
    }

    private func clipIds(containedIn range: TimeRange) -> [UUID] {
        viewModel.currentProject.timeline.tracks.flatMap { track in
            track.clips.compactMap { clip in
                guard
                    clip.timelineRange.duration > 0,
                    clip.timelineRange.start >= range.start,
                    clip.timelineRange.end <= range.end
                else {
                    return nil
                }

                return clip.id
            }
        }
    }

    private func timelineSuggestions(
        from suggestions: [AnalysisSuggestion],
        alignedTo clip: Clip
    ) -> [AnalysisSuggestion] {
        suggestions.compactMap { suggestion in
            switch suggestion {
            case .silenceRemoval(let ranges):
                let mappedRanges = ranges.compactMap { timelineMapping(for: $0, in: clip)?.timelineRange }
                return mappedRanges.isEmpty ? nil : .silenceRemoval(ranges: mappedRanges)
            case .sceneChanges(let times):
                let mappedTimes = times.compactMap { time -> TimeInterval? in
                    let pointRange = TimeRange(start: time, duration: .ulpOfOne)
                    return timelineMapping(for: pointRange, in: clip)?.timelineRange.start
                }
                return mappedTimes.isEmpty ? nil : .sceneChanges(times: mappedTimes)
            case .autoCut(let editedRanges):
                let mappedRanges = editedRanges.compactMap { timelineMapping(for: $0, in: clip)?.timelineRange }
                return mappedRanges.isEmpty ? nil : .autoCut(editedRanges: mappedRanges)
            }
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

        let playbackRate = max(clip.playbackRate, 0.25)
        let timelineStart = clip.timelineRange.start + (sourceStart - clip.sourceRange.start) / playbackRate
        let timelineEnd = min(
            clip.timelineRange.end,
            timelineStart + (sourceEnd - sourceStart) / playbackRate
        )
        guard timelineEnd > timelineStart else { return nil }

        return (
            sourceRange: TimeRange(start: sourceStart, duration: sourceEnd - sourceStart),
            timelineRange: TimeRange(start: timelineStart, duration: timelineEnd - timelineStart)
        )
    }

    private func normalizedTimes(_ times: [TimeInterval]) -> [TimeInterval] {
        Array(Set(times.filter { $0.isFinite })).sorted()
    }

    private func normalizedRanges(_ ranges: [TimeRange]) -> [TimeRange] {
        let sortedRanges = ranges
            .filter { $0.start.isFinite && $0.duration.isFinite && $0.duration > 0 }
            .sorted { $0.start < $1.start }

        var normalized: [TimeRange] = []
        for range in sortedRanges {
            guard var lastRange = normalized.popLast() else {
                normalized.append(range)
                continue
            }

            if range.start <= lastRange.end {
                let end = max(lastRange.end, range.end)
                lastRange.duration = end - lastRange.start
                normalized.append(lastRange)
            } else {
                normalized.append(lastRange)
                normalized.append(range)
            }
        }

        return normalized
    }

    private func iconForSuggestion(_ suggestion: AnalysisSuggestion) -> String {
        switch suggestion {
        case .silenceRemoval:
            "speaker.slash"
        case .sceneChanges:
            "film"
        case .autoCut:
            "scissors"
        }
    }

    private func colorForSuggestion(_ suggestion: AnalysisSuggestion) -> Color {
        switch suggestion {
        case .silenceRemoval:
            .orange
        case .sceneChanges:
            .blue
        case .autoCut:
            .purple
        }
    }

    private func titleForSuggestion(_ suggestion: AnalysisSuggestion) -> String {
        switch suggestion {
        case .silenceRemoval:
            "Silence Removal"
        case .sceneChanges:
            "Scene Changes"
        case .autoCut:
            "Auto Cut"
        }
    }

    private func descriptionForSuggestion(_ suggestion: AnalysisSuggestion) -> String {
        switch suggestion {
        case .silenceRemoval(let ranges):
            "\(ranges.count) silent segment(s) detected"
        case .sceneChanges(let times):
            "\(times.count) scene change(s) at \(times.prefix(3).map { String(format: "%.1fs", $0) }.joined(separator: ", "))\(times.count > 3 ? "..." : "")"
        case .autoCut(let ranges):
            "\(ranges.count) segment(s) suggested for removal"
        }
    }
}
#endif
