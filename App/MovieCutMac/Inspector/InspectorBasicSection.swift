import SwiftUI
import MovieCutCore

enum InspectorBasicMode {
    case full
    case visual
    case speed
    case audio
    case text
}

struct InspectorBasicSection: View {
    @Bindable var viewModel: EditorViewModel
    let clip: Clip
    let mode: InspectorBasicMode

    private let speedPresets: [Double] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]
    private let minimumSpeedCurvePointCount = 2

    private struct SpeedCurvePreset: Identifiable {
        var id: String
        var name: String
        var systemImage: String
        var points: [SpeedRampPoint]
    }

    private let speedCurvePresets: [SpeedCurvePreset] = [
        SpeedCurvePreset(
            id: "easeIn",
            name: "Ease In",
            systemImage: "speedometer",
            points: [
                SpeedRampPoint(time: 0.00, rate: 0.50),
                SpeedRampPoint(time: 0.35, rate: 0.80),
                SpeedRampPoint(time: 0.70, rate: 1.35),
                SpeedRampPoint(time: 1.00, rate: 2.00)
            ]
        ),
        SpeedCurvePreset(
            id: "easeOut",
            name: "Ease Out",
            systemImage: "gauge.with.dots.needle.100percent",
            points: [
                SpeedRampPoint(time: 0.00, rate: 2.00),
                SpeedRampPoint(time: 0.30, rate: 1.35),
                SpeedRampPoint(time: 0.65, rate: 0.80),
                SpeedRampPoint(time: 1.00, rate: 0.50)
            ]
        ),
        SpeedCurvePreset(
            id: "montageFlash",
            name: "Flash",
            systemImage: "bolt.fill",
            points: [
                SpeedRampPoint(time: 0.00, rate: 1.00),
                SpeedRampPoint(time: 0.18, rate: 3.00),
                SpeedRampPoint(time: 0.38, rate: 0.55),
                SpeedRampPoint(time: 0.62, rate: 3.25),
                SpeedRampPoint(time: 0.82, rate: 0.75),
                SpeedRampPoint(time: 1.00, rate: 1.25)
            ]
        )
    ]

    init(viewModel: EditorViewModel, clip: Clip, mode: InspectorBasicMode = .full) {
        self.viewModel = viewModel
        self.clip = clip
        self.mode = mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            switch mode {
            case .full:
                fullSections
            case .visual:
                visualSections
            case .speed:
                speedSections
            case .audio:
                audioSections
            case .text:
                textSections
            }
        }
    }

    @ViewBuilder
    private var fullSections: some View {
        clipInfoSection
        transformSection
        if isStickerClip {
            stickerTransformSection
        }
        opacitySection

        if clip.kind.supportsVolume {
            volumeSection
            fadeDurationSection
            equalizerSection
        }

        if clip.kind == .audio || clip.kind == .video {
            autoCutSection
        }

        if clip.kind == .video {
            autoReframeSection
            motionTrackingSection
        }

        if clip.kind.supportsSpeed {
            speedSection
        }

        if let textContent = clip.textContent {
            textContentSection(textContent)
        }
    }

    @ViewBuilder
    private var visualSections: some View {
        clipInfoSection
        transformSection
        if isStickerClip {
            stickerTransformSection
        }
        opacitySection

        if clip.kind == .video {
            autoReframeSection
            motionTrackingSection
        }
    }

    @ViewBuilder
    private var speedSections: some View {
        clipInfoSection

        if clip.kind.supportsSpeed {
            speedSection
        } else {
            speedUnavailableSection
        }
    }

    @ViewBuilder
    private var audioSections: some View {
        clipInfoSection

        if clip.kind.supportsVolume {
            volumeSection
            fadeDurationSection
            equalizerSection
        }

        if clip.kind == .audio || clip.kind == .video {
            autoCutSection
        }

        if clip.kind.supportsSpeed {
            speedSection
        }
    }

    @ViewBuilder
    private var textSections: some View {
        if let textContent = clip.textContent {
            textContentSection(textContent)
        }

        clipInfoSection
        transformSection
        if isStickerClip {
            stickerTransformSection
        }
        opacitySection
    }

    /// Subject-tracking auto reframe with preview/apply/cancel (F-19).
    private var autoReframeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Auto Reframe")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Tracks the subject and reframes to the current canvas with smoothed keyframes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.hasReframePreview {
                Text("\(viewModel.reframePreviewFrames.count) crop frames previewed on the canvas")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            HStack(spacing: 6) {
                Button("Preview") {
                    Task { await viewModel.previewAutoReframeOnSelection() }
                }
                .controlSize(.small)
                .accessibilityHint("Shows the smoothed crop path on the preview without changing the clip.")

                if viewModel.hasReframePreview {
                    Button("Apply") {
                        Task { await viewModel.applyAutoReframePreview() }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Commits the previewed reframe keyframes to the clip.")

                    Button("Cancel") {
                        viewModel.cancelAutoReframePreview()
                    }
                    .controlSize(.small)
                    .accessibilityHint("Discards the auto reframe preview.")
                }
            }
        }
    }

    private var motionTrackingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("모션 트래킹")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if viewModel.isMotionTrackingRunning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Motion tracking in progress")
                }
            }

            if viewModel.selectedClipMotionTrackingKeyframeCount > 0 {
                Text("\(viewModel.selectedClipMotionTrackingKeyframeCount) keyframes")
                    .font(.caption)
                    .foregroundStyle(.cyan)
            }

            HStack(spacing: 6) {
                Button("영역 조정") {
                    viewModel.beginMotionTrackingSelection()
                }
                .controlSize(.small)
                .disabled(!viewModel.canTrackMotionSelection || viewModel.isMotionTrackingRunning)
                .accessibilityHint("Shows an editable tracking box on the preview.")

                Button("Track") {
                    Task { await viewModel.trackMotionInSelectedClip() }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canTrackMotionSelection || viewModel.isMotionTrackingRunning)
                .accessibilityHint("Tracks the preview box and writes position keyframes to the clip.")

                if viewModel.isMotionTrackingSelectionActive {
                    Button("Cancel") {
                        viewModel.cancelMotionTrackingSelection()
                    }
                    .controlSize(.small)
                    .disabled(viewModel.isMotionTrackingRunning)
                    .accessibilityHint("Hides the editable tracking box.")
                }

                if viewModel.selectedClipMotionTrackingKeyframeCount > 0 {
                    Button("Clear") {
                        Task { await viewModel.clearMotionTrackingOnSelectedClip() }
                    }
                    .controlSize(.small)
                    .disabled(viewModel.isMotionTrackingRunning)
                    .accessibilityHint("Removes motion tracking position keyframes from the selected clip.")
                }
            }
        }
    }

    /// Silence-based auto cut with parameters and preview/apply/cancel (F-18).
    private var autoCutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Auto Cut (Silence)")
                .font(.subheadline)
                .fontWeight(.semibold)

            autoCutSlider(
                title: "Threshold",
                value: Binding(
                    get: { Double(viewModel.autoCutThresholdDB) },
                    set: { viewModel.autoCutThresholdDB = Float($0) }
                ),
                range: -60 ... -10,
                step: 1,
                format: "%.0f dB",
                accessibility: "Silence threshold decibels"
            )
            autoCutSlider(
                title: "Min Silence",
                value: $viewModel.autoCutMinSilence,
                range: 0.1 ... 3.0,
                step: 0.1,
                format: "%.1fs",
                accessibility: "Minimum silence duration seconds"
            )
            autoCutSlider(
                title: "Padding",
                value: $viewModel.autoCutPadding,
                range: 0 ... 1.0,
                step: 0.05,
                format: "%.2fs",
                accessibility: "Speech padding seconds"
            )

            if viewModel.hasAutoCutPreview {
                Text(String(
                    format: "%d range(s), %.1fs removable",
                    viewModel.autoCutPreviewRanges.count,
                    viewModel.autoCutPreviewTotalDuration
                ))
                .font(.caption)
                .foregroundStyle(.red)
            }

            HStack(spacing: 6) {
                Button("Preview") {
                    Task { await viewModel.previewAutoCutOnSelection() }
                }
                .controlSize(.small)
                .accessibilityHint("Highlights silent ranges that would be removed without changing the timeline.")

                if viewModel.hasAutoCutPreview {
                    Button("Apply") {
                        Task { await viewModel.applyAutoCutPreview() }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Removes the previewed silent ranges as a single undoable edit.")

                    Button("Cancel") {
                        viewModel.cancelAutoCutPreview()
                    }
                    .controlSize(.small)
                    .accessibilityHint("Discards the auto cut preview.")
                }
            }
        }
    }

    private func autoCutSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String,
        accessibility: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(accessibility)
            Text(String(format: format, value.wrappedValue))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private var clipInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Clip Info")
                .font(.subheadline)
                .fontWeight(.semibold)
            LabeledContent("Type", value: clipTypeLabel)
            LabeledContent("Duration", value: String(format: "%.2fs", clip.timelineRange.duration))
        }
    }

    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transform")
                .font(.subheadline)
                .fontWeight(.semibold)
            LabeledContent("X", value: String(format: "%.1f", clip.transform.position.x))
            LabeledContent("Y", value: String(format: "%.1f", clip.transform.position.y))
            LabeledContent("Scale", value: String(format: "%.2f", clip.transform.scale.width))
            LabeledContent("Rotation", value: String(format: "%.1f\u{00B0}", clip.transform.rotation))
        }
    }

    private var stickerTransformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sticker Transform")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Quick")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            transformSlider(
                title: "X",
                value: Double(clip.transform.position.x),
                range: 0 ... Double(max(canvasSize.width, 1))
            ) { newValue in
                var transform = clip.transform
                transform.position.x = CGFloat(newValue)
                Task { await viewModel.updateSelectedStickerTransform(transform) }
            }

            transformSlider(
                title: "Y",
                value: Double(clip.transform.position.y),
                range: 0 ... Double(max(canvasSize.height, 1))
            ) { newValue in
                var transform = clip.transform
                transform.position.y = CGFloat(newValue)
                Task { await viewModel.updateSelectedStickerTransform(transform) }
            }

            transformSlider(
                title: "Scale",
                value: Double((clip.transform.scale.width + clip.transform.scale.height) * 0.5),
                range: 0.25 ... 2.5
            ) { newValue in
                var transform = clip.transform
                let scale = CGFloat(newValue)
                transform.scale = CGSize(width: scale, height: scale)
                Task { await viewModel.updateSelectedStickerTransform(transform) }
            }

            transformSlider(
                title: "Rotate",
                value: clip.transform.rotation,
                range: -180 ... 180
            ) { newValue in
                var transform = clip.transform
                transform.rotation = newValue
                Task { await viewModel.updateSelectedStickerTransform(transform) }
            }

            HStack(spacing: 6) {
                Button {
                    Task { await viewModel.centerSelectedSticker() }
                } label: {
                    Label("Center", systemImage: "dot.scope")
                }
                .controlSize(.small)

                Button {
                    Task { await viewModel.fitSelectedStickerToSocialSafeArea() }
                } label: {
                    Label("Safe", systemImage: "viewfinder")
                }
                .controlSize(.small)

                Button {
                    Task { await viewModel.resetSelectedStickerTransform() }
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
            }
        }
    }

    private var opacitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Opacity")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack {
                Slider(value: Binding(
                    get: { clip.opacity },
                    set: { newValue in
                        Task { await viewModel.updateSelectedOpacity(newValue) }
                    }
                ), in: 0 ... 1)
                Text(String(format: "%.0f%%", clip.opacity * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
            }
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Volume")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack {
                Slider(value: Binding(
                    get: { clip.volume },
                    set: { newValue in
                        Task { await viewModel.updateSelectedVolume(newValue) }
                    }
                ), in: 0 ... 2)
                Text(String(format: "%.0f%%", clip.volume * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
            }

            HStack {
                Button("Noise Reduction") {
                    if let clipId = viewModel.selectedClipId {
                        Task { try? await viewModel.applyNoiseReduction(for: clipId) }
                    }
                }
                .controlSize(.small)

                if clip.kind == .video {
                    Button {
                        Task { await viewModel.extractAudioFromSelectedClip() }
                    } label: {
                        Label("Extract Audio from Video", systemImage: "waveform")
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.canExtractAudioFromSelection)
                    .accessibilityLabel("Extract Audio from Video")
                    .accessibilityHint("Creates an audio-only timeline clip from the selected video's embedded audio.")
                }
            }
        }
    }

    private var fadeDurationSection: some View {
        AudioFadeDurationEditor(viewModel: viewModel, clip: clip)
    }

    private var equalizerSection: some View {
        Section("Equalizer") {
            Picker("Preset", selection: $viewModel.selectedEQPreset) {
                ForEach(EqualizerPresetOption.allCases) { opt in
                    Text(opt.displayName).tag(opt.rawValue)
                }
            }
            .onChange(of: viewModel.selectedEQPreset) { _, newValue in
                Task { await viewModel.applyEQPreset(newValue) }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(equalizerBands.enumerated()), id: \.element.frequency) { _, band in
                    HStack(spacing: 6) {
                        Text(equalizerFrequencyLabel(band.frequency))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .leading)
                        Slider(value: Binding(
                            get: { Double(band.gain) },
                            set: { newValue in
                                Task {
                                    await viewModel.updateSelectedEQBandGain(
                                        frequency: band.frequency,
                                        gain: Float(newValue)
                                    )
                                }
                            }
                        ), in: -12 ... 12, step: 0.5)
                        .accessibilityLabel("Equalizer \(equalizerFrequencyLabel(band.frequency)) gain")
                        .accessibilityValue(String(format: "%.1f dB", band.gain))
                        Text(String(format: "%+.1f dB", band.gain))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var equalizerBands: [EQBand] {
        ClipEqualizerSettings.normalizedBands(clip.equalizer?.bands ?? EqualizerPreset.flat.bands)
    }

    private func equalizerFrequencyLabel(_ frequency: Float) -> String {
        switch Int(frequency.rounded()) {
        case 60:
            return "60Hz"
        case 250:
            return "250Hz"
        case 1_000:
            return "1kHz"
        case 4_000:
            return "4kHz"
        case 12_000:
            return "12kHz"
        default:
            return "\(Int(frequency.rounded()))Hz"
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Speed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.0f%%", clip.playbackRate * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Slider(value: Binding(
                get: { clip.playbackRate },
                set: { newValue in
                    Task { await viewModel.updateSelectedPlaybackRate(newValue) }
                }
            ), in: 0.25 ... 4.0)
            .accessibilityLabel("Constant speed")
            .accessibilityValue(String(format: "%.0f%%", clip.playbackRate * 100))
            .accessibilityHint("Adjusts the selected clip constant playback speed.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
                ForEach(speedPresets, id: \.self) { preset in
                    Button(speedPresetLabel(preset)) {
                        Task { await viewModel.updateSelectedPlaybackRate(preset) }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Constant speed \(speedPresetLabel(preset))")
                    .accessibilityHint("Applies this constant speed to the selected clip.")
                }
            }

            if clip.kind == .video {
                Toggle("부드러운 슬로우모션", isOn: Binding(
                    get: { clip.useOpticalFlow },
                    set: { newValue in
                        Task { await viewModel.updateSelectedOpticalFlow(newValue) }
                    }
                ))
                .disabled(clip.playbackRate >= 1.0)
                .accessibilityHint("Exports opted-in slow motion with frame interpolation.")

                Text("내보낼 때 프레임 보간이 적용됩니다")
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
            }

            Divider()

            speedCurveEditor
        }
    }

    private var speedCurveEditor: some View {
        let points = normalizedSpeedRampPoints(clip.speedRampPoints)

        return VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            HStack {
                Text("Speed Curve")
                    .font(MovieCutTypography.cardTitle)
                Spacer()
                Text(speedCurveStatusText(points))
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Speed Curve")
            .accessibilityValue(speedCurveStatusText(points))
            .accessibilityHint("Edits the selected clip normalized speed ramp curve.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: MovieCutSpacing.xSmall)], spacing: MovieCutSpacing.xSmall) {
                ForEach(speedCurvePresets) { preset in
                    Button {
                        applySpeedCurvePreset(preset)
                    } label: {
                        Label(preset.name, systemImage: preset.systemImage)
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Apply \(preset.name) Speed Curve")
                    .accessibilityHint("Replaces the selected clip speed curve with the \(preset.name) preset.")
                }
            }

            HStack(spacing: MovieCutSpacing.xSmall) {
                Button {
                    addSpeedCurvePoint()
                } label: {
                    Label("Add Point", systemImage: "plus")
                }
                .controlSize(.small)
                .accessibilityLabel("Add Speed Curve Point")
                .accessibilityHint("Adds a normalized point using a safe time and rate.")

                Button {
                    resetSpeedCurve()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .disabled(points.isEmpty)
                .accessibilityLabel("Reset Speed Curve")
                .accessibilityHint("Clears the curve so the selected clip uses constant speed.")
            }

            if points.isEmpty {
                Text("Constant playback rate is active.")
                    .font(MovieCutTypography.panelSubtitle)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Speed Curve Constant")
                    .accessibilityValue(String(format: "%.0f%%", clip.playbackRate * 100))
            } else {
                VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        speedCurvePointRow(
                            point,
                            index: index,
                            canDelete: points.count > minimumSpeedCurvePointCount
                        )
                    }
                }
            }
        }
    }

    private func speedCurvePointRow(
        _ point: SpeedRampPoint,
        index: Int,
        canDelete: Bool
    ) -> some View {
        let pointNumber = index + 1

        return VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            HStack(spacing: MovieCutSpacing.small) {
                Text("Point \(pointNumber)")
                    .font(MovieCutTypography.metadata.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(speedCurvePointSummary(point))
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button(role: .destructive) {
                    deleteSpeedCurvePoint(point.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(!canDelete)
                .accessibilityLabel("Speed curve point delete")
                .accessibilityValue("Point \(pointNumber)")
                .accessibilityHint(canDelete ? "Deletes this speed curve point." : "Keep at least two curve points, or reset the curve.")
            }

            HStack(spacing: MovieCutSpacing.small) {
                Text("Time")
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { point.time },
                        set: { newValue in
                            updateSpeedCurvePoint(point.id, time: newValue, rate: point.rate)
                        }
                    ),
                    in: 0 ... 1,
                    step: 0.01
                )
                .accessibilityLabel("Speed curve point time")
                .accessibilityValue(speedCurveTimeLabel(point.time))
                .accessibilityHint("Sets this point position from the beginning to the end of the clip.")
                Text(speedCurveTimeLabel(point.time))
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }

            HStack(spacing: MovieCutSpacing.small) {
                Text("Rate")
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { point.rate },
                        set: { newValue in
                            updateSpeedCurvePoint(point.id, time: point.time, rate: newValue)
                        }
                    ),
                    in: 0.25 ... 4.0,
                    step: 0.05
                )
                .accessibilityLabel("Speed curve point rate")
                .accessibilityValue(speedCurveRateLabel(point.rate))
                .accessibilityHint("Sets the playback speed at this point.")
                Text(speedCurveRateLabel(point.rate))
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .padding(MovieCutSpacing.xSmall)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .fill(MovieCutTheme.inspectorSelectedControlSurface.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(MovieCutTheme.inspectorSelectedBorder.opacity(0.18), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Speed curve point \(pointNumber)")
        .accessibilityValue(speedCurvePointSummary(point))
    }

    private func normalizedSpeedRampPoints(_ points: [SpeedRampPoint]) -> [SpeedRampPoint] {
        points
            .map { point in
                SpeedRampPoint(id: point.id, time: point.time, rate: point.rate)
            }
            .sorted { lhs, rhs in
                if lhs.time == rhs.time {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.time < rhs.time
            }
    }

    private func applySpeedCurvePreset(_ preset: SpeedCurvePreset) {
        let points = normalizedSpeedRampPoints(preset.points)
        Task { await viewModel.updateSelectedSpeedRampPoints(points) }
    }

    private func addSpeedCurvePoint() {
        var points = normalizedSpeedRampPoints(clip.speedRampPoints)
        let newPoint = SpeedRampPoint(
            time: defaultSpeedCurvePointTime(in: points),
            rate: clampedSpeedCurveRate(clip.playbackRate)
        )
        points.append(newPoint)

        Task { await viewModel.updateSelectedSpeedRampPoints(normalizedSpeedRampPoints(points)) }
    }

    private func updateSpeedCurvePoint(_ id: SpeedRampPoint.ID, time: Double, rate: Double) {
        let points = normalizedSpeedRampPoints(clip.speedRampPoints).map { point in
            if point.id == id {
                return SpeedRampPoint(id: point.id, time: time, rate: rate)
            }

            return point
        }

        Task { await viewModel.updateSelectedSpeedRampPoints(normalizedSpeedRampPoints(points)) }
    }

    private func deleteSpeedCurvePoint(_ id: SpeedRampPoint.ID) {
        let points = normalizedSpeedRampPoints(clip.speedRampPoints)
        guard points.count > minimumSpeedCurvePointCount else { return }

        Task {
            await viewModel.updateSelectedSpeedRampPoints(
                normalizedSpeedRampPoints(points.filter { $0.id != id })
            )
        }
    }

    private func resetSpeedCurve() {
        Task { await viewModel.updateSelectedSpeedRampPoints([]) }
    }

    private func defaultSpeedCurvePointTime(in points: [SpeedRampPoint]) -> Double {
        guard !points.isEmpty else { return 0.50 }

        let sortedTimes = points.map(\.time).sorted()
        var bestStart = 0.0
        var bestEnd = sortedTimes[0]

        for (left, right) in zip(sortedTimes, sortedTimes.dropFirst()) {
            if right - left > bestEnd - bestStart {
                bestStart = left
                bestEnd = right
            }
        }

        if 1.0 - (sortedTimes.last ?? 1.0) > bestEnd - bestStart {
            bestStart = sortedTimes.last ?? 0.0
            bestEnd = 1.0
        }

        return clampedSpeedCurveTime((bestStart + bestEnd) * 0.5)
    }

    private func clampedSpeedCurveTime(_ time: Double) -> Double {
        min(max(time, 0), 1)
    }

    private func clampedSpeedCurveRate(_ rate: Double) -> Double {
        min(max(rate, 0.25), 4.0)
    }

    private func speedCurveStatusText(_ points: [SpeedRampPoint]) -> String {
        if points.isEmpty {
            return "Constant"
        }

        return "\(points.count) points"
    }

    private func speedCurveTimeLabel(_ time: Double) -> String {
        String(format: "%.0f%%", clampedSpeedCurveTime(time) * 100)
    }

    private func speedCurveRateLabel(_ rate: Double) -> String {
        String(format: "%.2gx", clampedSpeedCurveRate(rate))
    }

    private func speedCurvePointSummary(_ point: SpeedRampPoint) -> String {
        "\(speedCurveTimeLabel(point.time)) · \(speedCurveRateLabel(point.rate))"
    }

    private var speedUnavailableSection: some View {
        Text("This clip type does not support speed controls.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private let fontFamilies = [
        "System", "Helvetica Neue", "Helvetica Neue Bold",
        "SF Pro", "SF Pro Rounded", "Georgia", "Menlo",
        "Avenir Next", "Futura", "Courier New"
    ]

    private struct TextStylePreset: Identifiable {
        var id: String
        var name: String
        var systemImage: String
        var fontFamily: String
        var fontSize: Double
        var alignment: MovieCutCore.TextAlignment
        var fontColor: String
        var backgroundColor: String?
    }

    private let textStylePresets = [
        TextStylePreset(
            id: "title",
            name: "Title",
            systemImage: "textformat.size.larger",
            fontFamily: "Helvetica Neue Bold",
            fontSize: 64,
            alignment: .center,
            fontColor: "#FFFFFF",
            backgroundColor: nil
        ),
        TextStylePreset(
            id: "caption",
            name: "Caption",
            systemImage: "captions.bubble",
            fontFamily: "System",
            fontSize: 28,
            alignment: .center,
            fontColor: "#FFFFFF",
            backgroundColor: "#000000"
        ),
        TextStylePreset(
            id: "lower_third",
            name: "Lower Third",
            systemImage: "rectangle.bottomthird.inset.filled",
            fontFamily: "Avenir Next",
            fontSize: 34,
            alignment: .leading,
            fontColor: "#FFFFFF",
            backgroundColor: "#000000"
        ),
        TextStylePreset(
            id: "background_safe",
            name: "BG Safe",
            systemImage: "rectangle.inset.filled",
            fontFamily: "System",
            fontSize: 36,
            alignment: .center,
            fontColor: "#FFFFFF",
            backgroundColor: "#111111"
        )
    ]

    private func textContentSection(_ textContent: TextClipContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isStickerClip ? "Sticker" : "Style")
                .font(.subheadline)
                .fontWeight(.semibold)

            textBodyEditor(textContent)

            if isStickerClip {
                stickerMetadataSection(textContent)
            } else {
                textTemplateBrowser()
                normalTextStyleEditor(textContent)
            }
        }
    }

    private func textTemplateBrowser() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Templates")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(MovieCutCore.TextTemplate.builtIn.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [
                        GridItem(.fixed(78), spacing: 8),
                        GridItem(.fixed(78), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(MovieCutCore.TextTemplate.builtIn) { template in
                        Button {
                            Task { await viewModel.addTextTemplateClip(template) }
                        } label: {
                            InspectorTextTemplateThumbnail(template: template)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(template.name) text template")
                        .accessibilityHint("Creates a new text clip at the playhead with this template style.")
                        .help(template.name)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 166)
        }
    }

    private func normalTextStyleEditor(_ textContent: TextClipContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                fontPicker(textContent)
                fontSizeControl(textContent)
            }

            HStack(spacing: 8) {
                alignmentPicker(textContent)
                foregroundColorPicker(textContent)
            }

            textBackgroundControls(textContent)
            textDecorationControls(textContent)
            textQuickStylePresets(textContent)
            textAnimationControls(textContent)
            userStylePresetControls(textContent)
            textToSpeechControls(textContent)
        }
    }

    /// CapCut-style text animation presets with shared preview/export math.
    private func textAnimationControls(_ textContent: TextClipContent) -> some View {
        let selectedPreset = textContent.animation?.preset ?? .none
        let selectedDuration = textContent.animation?.duration ?? selectedPreset.duration

        return VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                Text("Animation")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(textAnimationName(selectedPreset))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 6)], spacing: 6) {
                ForEach(TextAnimationPreset.allCases, id: \.self) { preset in
                    Button {
                        applyTextAnimationPreset(preset, to: textContent)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: textAnimationSystemImage(preset))
                                .font(.system(size: 16, weight: .semibold))
                            Text(textAnimationName(preset))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(preset == selectedPreset ? Color.accentColor.opacity(0.22) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(preset == selectedPreset ? Color.accentColor.opacity(0.72) : Color.secondary.opacity(0.22), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Text animation \(textAnimationName(preset))")
                    .accessibilityHint("Applies this animation preset to the selected text clip.")
                    .help(textAnimationName(preset))
                }
            }

            HStack(spacing: 6) {
                Text("Duration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Slider(value: Binding(
                    get: { min(max(selectedDuration, 0.3), 2.0) },
                    set: { newValue in
                        updateTextAnimationDuration(newValue, for: textContent)
                    }
                ), in: 0.3 ... 2.0, step: 0.05)
                .disabled(selectedPreset == .none)
                .accessibilityLabel("Text animation duration")
                .accessibilityValue(String(format: "%.2f seconds", selectedDuration))

                Text(String(format: "%.2fs", selectedDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func applyTextAnimationPreset(_ preset: TextAnimationPreset, to textContent: TextClipContent) {
        var updated = textContent
        if preset == .none {
            updated.animation = nil
        } else {
            let duration = min(max(updated.animation?.duration ?? preset.duration, 0.3), 2.0)
            updated.animation = TextAnimation(preset: preset, duration: duration)
        }
        Task { await viewModel.updateSelectedTextContent(updated) }
    }

    private func updateTextAnimationDuration(_ duration: Double, for textContent: TextClipContent) {
        guard let animation = textContent.animation, animation.preset != .none else { return }

        var updated = textContent
        updated.animation = TextAnimation(
            preset: animation.preset,
            duration: min(max(duration, 0.3), 2.0),
            delay: animation.delay
        )
        Task { await viewModel.updateSelectedTextContent(updated) }
    }

    private func textAnimationName(_ preset: TextAnimationPreset) -> String {
        switch preset {
        case .none: return "None"
        case .fadeIn: return "Fade In"
        case .fadeOut: return "Fade Out"
        case .fadeInOut: return "Fade In/Out"
        case .slideInLeft: return "Left"
        case .slideInRight: return "Right"
        case .slideInUp: return "Up"
        case .slideInDown: return "Down"
        case .typewriter: return "Type"
        case .bounceIn: return "Bounce"
        case .zoomIn: return "Zoom"
        case .popIn: return "Pop"
        case .wave: return "Wave"
        }
    }

    private func textAnimationSystemImage(_ preset: TextAnimationPreset) -> String {
        switch preset {
        case .none: return "slash.circle"
        case .fadeIn: return "circle.lefthalf.filled"
        case .fadeOut: return "circle.righthalf.filled"
        case .fadeInOut: return "circle.dashed"
        case .slideInLeft: return "arrow.right"
        case .slideInRight: return "arrow.left"
        case .slideInUp: return "arrow.up"
        case .slideInDown: return "arrow.down"
        case .typewriter: return "text.cursor"
        case .bounceIn: return "arrow.up.and.down"
        case .zoomIn: return "plus.magnifyingglass"
        case .popIn: return "sparkles"
        case .wave: return "water.waves"
        }
    }

    /// Generates a spoken audio clip from the text using a system voice (F-17).
    private func textToSpeechControls(_ textContent: TextClipContent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            Text("Text to Speech")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Picker("Voice", selection: Binding(
                    get: { viewModel.selectedTTSVoiceId ?? "" },
                    set: { viewModel.selectedTTSVoiceId = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(viewModel.ttsVoices) { voice in
                        Text(voice.displayName).tag(voice.id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 180)
                .accessibilityLabel("Speech voice")

                Button("Generate Voice") {
                    Task { await viewModel.generateSpeechFromSelectedText() }
                }
                .controlSize(.small)
                .disabled(!viewModel.canGenerateSpeechFromSelection)
                .accessibilityLabel("Generate voice from text")
                .accessibilityHint("Creates a spoken audio clip aligned to this text clip.")
            }
        }
        .onAppear { viewModel.loadTTSVoices() }
    }

    /// Bold/italic, outline, and drop-shadow editing (F-12R).
    private func textDecorationControls(_ textContent: TextClipContent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { textContent.isBold },
                    set: { newValue in
                        var updated = textContent
                        updated.isBold = newValue
                        Task { await viewModel.updateSelectedTextContent(updated) }
                    }
                )) {
                    Image(systemName: "bold")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Bold text")

                Toggle(isOn: Binding(
                    get: { textContent.isItalic },
                    set: { newValue in
                        var updated = textContent
                        updated.isItalic = newValue
                        Task { await viewModel.updateSelectedTextContent(updated) }
                    }
                )) {
                    Image(systemName: "italic")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Italic text")

                Spacer()
            }

            HStack(spacing: 6) {
                Text("Outline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ColorPicker("", selection: Binding(
                    get: { colorFromHex(textContent.strokeColor ?? "#000000") },
                    set: { newValue in
                        var updated = textContent
                        updated.strokeColor = hexFromColor(newValue)
                        if updated.strokeWidth == nil || updated.strokeWidth == 0 {
                            updated.strokeWidth = 2
                        }
                        Task { await viewModel.updateSelectedTextContent(updated) }
                    }
                ))
                .labelsHidden()
                .accessibilityLabel("Outline color")

                Slider(value: Binding(
                    get: { textContent.strokeWidth ?? 0 },
                    set: { newValue in
                        var updated = textContent
                        if newValue <= 0.01 {
                            updated.strokeWidth = nil
                            updated.strokeColor = nil
                        } else {
                            updated.strokeWidth = newValue
                            if updated.strokeColor == nil {
                                updated.strokeColor = "#000000"
                            }
                        }
                        Task { await viewModel.updateSelectedTextContent(updated) }
                    }
                ), in: 0 ... 8)
                .accessibilityLabel("Outline width")

                Text(String(format: "%.1f", textContent.strokeWidth ?? 0))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Toggle("Shadow", isOn: Binding(
                    get: { textContent.shadowColor != nil },
                    set: { enabled in
                        var updated = textContent
                        if enabled {
                            updated.shadowColor = updated.shadowColor ?? "#000000"
                            updated.shadowBlur = updated.shadowBlur ?? 4
                            updated.shadowOffset = updated.shadowOffset ?? CGPoint(x: 2, y: 2)
                        } else {
                            updated.shadowColor = nil
                            updated.shadowBlur = nil
                            updated.shadowOffset = nil
                        }
                        Task { await viewModel.updateSelectedTextContent(updated) }
                    }
                ))
                .font(.caption)
                .accessibilityLabel("Text shadow")

                if textContent.shadowColor != nil {
                    Slider(value: Binding(
                        get: { textContent.shadowBlur ?? 4 },
                        set: { newValue in
                            var updated = textContent
                            updated.shadowBlur = newValue
                            Task { await viewModel.updateSelectedTextContent(updated) }
                        }
                    ), in: 0 ... 20)
                    .accessibilityLabel("Shadow blur")

                    Text(String(format: "%.0f", textContent.shadowBlur ?? 4))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 22, alignment: .trailing)
                }
            }
        }
    }

    /// Saved user presets: capture the current style or apply/delete one.
    private func userStylePresetControls(_ textContent: TextClipContent) -> some View {
        HStack(spacing: 6) {
            Menu("My Styles") {
                if viewModel.userTextStylePresets.isEmpty {
                    Text("No saved styles")
                }
                ForEach(viewModel.userTextStylePresets) { preset in
                    Button(preset.name) {
                        Task { await viewModel.applyUserTextStylePreset(preset) }
                    }
                }
                if !viewModel.userTextStylePresets.isEmpty {
                    Divider()
                    Menu("Delete") {
                        ForEach(viewModel.userTextStylePresets) { preset in
                            Button(preset.name, role: .destructive) {
                                viewModel.deleteUserTextStylePreset(preset.id)
                            }
                        }
                    }
                }
            }
            .controlSize(.small)
            .frame(maxWidth: 120)
            .accessibilityLabel("Saved text styles")
            .onAppear {
                viewModel.loadUserTextStylePresets()
            }

            Button("Save Style") {
                viewModel.saveSelectedTextStyleAsPreset()
            }
            .controlSize(.small)
            .accessibilityLabel("Save current text style as preset")
            .accessibilityHint("Captures font, colors, outline, and shadow for reuse.")
        }
    }

    private func textBodyEditor(_ textContent: TextClipContent) -> some View {
        TextField(isStickerClip ? "Sticker" : "Text", text: Binding(
            get: { textContent.text },
            set: { newValue in
                var updated = textContent
                updated.text = newValue
                if isStickerClip {
                    updated.contentKind = .sticker
                }
                Task { await viewModel.updateSelectedTextContent(updated) }
            }
        ))
        .movieCutInputField()
    }

    private func fontPicker(_ textContent: TextClipContent) -> some View {
        Picker("Font", selection: Binding(
            get: { textContent.fontFamily },
            set: { newValue in
                var updated = textContent
                updated.fontFamily = newValue
                Task { await viewModel.updateSelectedTextContent(updated) }
            }
        )) {
            ForEach(fontFamilies, id: \.self) { family in
                Text(family).tag(family)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 170)
    }

    private func fontSizeControl(_ textContent: TextClipContent) -> some View {
        HStack(spacing: 4) {
            Text("Size")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { textContent.fontSize },
                set: { newValue in
                    var updated = textContent
                    updated.fontSize = newValue
                    Task { await viewModel.updateSelectedTextContent(updated) }
                }
            ), in: 8 ... 144, step: 1)
            Text(String(format: "%.0f", textContent.fontSize))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func alignmentPicker(_ textContent: TextClipContent) -> some View {
        Picker("Alignment", selection: Binding(
            get: { textContent.alignment },
            set: { newValue in
                var updated = textContent
                updated.alignment = newValue
                Task { await viewModel.updateSelectedTextContent(updated) }
            }
        )) {
            Label("Left", systemImage: "text.alignleft").tag(MovieCutCore.TextAlignment.leading)
            Label("Center", systemImage: "text.aligncenter").tag(MovieCutCore.TextAlignment.center)
            Label("Right", systemImage: "text.alignright").tag(MovieCutCore.TextAlignment.trailing)
            Label("Justify", systemImage: "text.justify").tag(MovieCutCore.TextAlignment.justified)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
    }

    private func foregroundColorPicker(_ textContent: TextClipContent) -> some View {
        ColorPicker("Foreground", selection: Binding(
            get: {
                colorFromHex(textContent.fontColor)
            },
            set: { newValue in
                var updated = textContent
                updated.fontColor = hexFromColor(newValue)
                Task { await viewModel.updateSelectedTextContent(updated) }
            }
        ))
        .labelsHidden()
    }

    private func textBackgroundControls(_ textContent: TextClipContent) -> some View {
        HStack(spacing: 8) {
            Toggle("Background", isOn: Binding(
                get: { textContent.backgroundColor != nil },
                set: { isEnabled in
                    setTextBackgroundEnabled(isEnabled, for: textContent)
                }
            ))
            .toggleStyle(.checkbox)

            ColorPicker("Background", selection: Binding(
                get: {
                    colorFromHex(textContent.backgroundColor ?? "#000000")
                },
                set: { newValue in
                    var updated = textContent
                    updated.backgroundColor = hexFromColor(newValue)
                    Task { await viewModel.updateSelectedTextContent(updated) }
                }
            ))
            .labelsHidden()
            .disabled(textContent.backgroundColor == nil)

            Button("None") {
                setTextBackgroundEnabled(false, for: textContent)
            }
            .controlSize(.small)
        }
    }

    private func textQuickStylePresets(_ textContent: TextClipContent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Presets")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(textStylePresets) { preset in
                    Button {
                        applyTextStylePreset(preset, to: textContent)
                    } label: {
                        Label(preset.name, systemImage: preset.systemImage)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func applyTextStylePreset(_ preset: TextStylePreset, to textContent: TextClipContent) {
        var updated = textContent
        updated.fontFamily = preset.fontFamily
        updated.fontSize = preset.fontSize
        updated.alignment = preset.alignment
        updated.fontColor = preset.fontColor
        updated.backgroundColor = preset.backgroundColor
        updated.contentKind = .text
        Task { await viewModel.updateSelectedTextContent(updated) }
    }

    private func setTextBackgroundEnabled(_ isEnabled: Bool, for textContent: TextClipContent) {
        var updated = textContent
        if isEnabled {
            updated.backgroundColor = normalizedHexRGB(textContent.backgroundColor) ?? "#000000"
        } else {
            updated.backgroundColor = nil
        }
        Task { await viewModel.updateSelectedTextContent(updated) }
    }

    private func stickerMetadataSection(_ textContent: TextClipContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Kind", value: textContent.stickerImageURL == nil ? "Emoji sticker" : "Image/badge sticker")
                .font(.caption)

            if let stickerAssetID = textContent.stickerAssetID {
                LabeledContent("Asset", value: stickerAssetID.uuidString.prefix(8).description)
                    .font(.caption)
            }

            if let stickerImageURL = textContent.stickerImageURL {
                LabeledContent("Image", value: stickerImageURL.lastPathComponent)
                    .font(.caption)
            }
        }
    }

    private var clipTypeLabel: String {
        if isStickerClip {
            if clip.textContent?.stickerImageURL != nil {
                return "Image Sticker"
            }

            return "Sticker"
        }

        return clip.kind.rawValue.capitalized
    }

    private var isStickerClip: Bool {
        guard clip.kind == .text, let textContent = clip.textContent else {
            return false
        }

        return textContent.isSticker || textContent.fontFamily == "Apple Color Emoji"
    }

    private var canvasSize: CGSize {
        let timelineSize = viewModel.currentProject.timeline.canvasSize
        if timelineSize.width > 0, timelineSize.height > 0 {
            return timelineSize
        }

        return viewModel.currentProject.canvas.size
    }

    private func transformSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range
            )
            Text(sliderValueLabel(title: title, value: value))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func sliderValueLabel(title: String, value: Double) -> String {
        if title == "Scale" {
            return String(format: "%.2f", value)
        }

        if title == "Rotate" {
            return String(format: "%.0f\u{00B0}", value)
        }

        return String(format: "%.0f", value)
    }

    private func colorFromHex(_ hex: String) -> Color {
        guard let normalized = normalizedHexRGB(hex) else {
            return .white
        }
        let clean = String(normalized.dropFirst())
        guard let value = UInt64(clean, radix: 16) else { return .white }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func normalizedHexRGB(_ hex: String?) -> String? {
        guard let hex else { return nil }
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count >= 6 else { return nil }

        let rgb = String(clean.prefix(6)).uppercased()
        guard UInt64(rgb, radix: 16) != nil else { return nil }
        return "#\(rgb)"
    }

    private func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func speedPresetLabel(_ rate: Double) -> String {
        if rate.rounded() == rate {
            return String(format: "%.0fx", rate)
        }
        return String(format: "%.2gx", rate)
    }
}

private struct InspectorTextTemplateThumbnail: View {
    let template: MovieCutCore.TextTemplate

    private var content: TextClipContent {
        template.content
    }

    private var previewText: String {
        content.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewFontSize: CGFloat {
        min(max(CGFloat(content.fontSize) * 0.26, 11), 24)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .fill(MovieCutTheme.previewWellBackground)

                GeometryReader { proxy in
                    styledPreviewText
                        .frame(maxWidth: min(proxy.size.width - 12, 116), alignment: alignmentFrame)
                        .position(previewPosition(in: proxy.size))
                }
                .padding(2)
            }
            .frame(height: 56)
            .overlay(
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .stroke(MovieCutTheme.border.opacity(0.44), lineWidth: 0.5)
            )

            Text(template.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 128, height: 78)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .fill(MovieCutTheme.inspectorSelectedControlSurface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .stroke(MovieCutTheme.inspectorSelectedBorder.opacity(0.52), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var styledPreviewText: some View {
        let text = Text(previewText.isEmpty ? template.name : previewText)
            .font(.custom(content.fontFamily, size: previewFontSize))
            .fontWeight(content.isBold ? .bold : .regular)
            .foregroundStyle(Self.color(from: content.fontColor))

        if content.isItalic {
            decoratedText(text.italic())
        } else {
            decoratedText(text)
        }
    }

    private func decoratedText<Label: View>(_ label: Label) -> some View {
        let strokeColor = content.strokeColor.map { Self.color(from: $0) } ?? .clear
        let strokeWidth = min(max(CGFloat(content.strokeWidth ?? 0) * 0.25, 0), 2)
        let shadowColor = content.shadowColor.map { Self.color(from: $0).opacity(0.9) } ?? .clear
        let shadowOffset = content.shadowOffset ?? CGPoint(x: 0, y: 0)
        let shadowRadius = min(max(CGFloat(content.shadowBlur ?? 0) * 0.18, 0), 4)

        return label
            .lineLimit(2)
            .minimumScaleFactor(0.55)
            .multilineTextAlignment(multilineAlignment)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                if let backgroundColor = content.backgroundColor {
                    RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                        .fill(Self.color(from: backgroundColor))
                }
            }
            .shadow(color: strokeColor, radius: 0, x: strokeWidth, y: 0)
            .shadow(color: strokeColor, radius: 0, x: -strokeWidth, y: 0)
            .shadow(color: strokeColor, radius: 0, x: 0, y: strokeWidth)
            .shadow(color: strokeColor, radius: 0, x: 0, y: -strokeWidth)
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: min(max(shadowOffset.x * 0.18, -3), 3),
                y: min(max(shadowOffset.y * 0.18, -3), 3)
            )
    }

    private var alignmentFrame: Alignment {
        switch content.alignment {
        case .leading:
            return .leading
        case .center, .justified:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private var multilineAlignment: SwiftUI.TextAlignment {
        switch content.alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        case .justified:
            return .leading
        }
    }

    private func previewPosition(in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else {
            return CGPoint(x: 0, y: 0)
        }

        let isDefaultPosition = abs(content.position.x) <= 1.0e-9 && abs(content.position.y) <= 1.0e-9
        let normalizedX = isDefaultPosition ? 0.5 : min(max(content.position.x / 1920, 0.18), 0.82)
        let normalizedY = isDefaultPosition ? 0.5 : min(max(content.position.y / 1080, 0.20), 0.80)

        return CGPoint(
            x: size.width * normalizedX,
            y: size.height * normalizedY
        )
    }

    private static func color(from hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count >= 6 else { return .white }

        let rgb = String(clean.prefix(6))
        guard let value = UInt64(rgb, radix: 16) else { return .white }

        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

private struct AudioFadeDurationEditor: View {
    let viewModel: EditorViewModel
    let clip: Clip

    private let fineStep: Double = 0.05
    private let softPresetDuration: Double = 0.5
    private let longPresetDuration: Double = 2.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fade Duration")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(formattedSeconds(clip.fadeInDuration)) in / \(formattedSeconds(clip.fadeOutDuration)) out")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            fadeDurationControl(
                title: "Fade In",
                value: clip.fadeInDuration,
                accessibilityLabel: "Fade In duration",
                accessibilityHint: "Adjusts how long the selected audio clip takes to fade in."
            ) { newValue in
                updateFadeInDuration(newValue)
            }

            fadeDurationControl(
                title: "Fade Out",
                value: clip.fadeOutDuration,
                accessibilityLabel: "Fade Out duration",
                accessibilityHint: "Adjusts how long the selected audio clip takes to fade out."
            ) { newValue in
                updateFadeOutDuration(newValue)
            }

            HStack(spacing: 6) {
                Button("Reset Fades") {
                    resetAudioFades()
                }
                .controlSize(.small)
                .accessibilityLabel("Reset audio fades")
                .accessibilityHint("Sets fade in and fade out duration to zero seconds.")

                Button("None") {
                    applyAudioFadePreset(0)
                }
                .controlSize(.small)
                .accessibilityLabel("No audio fade preset")
                .accessibilityHint("Sets fade in and fade out duration to zero seconds.")

                Button("Soft") {
                    applyAudioFadePreset(softPresetDuration)
                }
                .controlSize(.small)
                .accessibilityLabel("Soft audio fade preset")
                .accessibilityHint("Sets fade in and fade out to a short duration.")

                Button("Long") {
                    applyAudioFadePreset(longPresetDuration)
                }
                .controlSize(.small)
                .accessibilityLabel("Long audio fade preset")
                .accessibilityHint("Sets fade in and fade out to a longer duration.")
            }

            Divider()

            HStack {
                Text("Audio Ducking")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if !clip.duckingRanges.isEmpty, let level = clip.duckingLevel {
                    Text("\(clip.duckingRanges.count) range(s) at \(Int(level * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 6) {
                Button("Duck Other Audio") {
                    Task { await viewModel.autoDuckOtherAudio() }
                }
                .controlSize(.small)
                .help("Lowers overlapping music while this clip's voice is active.")
                .accessibilityLabel("Duck other audio under this clip")
                .accessibilityHint("Analyzes this clip's speech and lowers overlapping audio clips during voiced intervals.")

                if !clip.duckingRanges.isEmpty {
                    Button("Clear Ducking") {
                        Task { await viewModel.clearDuckingOnSelectedClip() }
                    }
                    .controlSize(.small)
                    .accessibilityLabel("Clear ducking on this clip")
                    .accessibilityHint("Removes the ducking volume ranges from this clip.")
                }
            }
        }
    }

    private func fadeDurationControl(
        title: String,
        value: Double,
        accessibilityLabel: String,
        accessibilityHint: String,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let clampedValue = clampedFadeDuration(value)
        let binding = Binding<Double>(
            get: { clampedValue },
            set: { newValue in
                onChange(clampedFadeDuration(newValue))
            }
        )

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedSeconds(clampedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }

            Slider(value: binding, in: fadeControlRange, step: fineStep)
                .disabled(fadeDurationMaximum == 0)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(formattedSeconds(clampedValue))
                .accessibilityHint(accessibilityHint)

            HStack(spacing: 6) {
                TextField("Seconds", value: binding, format: .number.precision(.fractionLength(2)))
                    .movieCutInputField()
                    .frame(width: 76)
                    .disabled(fadeDurationMaximum == 0)
                    .accessibilityLabel("\(accessibilityLabel) value")
                    .accessibilityValue(formattedSeconds(clampedValue))
                    .accessibilityHint("Enter a non-negative duration in seconds.")

                Stepper("Step \(title)", value: binding, in: fadeControlRange, step: fineStep)
                    .labelsHidden()
                    .disabled(fadeDurationMaximum == 0)
                    .accessibilityLabel("\(accessibilityLabel) fine adjustment")
                    .accessibilityValue(formattedSeconds(clampedValue))
                    .accessibilityHint("Adjusts the duration in 0.05 second increments.")

                Text("s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fadeDurationMaximum: Double {
        max(0, min(10, clip.timelineRange.duration))
    }

    private var fadeControlRange: ClosedRange<Double> {
        0 ... max(fadeDurationMaximum, fineStep)
    }

    private func clampedFadeDuration(_ value: Double) -> Double {
        min(max(value, 0), fadeDurationMaximum)
    }

    private func updateFadeInDuration(_ newValue: Double) {
        Task { await viewModel.updateSelectedAudioFade(fadeInDuration: clampedFadeDuration(newValue)) }
    }

    private func updateFadeOutDuration(_ newValue: Double) {
        Task { await viewModel.updateSelectedAudioFade(fadeOutDuration: clampedFadeDuration(newValue)) }
    }

    private func resetAudioFades() {
        let zero = clampedFadeDuration(0)
        Task { await viewModel.updateSelectedAudioFade(fadeInDuration: zero, fadeOutDuration: zero) }
    }

    private func applyAudioFadePreset(_ duration: Double) {
        let clampedDuration = clampedFadeDuration(duration)
        Task {
            await viewModel.updateSelectedAudioFade(
                fadeInDuration: clampedDuration,
                fadeOutDuration: clampedDuration
            )
        }
    }

    private func formattedSeconds(_ value: Double) -> String {
        String(format: "%.2fs", clampedFadeDuration(value))
    }
}
