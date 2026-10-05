import MovieCutCore
import SwiftUI
import UniformTypeIdentifiers

/// AI photo-montage creation — the user entry point for
/// `EditorViewModel.applyPhotoMontage` (AI-03/AI-04): pick photos and
/// optional music through the system open panel (the powerbox — files
/// chosen here carry real user-granted, security-scoped bookmarks), choose
/// length and canvas, and create the montage through the same atomic-batch
/// path the E2E suite exercises.
struct AIMontageSection: View {
    var viewModel: EditorViewModel

    @State private var isExpanded = false
    @State private var photoURLs: [URL] = []
    @State private var musicURL: URL?
    @State private var targetDuration: TimeInterval = 15
    @State private var targetRatio: AspectRatio = .portrait9x16
    @State private var isCreating = false
    @State private var errorMessage: String?

    private let durationOptions: [(label: String, seconds: TimeInterval)] = [
        ("10s", 10), ("15s", 15), ("30s", 30), ("60s", 60),
    ]
    private let ratioOptions: [(label: String, ratio: AspectRatio)] = [
        ("9:16", .portrait9x16),
        ("16:9", .landscape16x9),
        ("1:1", .square1x1),
        ("4:5", .portrait4x5),
    ]

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                HStack(spacing: MovieCutSpacing.small) {
                    Button {
                        pickPhotos()
                    } label: {
                        Label(photoPickerLabel, systemImage: "photo.on.rectangle")
                    }
                    .controlSize(.small)

                    Button {
                        pickMusic()
                    } label: {
                        Label(musicPickerLabel, systemImage: "music.note")
                    }
                    .controlSize(.small)
                }

                if !photoURLs.isEmpty {
                    Text(photoSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityLabel("Selected photos summary")
                }

                HStack(spacing: MovieCutSpacing.small) {
                    Picker("Length", selection: $targetDuration) {
                        ForEach(durationOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    .controlSize(.small)

                    Picker("Canvas", selection: $targetRatio) {
                        ForEach(ratioOptions, id: \.ratio) { option in
                            Text(option.label).tag(option.ratio)
                        }
                    }
                    .controlSize(.small)
                }

                Button {
                    create()
                } label: {
                    if isCreating {
                        HStack(spacing: MovieCutSpacing.xSmall) {
                            ProgressView().controlSize(.small)
                            Text("Creating…")
                        }
                    } else {
                        Text("Create Montage")
                    }
                }
                .controlSize(.small)
                .disabled(photoURLs.isEmpty || isCreating)
                .accessibilityHint("Creates a photo montage video on the timeline")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if viewModel.assistantResultMessage != nil && errorMessage == nil && !isCreating {
                    // applyPhotoMontage posts its success message here.
                    Text(viewModel.assistantResultMessage ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, MovieCutSpacing.small)
        } label: {
            Label("AI Photo Montage", systemImage: "photo.on.rectangle.angled")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Labels

    private var photoPickerLabel: String {
        photoURLs.isEmpty ? "Choose Photos…" : "Photos (\(photoURLs.count))"
    }

    private var musicPickerLabel: String {
        if let musicURL {
            return "Music: \(musicURL.lastPathComponent)"
        }
        return "Choose Music…"
    }

    private var photoSummary: String {
        let names = photoURLs.map(\.lastPathComponent)
        let shown = names.prefix(3).joined(separator: ", ")
        let remainder = names.count - min(3, names.count)
        return remainder > 0 ? "\(shown) and \(remainder) more" : shown
    }

    // MARK: - Pickers

    private func pickPhotos() {
        let panel = NSOpenPanel()
        panel.title = "Choose Photos"
        panel.message = "Photos are arranged into a montage with Ken Burns motion."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        let picked = panel.urls
        guard !picked.isEmpty else { return }
        photoURLs = picked
        errorMessage = nil
    }

    private func pickMusic() {
        if musicURL != nil {
            // A second click clears the current track — optional music.
            musicURL = nil
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose Music"
        panel.message = "One audio file. Short tracks loop to fill the montage."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        musicURL = url
        errorMessage = nil
    }

    // MARK: - Creation

    private func create() {
        let photos = photoURLs
        let music = musicURL
        let duration = targetDuration
        let canvas = CanvasPreset(aspectRatio: targetRatio)
        guard !photos.isEmpty, !isCreating else { return }

        isCreating = true
        errorMessage = nil
        Task { @MainActor in
            defer { isCreating = false }
            do {
                _ = try await viewModel.applyPhotoMontage(
                    photoURLs: photos,
                    musicURL: music,
                    targetDuration: duration,
                    targetCanvas: canvas
                )
            } catch let error as EditingActionDSL.PlanningError {
                if case .timelineNotEmpty = error {
                    // Montage is a new-project creation — surface the policy
                    // instead of the raw enum.
                    errorMessage = "The timeline already has clips. Montages are created in a new project — clear the timeline or open a new one first."
                } else {
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = friendlyMessage(for: error)
            }
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if case EditorCommandError.duplicatePlanApplication = error {
            return "This montage was already created. Click Create again to make a new one."
        }
        return error.localizedDescription
    }
}
