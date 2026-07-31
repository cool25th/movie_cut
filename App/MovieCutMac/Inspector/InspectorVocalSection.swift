import SwiftUI
import MovieCutCore

// MARK: - Vocal separation inspector section (requirement 9.1)

// Inspector surface for offline vocal separation. The user picks a mode
// (remove center-panned vocals / isolate the center), sets a strength, and
// applies. Application runs the offline renderer and swaps the clip's source to
// the processed file through `ImportAndSetClipSourceCommand` — a single undo
// unit. See `EditorViewModel+VocalSeparation.swift`.
//
// This is a standalone section view following the `InspectorAnalysisSection`
// pattern (`@Bindable var viewModel`, `let clip`). It is surfaced in the
// inspector by the host panel; like the other App files added in this task it
// is registered at the orchestrator's next xcodegen run.

struct InspectorVocalSection: View {
    @Bindable var viewModel: EditorViewModel
    let clip: Clip

    /// Local mirror of the chosen mode, independent of selection churn.
    @State private var mode: VocalSeparationMode = .removeVocals

    /// Effect strength in `[0, 1]`. `1` is full cancellation/isolation.
    @State private var strength: Double = 1

    /// True while the offline render is running, to disable the button.
    @State private var isApplying = false

    init(viewModel: EditorViewModel, clip: Clip) {
        self.viewModel = viewModel
        self.clip = clip
    }

    var body: some View {
        Section {
            modePicker
            strengthSlider
            applyButton
        } header: {
            Label("Vocal Separation", systemImage: "music.mic")
                .font(MovieCutTypography.panelTitle)
                .foregroundStyle(.primary)
        } footer: {
            Text(footer)
                .font(MovieCutTypography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Subviews

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            Text("Remove Vocals").tag(VocalSeparationMode.removeVocals)
            Text("Isolate Center").tag(VocalSeparationMode.isolateCenter)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Vocal separation mode")
        .accessibilityHint("Remove Vocals cancels center-panned content (karaoke). Isolate Center keeps it (approximate vocal).")
    }

    private var strengthSlider: some View {
        HStack {
            Text("Strength")
                .font(.subheadline)
            Slider(value: $strength, in: 0 ... 1, step: 0.05) {
                Text("Strength")
            } minimumValueLabel: {
                Image(systemName: "0.circle")
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "1.circle")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Vocal separation strength")
            .accessibilityValue("\(Int(strength * 100)) percent")
            Text("\(Int(strength * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var applyButton: some View {
        Button {
            guard !isApplying else { return }
            isApplying = true
            let modeValue = mode
            let strengthValue = Float(strength)
            Task { @MainActor in
                defer { isApplying = false }
                await viewModel.applyVocalSeparationToSelection(
                    mode: modeValue,
                    strength: strengthValue
                )
            }
        } label: {
            if isApplying {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Applying…")
                }
            } else {
                Text(mode == .removeVocals ? "Remove Vocals" : "Isolate Vocals")
            }
        }
        .controlSize(.small)
        .disabled(isApplying || !viewModel.canApplyVocalSeparationToSelection)
        .accessibilityHint("Renders vocal separation and swaps this clip's source in one undoable step.")
    }

    // MARK: - Helpers

    /// Footer explains applicability + the stereo requirement so a mono / video
    /// selection surfaces a reason rather than silently failing.
    private var footer: String {
        if clip.kind != .audio {
            return "Applies to audio clips. Extract audio from a video clip first."
        }
        if !viewModel.canApplyVocalSeparationToSelection {
            return "Select an audio clip whose source is a stereo audio file."
        }
        return "Requires a stereo source. Mono input is reported as an error."
    }
}
