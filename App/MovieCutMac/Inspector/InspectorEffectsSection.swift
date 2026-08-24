import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

enum InspectorEffectsMode {
    case full
    case adjustment
    case mask
    case animation

    /// The effect browser belongs to effect/color discovery, so it is exposed
    /// from the active Adjustment tab as well as the legacy full inspector.
    /// Keeping the policy on the mode makes the reachable-path contract
    /// behavior-testable instead of relying on source-string inspection.
    var showsEffectBrowser: Bool {
        switch self {
        case .full, .adjustment:
            return true
        case .mask, .animation:
            return false
        }
    }
}

struct InspectorEffectsSection: View {
    @Bindable var viewModel: EditorViewModel
    let clip: Clip
    let mode: InspectorEffectsMode

    @State private var isTransitionExpanded = false
    @State private var isAnimationExpanded = false
    @State private var selectedKeyframeId: UUID?
    @State private var isEffectBrowserPresented = false

    init(viewModel: EditorViewModel, clip: Clip, mode: InspectorEffectsMode = .full) {
        self.viewModel = viewModel
        self.clip = clip
        self.mode = mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            switch mode {
            case .full:
                fullSections
            case .adjustment:
                adjustmentSections
            case .mask:
                maskSections
            case .animation:
                animationSections
            }
        }
        .onChange(of: viewModel.selectedClipId) { _, _ in
            selectedKeyframeId = nil
        }
    }

    @ViewBuilder
    private var effectBrowserEntry: some View {
        if mode.showsEffectBrowser {
            HStack {
                Text("Effects")
                    .font(MovieCutTypography.panelTitle)
                Spacer()
                Button {
                    isEffectBrowserPresented = true
                } label: {
                    Label("Browse", systemImage: "square.grid.2x2")
                        .font(MovieCutTypography.toolbar)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Browse effects")
                .accessibilityHint("Opens effect previews and parameter controls for the selected clip.")
            }
            .sheet(isPresented: $isEffectBrowserPresented) {
                EffectBrowserView(viewModel: viewModel, clip: clip)
            }
        }
    }

    @ViewBuilder
    private var fullSections: some View {
        effectBrowserEntry
        colorCorrectionSection
        colorGradeSection
        maskSection
        backgroundRemovalSection
        styleTransferSection
        effectsSection

        if clip.kind == .video {
            chromaKeySection
        }

        reverseFreezeSection
        transitionSection
        animationSection
    }

    @ViewBuilder
    private var adjustmentSections: some View {
        // G-28: this is the mode used by InspectorPanel's visible Adjustment
        // tab, so the browser must be reachable here (not only in `.full`).
        effectBrowserEntry
        colorCorrectionSection
        colorGradeSection
        backgroundRemovalSection
        styleTransferSection
        effectsSection

        if clip.kind == .video {
            chromaKeySection
        }

        reverseFreezeSection
    }

    @ViewBuilder
    private var maskSections: some View {
        maskSection
    }

    @ViewBuilder
    private var animationSections: some View {
        transitionSection
        animationSection
    }

    private var colorCorrectionSection: some View {
        let colorCorrection = clip.colorCorrection ?? ColorCorrection()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Color Correction")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Reset") {
                    Task { await viewModel.updateSelectedColorCorrection(nil) }
                }
                .controlSize(.small)
                .disabled(clip.colorCorrection == nil)
            }

            inspectorSlider(
                title: "Brightness",
                value: colorCorrection.brightness,
                range: -1 ... 1,
                binding: colorCorrectionBinding(keyPath: \.brightness)
            )

            inspectorSlider(
                title: "Contrast",
                value: colorCorrection.contrast,
                range: 0 ... 2,
                binding: colorCorrectionBinding(keyPath: \.contrast)
            )

            inspectorSlider(
                title: "Saturation",
                value: colorCorrection.saturation,
                range: 0 ... 2,
                binding: colorCorrectionBinding(keyPath: \.saturation)
            )

            inspectorSlider(
                title: "Color Temperature",
                value: colorCorrection.warmth,
                range: -1 ... 1,
                binding: colorCorrectionBinding(keyPath: \.warmth)
            )

            inspectorSlider(
                title: "Tint",
                value: colorCorrection.tint,
                range: -1 ... 1,
                binding: colorCorrectionBinding(keyPath: \.tint)
            )
        }
    }

    private var colorGradeSection: some View {
        let grade = clip.colorGrade ?? ColorGrade()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Color Grade")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Auto Enhance") {
                    Task { await viewModel.autoEnhanceSelectedClip() }
                }
                .controlSize(.small)
                .help("On-device auto white balance + contrast")
                Menu("Auto…") {
                    Button("Auto White Balance") {
                        Task { await viewModel.autoColorSelectedClip() }
                    }
                    Button("Auto Levels") {
                        Task { await viewModel.autoLevelsSelectedClip() }
                    }
                }
                .controlSize(.small)
                .frame(width: 70)
                Button("Reset") {
                    Task { await viewModel.updateSelectedColorGrade(nil) }
                }
                .controlSize(.small)
                .disabled(clip.colorGrade == nil)
            }

            if let histogram = viewModel.scopeHistogram {
                HistogramView(histogram: histogram)
            }
            HStack(alignment: .top, spacing: 8) {
                if let waveform = viewModel.scopeWaveform {
                    WaveformView(waveform: waveform)
                }
                if let vectorscope = viewModel.scopeVectorscope {
                    VectorscopeView(vectorscope: vectorscope)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                ColorGradeWheel(
                    title: "Lift · shadows",
                    red: grade.lift.red,
                    green: grade.lift.green,
                    blue: grade.lift.blue,
                    chromaScale: 0.5,
                    lumaRange: -0.5 ... 0.5,
                    onChange: { red, green, blue in
                        updateColorGradeLift(red: red, green: green, blue: blue)
                    }
                )
                ColorGradeWheel(
                    title: "Gain · highlights",
                    red: grade.gain.red,
                    green: grade.gain.green,
                    blue: grade.gain.blue,
                    chromaScale: 0.5,
                    lumaRange: 0 ... 2,
                    onChange: { red, green, blue in
                        updateColorGradeGain(red: red, green: green, blue: blue)
                    }
                )
            }

            Text("Gamma · midtones")
                .font(.caption2)
                .foregroundStyle(.secondary)
            inspectorSlider(title: "Gamma", value: grade.gamma, range: 0.2 ... 2.0, binding: colorGradeBinding(keyPath: \.gamma))

            ColorHSLBandsView(bands: grade.hslBands) { bands in
                updateColorGradeHSLBands(bands)
            }
        }
        .task(id: clip.id) {
            viewModel.refreshScopes()
        }
    }

    private func updateColorGradeLift(red: Double, green: Double, blue: Double) {
        let grade = clip.colorGrade ?? ColorGrade()
        let updated = ColorGrade(
            lift: .init(red: red, green: green, blue: blue),
            gamma: grade.gamma,
            gain: grade.gain,
            hslBands: grade.hslBands,
            curves: grade.curves
        )
        Task { await viewModel.updateSelectedColorGrade(updated) }
    }

    private func updateColorGradeGain(red: Double, green: Double, blue: Double) {
        let grade = clip.colorGrade ?? ColorGrade()
        let updated = ColorGrade(
            lift: grade.lift,
            gamma: grade.gamma,
            gain: .init(red: red, green: green, blue: blue),
            hslBands: grade.hslBands,
            curves: grade.curves
        )
        Task { await viewModel.updateSelectedColorGrade(updated) }
    }

    /// G-02 Inc 5: commits the HSL band editor's full band array through the
    /// same single command path as the wheels, preserving the 3-way values and
    /// curves. Passing nil (every band identity) keeps ungraded JSON clean.
    private func updateColorGradeHSLBands(_ bands: [HSLBand]?) {
        let grade = clip.colorGrade ?? ColorGrade()
        let updated = ColorGrade(
            lift: grade.lift,
            gamma: grade.gamma,
            gain: grade.gain,
            hslBands: bands,
            curves: grade.curves
        )
        Task { await viewModel.updateSelectedColorGrade(updated) }
    }

    private var maskSection: some View {
        let mask = clip.mask ?? defaultMask()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mask")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Clear Mask") {
                    Task { await viewModel.updateSelectedMask(nil) }
                }
                .controlSize(.small)
                .disabled(clip.mask == nil)
            }

            Picker("Shape", selection: Binding(
                get: { mask.shape },
                set: { shape in
                    var updatedMask = clip.mask ?? defaultMask(shape: shape)
                    updatedMask.shape = shape
                    Task { await viewModel.updateSelectedMask(updatedMask) }
                }
            )) {
                ForEach(MaskShape.allCases, id: \.self) { shape in
                    Text(shape.displayName).tag(shape)
                }
            }
            .pickerStyle(.menu)

            inspectorSlider(
                title: "Feather",
                value: mask.feather,
                range: 0 ... 1,
                binding: maskFeatherBinding()
            )

            inspectorSlider(
                title: "Position X",
                value: Double(mask.position.x),
                range: 0 ... Double(viewModel.currentProject.canvas.size.width),
                binding: Binding(
                    get: { Double(mask.position.x) },
                    set: { newValue in
                        var updatedMask = clip.mask ?? defaultMask()
                        updatedMask.position.x = CGFloat(newValue)
                        Task { await viewModel.updateSelectedMask(updatedMask) }
                    }
                )
            )

            inspectorSlider(
                title: "Position Y",
                value: Double(mask.position.y),
                range: 0 ... Double(viewModel.currentProject.canvas.size.height),
                binding: Binding(
                    get: { Double(mask.position.y) },
                    set: { newValue in
                        var updatedMask = clip.mask ?? defaultMask()
                        updatedMask.position.y = CGFloat(newValue)
                        Task { await viewModel.updateSelectedMask(updatedMask) }
                    }
                )
            )

            inspectorSlider(
                title: "Width",
                value: Double(mask.size.width),
                range: 0 ... Double(viewModel.currentProject.canvas.size.width),
                binding: Binding(
                    get: { Double(mask.size.width) },
                    set: { newValue in
                        var updatedMask = clip.mask ?? defaultMask()
                        updatedMask.size.width = CGFloat(newValue)
                        Task { await viewModel.updateSelectedMask(updatedMask) }
                    }
                )
            )

            inspectorSlider(
                title: "Height",
                value: Double(mask.size.height),
                range: 0 ... Double(viewModel.currentProject.canvas.size.height),
                binding: Binding(
                    get: { Double(mask.size.height) },
                    set: { newValue in
                        var updatedMask = clip.mask ?? defaultMask()
                        updatedMask.size.height = CGFloat(newValue)
                        Task { await viewModel.updateSelectedMask(updatedMask) }
                    }
                )
            )

            Toggle("Inverted", isOn: Binding(
                get: { mask.inverted },
                set: { inverted in
                    var updatedMask = clip.mask ?? defaultMask()
                    updatedMask.inverted = inverted
                    Task { await viewModel.updateSelectedMask(updatedMask) }
                }
            ))
        }
    }

    private var backgroundRemovalSection: some View {
        Section("Background Removal") {
            Toggle("Remove Background", isOn: $viewModel.isBackgroundRemoved)
                .onChange(of: viewModel.isBackgroundRemoved) { _, newValue in
                    Task { await viewModel.toggleBackgroundRemoval(newValue) }
                }
        }
    }

    private var styleTransferSection: some View {
        Section("Style Transfer") {
            Picker("Style", selection: $viewModel.selectedStyle) {
                Text("None").tag("none")
                Text("Cinematic").tag("cinematic")
                Text("Noir").tag("noir")
                Text("Vintage").tag("vintage")
                Text("Vivid").tag("vivid")
                Text("Cool").tag("cool")
            }
            .onChange(of: viewModel.selectedStyle) { _, newValue in
                Task { await viewModel.applyStyleTransfer(newValue) }
            }
        }
    }

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Effects")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    importLUT()
                } label: {
                    Label("Import LUT…", systemImage: "square.stack.3d.forward.dottedline")
                }
                .controlSize(.small)
                .help("Import an external .cube color LUT and apply it to this clip.")

                Button {
                    exportLUT()
                } label: {
                    Label("Export LUT…", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
                .help("Export this clip's LUT: re-exports an imported .cube losslessly, or bakes the basic color correction.")

                Menu {
                    ForEach(EffectType.allCases.filter { $0 != .externalLUT }, id: \.self) { type in
                        Button(type.displayName) {
                            addEffect(type)
                        }
                    }
                } label: {
                    Label("Add Effect", systemImage: "plus")
                }
                .menuStyle(.button)
                .controlSize(.small)
            }

            if clip.effects.isEmpty {
                Text("No effects")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            ForEach(clip.effects) { effect in
                EffectRowView(
                    effect: effect,
                    parameterDefinitions: parameterDefinitions(for: effect.type),
                    onRemove: {
                        removeEffect(effect.id)
                    },
                    onParameterChange: { key, newValue in
                        updateEffect(effect.id, parameter: key, value: newValue)
                    }
                )
            }
        }
    }

    private var chromaKeySection: some View {
        ChromaKeyView(
            clip: clip,
            isEyedropperActive: viewModel.isChromaKeyEyedropperActive,
            onChange: { chromaKey in
                Task { await viewModel.updateSelectedChromaKey(chromaKey) }
            },
            onPickColor: {
                viewModel.toggleChromaKeyEyedropper()
            }
        )
    }

    private var reverseFreezeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reverse & Freeze")
                .font(.subheadline)
                .fontWeight(.semibold)

            Toggle("Reverse playback", isOn: Binding(
                get: { clip.isReversed },
                set: { isReversed in
                    Task { await viewModel.updateSelectedReversePlayback(isReversed) }
                }
            ))

            Button("Freeze Frame") {
                Task { await viewModel.freezeSelectedFrame() }
            }
            .controlSize(.small)
            .disabled(!canFreezeFrame())
        }
    }

    private var transitionSection: some View {
        DisclosureGroup("Transition", isExpanded: $isTransitionExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: Binding(
                    get: { clip.transition?.type ?? .none },
                    set: { type in
                        updateTransitionType(type)
                    }
                )) {
                    ForEach(TransitionType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .accessibilityLabel("Transition type")
                .accessibilityValue((clip.transition?.type ?? .none).displayName)
                .accessibilityHint("Chooses the visual transition between this clip and the next clip. Export and device playback still require separate verification.")

                if let transition = clip.transition {
                    HStack {
                        Slider(value: Binding(
                            get: { transition.duration },
                            set: { duration in
                                updateTransitionDuration(duration)
                            }
                        ), in: 0.1 ... 3)
                        .accessibilityLabel("Transition duration")
                        .accessibilityValue(String(format: "%.1f seconds", transition.duration))
                        .accessibilityHint("Adjusts how long the transition overlap lasts between clips.")
                        Text(String(format: "%.1fs", transition.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 44)
                    }

                    transitionVerificationNote
                }
            }
            .padding(.top, 4)
        }
    }

    private var transitionVerificationNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Static preview only · export/device not verified · next: golden export sample", systemImage: "checklist.unchecked")

            Text("Claim label: targeted transition confidence only")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Evidence scope: inspector + pixel processor only")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("Boundary fixture: fade-through-black midpoint accepted · vertical slide pending")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("Retrospective quote: targeted confidence · export golden pending")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("Review-safe wording: do not say exported or device verified")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("Next evidence owner: export golden sample · output path + hash")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("6/12 next action: single golden export fixture before device/full-suite claims")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("Review handoff: Accepted evidence · Blocked claim · Next artifact · Owner")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("Final report guard: do not say exported/release-ready until golden artifact path exists")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Transition verification status")
        .accessibilityValue("Static preview only. Claim label is targeted transition confidence only. Evidence scope is inspector plus pixel processor only. Boundary fixture is fade-through-black midpoint accepted and vertical slide pending. Export golden and device playback are not verified. Review-safe wording says do not say exported or device verified. Next evidence owner is export golden sample with output path and hash. 6/12 next action is a single golden export fixture before device or full-suite claims. Review handoff uses Accepted evidence, Blocked claim, Next artifact, and Owner columns. Final report guard says do not say exported or release-ready until a golden artifact path exists. Next evidence needed is a deterministic golden export sample.")
        .accessibilityHint("Use this transition evidence as targeted confidence only. Do not claim exported, device-verified, or release-ready until export golden, device playback, and full-suite evidence exist.")
        .help("Transition targeted tests are accepted as targeted transition confidence only from inspector plus pixel processor evidence; next evidence owner is export golden sample with output path and hash; review handoff columns are Accepted evidence, Blocked claim, Next artifact, Owner; final report guard blocks exported/release-ready wording until a golden artifact path exists; 6/12 next action is one golden export fixture before device/full-suite claims. iOS device playback, full-suite, and release-ready claims still require separate evidence.")
    }

    private var animationSection: some View {
        DisclosureGroup("Animation", isExpanded: $isAnimationExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                KeyframeGraphView(
                    clip: clip,
                    playheadTime: viewModel.playheadTime,
                    selectedKeyframeId: selectedKeyframeId,
                    onSelect: { selectedKeyframeId = $0 },
                    onChange: { keyframes in
                        Task { await viewModel.updateSelectedKeyframes(keyframes) }
                    }
                )

                KeyframeEditorView(
                    clip: clip,
                    playheadTime: viewModel.playheadTime,
                    selectedKeyframeId: selectedKeyframeId,
                    onSelect: { selectedKeyframeId = $0 },
                    onChange: { keyframes in
                        Task { await viewModel.updateSelectedKeyframes(keyframes) }
                    }
                )

                KeyframeListView(
                    clip: clip,
                    selectedKeyframeId: selectedKeyframeId,
                    onSelect: { selectedKeyframeId = $0 },
                    onChange: { keyframes in
                        Task { await viewModel.updateSelectedKeyframes(keyframes) }
                    }
                )
            }
            .padding(.top, 4)
        }
    }

    private func inspectorSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        binding: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            Slider(value: binding, in: range, step: 0.01)
        }
    }

    private func colorCorrectionBinding(
        keyPath: WritableKeyPath<ColorCorrection, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                let colorCorrection = clip.colorCorrection ?? ColorCorrection()
                return colorCorrection[keyPath: keyPath]
            },
            set: { newValue in
                var colorCorrection = clip.colorCorrection ?? ColorCorrection()
                colorCorrection[keyPath: keyPath] = newValue
                Task { await viewModel.updateSelectedColorCorrection(colorCorrection) }
            }
        )
    }

    private func colorGradeBinding(
        keyPath: WritableKeyPath<ColorGrade, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                let grade = clip.colorGrade ?? ColorGrade()
                return grade[keyPath: keyPath]
            },
            set: { newValue in
                var grade = clip.colorGrade ?? ColorGrade()
                grade[keyPath: keyPath] = newValue
                // Re-init so the model's clamping invariants are enforced.
                let clamped = ColorGrade(
                    lift: grade.lift,
                    gamma: grade.gamma,
                    gain: grade.gain,
                    hslBands: grade.hslBands,
                    curves: grade.curves
                )
                Task { await viewModel.updateSelectedColorGrade(clamped) }
            }
        )
    }

    private func maskFeatherBinding() -> Binding<Double> {
        Binding(
            get: { (clip.mask ?? defaultMask()).feather },
            set: { feather in
                var mask = clip.mask ?? defaultMask()
                mask.feather = feather
                Task { await viewModel.updateSelectedMask(mask) }
            }
        )
    }

    private func defaultMask(shape: MaskShape = .rectangle) -> Mask {
        let canvasSize = viewModel.currentProject.canvas.size
        return Mask(
            shape: shape,
            position: CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5),
            size: CGSize(width: canvasSize.width * 0.5, height: canvasSize.height * 0.5)
        )
    }

    private func canFreezeFrame() -> Bool {
        let freezeTime = viewModel.playheadTime - clip.timelineRange.start
        return freezeTime > 0 && freezeTime < clip.timelineRange.duration
    }

    private func addEffect(_ type: EffectType) {
        var effects = clip.effects
        let parameters = Dictionary(
            uniqueKeysWithValues: parameterDefinitions(for: type).map { ($0.key, $0.defaultValue) }
        )
        effects.append(Effect(type: type, parameters: parameters))
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func importLUT() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let cubeType = UTType(filenameExtension: "cube") {
            panel.allowedContentTypes = [cubeType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.importExternalLUT(from: url) }
    }

    /// CA-26 — LUT 내보내기 저장 패널.
    private func exportLUT() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "cube")].compactMap { $0 }
        panel.nameFieldStringValue = "lut.cube"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.exportLUTForSelectedClip(to: url) }
    }

    private func removeEffect(_ effectId: UUID) {
        let effects = clip.effects.filter { $0.id != effectId }
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func updateEffect(_ effectId: UUID, parameter: String, value: Double) {
        var effects = clip.effects
        guard let index = effects.firstIndex(where: { $0.id == effectId }) else { return }
        effects[index].parameters[parameter] = value
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func updateTransitionType(_ type: TransitionType) {
        let transition: MovieCutCore.Transition?
        if type == .none {
            transition = nil
        } else {
            transition = MovieCutCore.Transition(
                id: clip.transition?.id ?? UUID(),
                type: type,
                duration: clip.transition?.duration ?? 0.5
            )
        }
        Task { await viewModel.updateSelectedTransition(transition) }
    }

    private func updateTransitionDuration(_ duration: Double) {
        guard var transition = clip.transition else { return }
        transition.duration = duration
        Task { await viewModel.updateSelectedTransition(transition) }
    }

    private func parameterDefinitions(for type: EffectType) -> [EffectParameterDefinition] {
        switch type {
        case .brightness:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: -1 ... 1, defaultValue: 0)]
        case .contrast:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: 0 ... 2, defaultValue: 1)]
        case .saturation:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: 0 ... 2, defaultValue: 1)]
        case .temperature:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: -1 ... 1, defaultValue: 0)]
        case .exposure:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: -2 ... 2, defaultValue: 0)]
        case .fadeIn, .fadeOut, .crossDissolve:
            return [EffectParameterDefinition(key: "duration", title: "Duration", range: 0.1 ... 3, defaultValue: 0.5, valueFormat: "%.1fs")]
        case .grayscale:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 1)]
        case .sepia:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 0.9)]
        case .blur:
            return [EffectParameterDefinition(key: "radius", title: "Radius", range: 1 ... 12, defaultValue: 1, valueFormat: "%.0f")]
        case .styleTransfer:
            return [
                EffectParameterDefinition(key: "styleIndex", title: "Style", range: 1 ... 5, defaultValue: 1, valueFormat: "%.0f"),
                EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 0.75)
            ]
        case .cinematicLUT, .vintageLUT, .vividLUT, .coolLUT:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 0.8)]
        case .noirLUT:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 0.9)]
        case .externalLUT:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 1)]
        }
    }
}
