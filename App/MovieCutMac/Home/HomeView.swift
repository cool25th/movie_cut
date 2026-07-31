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

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 260), spacing: MovieCutSpacing.large)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MovieCutSpacing.large) {
                header

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
        .task { await refresh() }
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
