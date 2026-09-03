import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

/// The home screen (requirement 3.1): a grid of recent project cards plus
/// "New Project" / "Open…" entry points (requirement 3.2). Cards show the
/// save-time thumbnail, name, modification time, and composition duration
/// (requirement 3.1); entries whose file is missing are marked distinctly and
/// offer removal (requirement 3.4).
///
/// This view is deliberately self-contained: it takes the router, the view
/// model, and the recent-projects store as inputs, and it owns no global state.
/// All editor ↔ home transitions go through ``AppStageRouter``, whose decisions
/// are unit-tested via ``AppStagePolicy`` in Core (the harness bypasses home, so
/// that policy is the only coverage for the routing branches).
struct HomeView: View {
    @Bindable var router: AppStageRouter
    @Bindable var viewModel: EditorViewModel
    let store: RecentProjectsStore

    @State private var entries: [RecentProject] = []
    @State private var missingEntries: [RecentProject] = []
    @State private var errorMessage: String?

    @State private var isTemplatePickerPresented = false
    @State private var isPhotoPickerPresented = false

    /// CA-25 first-run welcome card: shown once per install until the user
    /// opens the sample project or skips it.
    @State private var showsOnboardingCard = false

    /// Slideshow options chosen in the "Photo to Video" configuration sheet
    /// before the multi-image picker opens.
    @State private var isSlideshowOptionsPresented = false
    @State private var slideshowPace: PhotoSlideshowPace = .normal
    @State private var slideshowTransition: PhotoSlideshowTransition = .crossDissolve
    @State private var slideshowKenBurnsEnabled = true

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: MovieCutSpacing.large)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MovieCutSpacing.large) {
                header

                if showsOnboardingCard {
                    onboardingCard
                }

                quickStartSection

                if entries.isEmpty && missingEntries.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: MovieCutSpacing.large) {
                        ForEach(entries) { entry in
                            recentCard(for: entry, isMissing: false)
                        }
                        ForEach(missingEntries) { entry in
                            recentCard(for: entry, isMissing: true)
                        }
                    }
                }
            }
            .padding(.horizontal, MovieCutSpacing.large)
            .padding(.vertical, MovieCutSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MovieCutTheme.editorBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(MovieCutTheme.accentCyan)
        .frame(minWidth: 1024, minHeight: 720)
        .navigationTitle("MovieCut")
        .task {
            await refresh()
            configureOnboarding()
        }
        // Refresh whenever the stage flips back to home (e.g. after returning
        // from the editor where a save may have just recorded a new entry).
        .onChange(of: router.stage) { _, newStage in
            if newStage == .home {
                Task { await refresh() }
            }
        }
        .alert("Couldn’t open project",
               isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isTemplatePickerPresented) {
            TemplatePickerView(viewModel: viewModel)
        }
        .sheet(isPresented: $isSlideshowOptionsPresented) {
            slideshowOptionsSheet
        }
        .fileImporter(
            isPresented: $isPhotoPickerPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                let scoped = urls.map { $0.startAccessingSecurityScopedResource() ? $0 : $0 }
                let pace = slideshowPace
                let transitionStyle = slideshowTransition
                let kenBurnsEnabled = slideshowKenBurnsEnabled
                Task {
                    await router.requestCreatePhotoSlideshow(
                        fromPhotoURLs: scoped,
                        pace: pace,
                        transitionStyle: transitionStyle,
                        kenBurnsEnabled: kenBurnsEnabled
                    )
                    scoped.forEach { $0.stopAccessingSecurityScopedResource() }
                }
            case .failure:
                errorMessage = "Couldn’t load the selected photos."
            }
        }
    }

    // MARK: - Slideshow options sheet

    /// Configuration sheet shown when the user taps "Photo to Video": pick a
    /// pace and a transition style, then open the multi-image picker. This is
    /// the difference between a watchable slideshow and a hard-cut sequence.
    private var slideshowOptionsSheet: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.large) {
            HStack {
                Text("Photo to Video")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") { isSlideshowOptionsPresented = false }
            }

            VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                Text("Pace")
                    .font(.headline)
                Picker("Pace", selection: $slideshowPace) {
                    ForEach(PhotoSlideshowPace.allCases) { pace in
                        Text("\(pace.displayName) (\(String(format: "%.1f", pace.clipDuration))s per photo)")
                            .tag(pace)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("home.slideshow.pace")
            }

            VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                Text("Transition")
                    .font(.headline)
                Picker("Transition", selection: $slideshowTransition) {
                    ForEach(PhotoSlideshowTransition.allCases) { transition in
                        Text(transition.displayName).tag(transition)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("home.slideshow.transition")
            }

            Toggle(isOn: $slideshowKenBurnsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Motion (Ken Burns)")
                        .font(.headline)
                    Text("Add a slow zoom to each photo.")
                        .font(MovieCutTypography.metadata)
                        .foregroundStyle(MovieCutTheme.mutedText)
                }
            }
            .accessibilityIdentifier("home.slideshow.kenBurns")

            Text("\(slideshowTransition == .none ? "Hard cuts" : slideshowTransition.displayName) between photos at \(String(format: "%.1f", slideshowPace.clipDuration))s each\(slideshowKenBurnsEnabled ? ", with motion" : "").")
                .font(MovieCutTypography.metadata)
                .foregroundStyle(MovieCutTheme.mutedText)

            Spacer()

            HStack {
                Spacer()
                Button {
                    isSlideshowOptionsPresented = false
                    // Open the photo picker after the options sheet dismisses.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isPhotoPickerPresented = true
                    }
                } label: {
                    Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("home.slideshow.choosePhotos")
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
    }

    // MARK: - Onboarding (CA-25)

    /// Shows the card exactly once per install: records the first launch,
    /// shows the 3-step guide (import → subtitles → export) until dismissed,
    /// and stays out of UI-test launches that drive the home stage.
    private func configureOnboarding() {
        guard ProcessInfo.processInfo.environment["MOVIECUT_DISABLE_ONBOARDING"] == nil else { return }
        let metrics = viewModel.onboardingMetrics
        metrics.record(.firstLaunch)
        guard !metrics.isDismissed else { return }
        metrics.record(.onboardingShown)
        showsOnboardingCard = true
    }

    private func dismissOnboarding() {
        viewModel.onboardingMetrics.isDismissed = true
        showsOnboardingCard = false
    }

    private func openSampleProject() {
        Task {
            await router.requestOpenBundledSampleProject()
            if viewModel.lastErrorMessage == nil {
                dismissOnboarding()
            }
        }
    }

    /// The first-run guide: three steps to a first export, plus the bundled
    /// sample project as the zero-setup path through them (offline).
    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to MovieCut")
                        .font(.title2.weight(.semibold))
                    Text("Three steps to your first export")
                        .font(MovieCutTypography.metadata)
                        .foregroundStyle(MovieCutTheme.mutedText)
                }
                Spacer()
                Button("Skip") { dismissOnboarding() }
                    .accessibilityIdentifier("home.onboarding.skip")
            }

            HStack(alignment: .top, spacing: MovieCutSpacing.medium) {
                onboardingStep(
                    number: "1",
                    title: "Import your clip",
                    detail: "Drop in a clip from your iPhone.",
                    icon: "square.and.arrow.down"
                )
                onboardingStep(
                    number: "2",
                    title: "Add subtitles",
                    detail: "Auto-transcribe your speech.",
                    icon: "captions.bubble"
                )
                onboardingStep(
                    number: "3",
                    title: "Export",
                    detail: "Ship a 9:16 short.",
                    icon: "square.and.arrow.up"
                )
            }

            Button {
                openSampleProject()
            } label: {
                Label("Open the sample project", systemImage: "play.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("home.onboarding.openSample")
        }
        .padding(MovieCutSpacing.large)
        .background(MovieCutTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.large)
                .stroke(MovieCutTheme.border.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to MovieCut")
        .accessibilityHint("Three steps to your first export: import, subtitles, export.")
    }

    private func onboardingStep(number: String, title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: MovieCutSpacing.small) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(MovieCutTheme.accentCyan)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // The step title/detail arrive as catalog keys; resolve here
                // because Text() renders a runtime String verbatim.
                Text("\(number). \(NSLocalizedString(title, comment: "Onboarding step title"))")
                    .font(MovieCutTypography.cardTitle)
                Text(NSLocalizedString(detail, comment: "Onboarding step detail"))
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(MovieCutTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Quick Start

    /// CapCut-style entry points surfaced on the home screen: a blank project,
    /// a template gallery, and a one-click "Photo to Video" slideshow builder.
    /// These sit above the recent-projects grid so a first-run user can start
    /// creating without first opening a blank editor to hunt for actions.
    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
            Text("Start something new")
                .font(.headline)
                .foregroundStyle(MovieCutTheme.mutedText)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: MovieCutSpacing.medium) {
                quickStartCard(
                    title: "New Project",
                    icon: "rectangle.stack.badge.plus",
                    description: "Start with a blank timeline.",
                    identifier: "home.quickStart.newProject"
                ) {
                    Task { await router.requestNewProject() }
                }

                quickStartCard(
                    title: "Templates",
                    icon: "square.grid.2x2",
                    description: "Begin with a ready-made layout.",
                    identifier: "home.quickStart.templates"
                ) {
                    isTemplatePickerPresented = true
                }

                quickStartCard(
                    title: "Photo to Video",
                    icon: "photo.stack",
                    description: "Turn your photos into a 9:16 short.",
                    identifier: "home.quickStart.photoToVideo"
                ) {
                    isSlideshowOptionsPresented = true
                }
            }
        }
    }

    private func quickStartCard(
        title: String,
        icon: String,
        description: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(MovieCutTheme.accentCyan)
                    .accessibilityHidden(true)

                Text(title)
                    .font(MovieCutTypography.cardTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(description)
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(MovieCutTheme.mutedText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(MovieCutSpacing.medium)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(MovieCutTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: MovieCutRadius.large)
                    .stroke(MovieCutTheme.border.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: MovieCutSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent Projects")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(entries.isEmpty ? "Create or open a project to get started." : "\(entries.count) project\(entries.count == 1 ? "" : "s")")
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(MovieCutTheme.mutedText)
            }
            Spacer()
            Button {
                Task { await router.requestNewProject() }
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .accessibilityIdentifier("home.newProject")
            .keyboardShortcut("n", modifiers: .command)

            Button {
                openWithPanel()
            } label: {
                Label("Open…", systemImage: "folder")
            }
            .accessibilityIdentifier("home.open")
            .keyboardShortcut("o", modifiers: .command)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: MovieCutSpacing.medium) {
            Image(systemName: "film.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(MovieCutTheme.mutedText)
                .accessibilityHidden(true)
            Text("No recent projects yet")
                .font(.headline)
                .foregroundStyle(MovieCutTheme.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Cards

    private func recentCard(for entry: RecentProject, isMissing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                thumbnail(for: entry)
                    .frame(height: 124)
                    .frame(maxWidth: .infinity)
                    .clipped()
                // Duration badge, bottom-right.
                if entry.duration > 0 {
                    Text(Self.durationFormatter.string(from: entry.duration) ?? "")
                        .font(MovieCutTypography.micro)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            VStack(alignment: .leading, spacing: MovieCutSpacing.xxSmall) {
                Text(entry.name)
                    .font(MovieCutTypography.cardTitle)
                    .lineLimit(1)
                    .foregroundStyle(isMissing ? MovieCutTheme.mutedText : .white)
                Text(Self.modificationFormatter.string(from: entry.modificationDate))
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(MovieCutTheme.mutedText)
                if isMissing {
                    Text("File missing")
                        .font(MovieCutTypography.metadata)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("home.card.missing.\(entry.id.uuidString)")
                }
            }
            .padding(MovieCutSpacing.small)
        }
        .background(MovieCutTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.large)
                .stroke(MovieCutTheme.border.opacity(0.4), lineWidth: 1)
        )
        .opacity(isMissing ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if isMissing {
                // Tapping a missing card offers removal rather than a doomed open.
                offerRemoval(of: entry)
            } else {
                Task { await open(entry: entry) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: entry, isMissing: isMissing))
        .accessibilityHint(isMissing ? "File missing. Double tap to remove from the list." : "Double tap to open.")
        .accessibilityIdentifier("home.card.\(entry.id.uuidString)")
        .contextMenu {
            if isMissing {
                Button("Remove from Recent", role: .destructive) {
                    Task { await remove(entry) }
                }
            } else {
                Button("Open") { Task { await open(entry: entry) } }
            }
            Divider()
            Button("Remove from Recent", role: .destructive) {
                Task { await remove(entry) }
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for entry: RecentProject) -> some View {
        if let path = entry.thumbnailPath,
           let nsImage = NSImage(contentsOf: URL(fileURLWithPath: path)) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(MovieCutTheme.elevatedCardBackground)
                .overlay(
                    Image(systemName: "film")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(MovieCutTheme.mutedText)
                )
        }
    }

    private func accessibilityLabel(for entry: RecentProject, isMissing: Bool) -> String {
        let durationText = entry.duration > 0
            ? (Self.durationFormatter.string(from: entry.duration) ?? "")
            : ""
        let missingText = isMissing ? ", file missing" : ""
        return "\(entry.name), modified \(Self.modificationFormatter.string(from: entry.modificationDate))\(durationText.isEmpty ? "" : ", \(durationText)")\(missingText)"
    }

    // MARK: - Actions

    private func open(entry: RecentProject) async {
        // Resolve the bookmark through the single-owner SecurityScopedAccess so
        // the sandbox re-reaches the file (requirement 3.5). A nil resolution
        // means the file moved/was deleted since the list was loaded; refresh
        // and tell the user instead of silently failing.
        guard let resolved = SecurityScopedAccess.resolveBookmark(for: entry.urlBookmark) else {
            errorMessage = "“\(entry.name)” can’t be found. It may have been moved or deleted."
            await refresh()
            return
        }
        let didOpen = await router.requestOpenProject(at: resolved.url, bookmark: entry.urlBookmark)
        if !didOpen {
            errorMessage = viewModel.lastErrorMessage ?? "Couldn’t open “\(entry.name)”."
        }
    }

    private func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "moviecut") ?? .json,
            .json
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // No bookmark yet for a freshly-picked file; the open path captures one
        // when the project is next saved (which records it to the recent list).
        Task { _ = await router.requestOpenProject(at: url, bookmark: SecurityScopedAccess.makeBookmark(for: url)) }
    }

    private func offerRemoval(of entry: RecentProject) {
        let alert = NSAlert()
        alert.messageText = "Remove “\(entry.name)” from Recent?"
        alert.informativeText = "The project file can’t be found. This only removes the entry from the list; it does not delete any file."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await remove(entry) }
        }
    }

    private func remove(_ entry: RecentProject) async {
        _ = try? await store.remove(entry.id)
        await refresh()
    }

    private func refresh() async {
        // Partition so missing files are shown distinctly (requirement 3.4) but
        // remain removable. The store is the single source of truth for the list.
        let partition = await store.partitionedByReachability()
        entries = partition.present
        missingEntries = partition.missing
    }

    // MARK: - Formatters (shared, locale-aware)

    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .positional
        f.zeroFormattingBehavior = .pad
        return f
    }()

    private static let modificationFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()
}
