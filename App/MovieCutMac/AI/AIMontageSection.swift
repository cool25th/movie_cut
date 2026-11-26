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
                        .accessibilityLabel(NSLocalizedString("Selected photos summary", comment: "AI montage selected photos summary a11y"))
                }

                HStack(spacing: MovieCutSpacing.small) {
                    Picker(NSLocalizedString("Length", comment: "AI montage target duration picker"), selection: $targetDuration) {
                        ForEach(durationOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    .controlSize(.small)

                    Picker(NSLocalizedString("Canvas", comment: "AI montage target canvas picker"), selection: $targetRatio) {
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
                            Text(NSLocalizedString("Creating…", comment: "AI montage creating progress"))
                        }
                    } else {
                        Text(NSLocalizedString("Create Montage", comment: "AI montage create button"))
                    }
                }
                .controlSize(.small)
                .disabled(photoURLs.isEmpty || isCreating)
                .accessibilityHint(NSLocalizedString("Creates a photo montage video on the timeline", comment: "AI montage create hint"))

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
            Label(NSLocalizedString("AI Photo Montage", comment: "AI photo montage section title"), systemImage: "photo.on.rectangle.angled")
                .font(.subheadline.weight(.semibold))
        }
    }

    // MARK: - Labels

    private var photoPickerLabel: String {
        photoURLs.isEmpty
            ? NSLocalizedString("Choose Photos…", comment: "AI montage choose photos button")
            : String(format: NSLocalizedString("Photos (%d)", comment: "AI montage selected photos count"), photoURLs.count)
    }

    private var musicPickerLabel: String {
        if let musicURL {
            return String(format: NSLocalizedString("Music: %@", comment: "AI montage selected music label"), musicURL.lastPathComponent)
        }
        return NSLocalizedString("Choose Music…", comment: "AI montage choose music button")
    }

    private var photoSummary: String {
        let names = photoURLs.map(\.lastPathComponent)
        let shown = names.prefix(3).joined(separator: ", ")
        let remainder = names.count - min(3, names.count)
        return remainder > 0
            ? String(format: NSLocalizedString("%@ and %d more", comment: "AI montage photo summary overflow"), shown, remainder)
            : shown
    }

    // MARK: - Pickers

    private func pickPhotos() {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString("Choose Photos", comment: "AI montage open panel title")
        panel.message = NSLocalizedString("Photos are arranged into a montage with Ken Burns motion.", comment: "AI montage open panel message")
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
        panel.title = NSLocalizedString("Choose Music", comment: "AI montage music open panel title")
        panel.message = NSLocalizedString("One audio file. Short tracks loop to fill the montage.", comment: "AI montage music open panel message")
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
                    errorMessage = NSLocalizedString(
                        "The timeline already has clips. Montages are created in a new project — clear the timeline or open a new one first.",
                        comment: "AI montage non-empty timeline error"
                    )
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
            return NSLocalizedString(
                "This montage was already created. Click Create again to make a new one.",
                comment: "AI montage duplicate plan error"
            )
        }
        return error.localizedDescription
    }
}
