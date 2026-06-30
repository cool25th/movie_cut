import SwiftUI
import MovieCutCore

struct InspectorAnalysisSection: View {
    @Bindable var viewModel: EditorViewModel
    let clip: Clip

    @State private var showStickerPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            aiAssistantSection
            textTemplatesSection
            stickersSection

            if clip.kind == .video {
                automationSection
            }

            if clip.kind.supportsSubtitles {
                subtitlesSection
            }
        }
    }

    private var aiAssistantSection: some View {
        Section("AI Assistant") {
            Button("Auto Enhance") {
                Task { await viewModel.autoEnhance() }
            }
            Button("Suggest Cuts") {
                Task { try? await viewModel.suggestCuts() }
            }
            Button("Auto Color Correct") {
                Task { await viewModel.autoColorCorrect() }
            }
        }
    }

    private var textTemplatesSection: some View {
        Section("Text Templates") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(MovieCutCore.TextTemplate.builtIn) { template in
                        Button(template.name) {
                            Task { await viewModel.addTextTemplateClip(template) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var stickersSection: some View {
        Section("Stickers") {
            Button("Add Sticker") {
                showStickerPicker = true
            }
            .popover(isPresented: $showStickerPicker) {
                StickerPickerView { sticker in
                    Task { await viewModel.addSticker(sticker) }
                    showStickerPicker = false
                }
                .frame(width: 300, height: 400)
            }
        }
    }

    private var automationSection: some View {
        Section("Automation") {
            HStack {
                Button("Detect Scenes") {
                    runDetectScenes(for: clip.id)
                }
                .controlSize(.small)

                Button("Auto Reframe") {
                    runAutoReframe(for: clip.id)
                }
                .controlSize(.small)
            }
        }
    }

    private var subtitlesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subtitles")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack {
                Button {
                    runAutoSubtitles(for: clip.id)
                } label: {
                    Label("Auto Subtitles", systemImage: "captions.bubble")
                }
                .controlSize(.small)

                Button {
                    runAutoCutSilence(for: clip.id)
                } label: {
                    Label("Auto Cut Silence", systemImage: "speaker.slash")
                }
                .controlSize(.small)
            }
            AutoSubtitlesView(viewModel: viewModel)
        }
    }

    private func runAutoSubtitles(for clipId: UUID) {
        Task {
            do {
                try await viewModel.prepareSubtitles(for: clipId)
            } catch {
                viewModel.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func runAutoCutSilence(for clipId: UUID) {
        Task {
            do {
                try await viewModel.autoCutSilence(for: clipId)
            } catch {
                viewModel.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func runDetectScenes(for clipId: UUID) {
        Task {
            do {
                try await viewModel.detectAndSplitScenes(for: clipId)
            } catch {
                viewModel.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func runAutoReframe(for clipId: UUID) {
        Task {
            do {
                try await viewModel.autoReframe(for: clipId, targetAspect: 9.0 / 16.0)
            } catch {
                viewModel.lastErrorMessage = error.localizedDescription
            }
        }
    }
}
