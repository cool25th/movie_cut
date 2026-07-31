import AppKit
import MovieCutCore
import SwiftUI

private struct NativeAccessibilityStaticTextBacking: NSViewRepresentable {
    let identifier: String
    let label: String
    let hint: String?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSView) {
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.staticText)
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityLabel(label)
        view.setAccessibilityHelp(hint)
    }
}

private struct NativeAccessibilityStaticTextModifier: ViewModifier {
    let identifier: String
    let label: String
    let hint: String?
    let hidesContent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if hidesContent {
            content
                .accessibilityHidden(true)
                .overlay { accessibilityBacking }
        } else {
            content
                .overlay { accessibilityBacking }
        }
    }

    private var accessibilityBacking: some View {
        NativeAccessibilityStaticTextBacking(
            identifier: identifier,
            label: label,
            hint: hint
        )
        .allowsHitTesting(false)
    }
}

extension View {
    func nativeAccessibilityStaticText(
        identifier: String,
        label: String,
        hint: String? = nil,
        hidesContent: Bool = true
    ) -> some View {
        modifier(NativeAccessibilityStaticTextModifier(
            identifier: identifier,
            label: label,
            hint: hint,
            hidesContent: hidesContent
        ))
    }
}

extension CardFormat {
    var accessibilityTitle: String {
        switch self {
        case .square: "1:1"
        case .portrait: "4:5"
        case .story: "9:16"
        }
    }

}

private extension CardPageRole {
    var displayTitle: String {
        switch self {
        case .cover: "Cover"
        case .body: "Body"
        case .emphasis: "Emphasis"
        case .closing: "Closing"
        }
    }
}

/// G-18 Inc 2's explicit card-document editing mode. Persisted page and format
/// mutations are delegated to EditorViewModel's EditorSession-backed APIs.
struct CardEditorView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var selectedPageID: UUID?
    @State private var dropTargetPageID: UUID?

    private static let formats: [CardFormat] = [.square, .portrait, .story]

    var body: some View {
        if let document = viewModel.currentProject.cardDocument {
            VStack(spacing: 0) {
                header(document: document)

                Divider()
                    .overlay(MovieCutTheme.divider)

                HSplitView {
                    pageRail(document: document)
                        .frame(minWidth: 210, idealWidth: 230, maxWidth: 260)

                    pageWorkspace(document: document)
                        .frame(minWidth: 520)

                    CardTemplateGallery(viewModel: viewModel)
                        .frame(minWidth: 290, idealWidth: 310, maxWidth: 340)
                }

                footer(document: document)
            }
            .frame(minWidth: 1024, minHeight: 720)
            .background(MovieCutTheme.editorBackground)
            .onAppear {
                reconcileSelection(with: document.pages)
            }
            .onChange(of: document.pages.map(\.id)) { _, _ in
                reconcileSelection(with: document.pages)
            }
        }
    }

    private func header(document: CardDocument) -> some View {
        HStack(spacing: MovieCutSpacing.medium) {
            MovieCutIconTitle(
                title: "Card Editor",
                systemImage: "rectangle.stack",
                subtitle: document.title,
                iconColor: MovieCutTheme.accentCyan,
                titleFont: .headline
            )

            Text("\(document.pages.count) pages")
                .font(MovieCutTypography.metadata.monospacedDigit())
                .foregroundStyle(MovieCutTheme.mutedText)
                .nativeAccessibilityStaticText(
                    identifier: "cardEditor.pageCount",
                    label: "\(document.pages.count) pages"
                )

            Spacer(minLength: MovieCutSpacing.large)

            VStack(alignment: .trailing, spacing: MovieCutSpacing.xxSmall) {
                Picker(
                    "Card format",
                    selection: Binding(
                        get: { viewModel.currentProject.cardDocument?.format ?? .square },
                        set: { format in
                            Task { await viewModel.setCardFormat(format) }
                        }
                    )
                ) {
                    ForEach(Self.formats, id: \.self) { format in
                        Text(format.accessibilityTitle).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 230)
                .accessibilityIdentifier("cardEditor.formatPicker")
                .accessibilityLabel("Card format")
                .accessibilityHint("Changes every page between square, portrait, and story formats while retaining normalized layout.")

                Text("Format: \(document.format.accessibilityTitle)")
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(MovieCutTheme.mutedText)
                    .nativeAccessibilityStaticText(
                        identifier: "cardEditor.formatStatus",
                        label: "Format: \(document.format.accessibilityTitle)"
                    )
            }
        }
        .padding(.horizontal, MovieCutSpacing.large)
        .padding(.vertical, MovieCutSpacing.medium)
        .background(MovieCutTheme.panelBackgroundRaised)
    }

    private func pageRail(document: CardDocument) -> some View {
        VStack(spacing: 0) {
            MovieCutPanelHeader(
                title: "Pages",
                systemImage: "rectangle.stack",
                subtitle: "Drag to reorder"
            ) {
                pageControls(document: document)
            }

            ScrollView {
                LazyVStack(spacing: MovieCutSpacing.medium) {
                    ForEach(Array(document.pages.enumerated()), id: \.element.id) { index, page in
                        pageThumbnail(
                            page: page,
                            index: index,
                            format: document.format
                        )
                    }
                }
                .padding(MovieCutSpacing.medium)
            }
            .movieCutScrollBackground(MovieCutTheme.panelBackground)
            .accessibilityIdentifier("cardEditor.pageRail")
        }
        .background(MovieCutTheme.panelBackground)
    }

    private func pageControls(document: CardDocument) -> some View {
        HStack(spacing: MovieCutSpacing.xSmall) {
            cardControlButton(
                title: "Add page",
                systemImage: "plus",
                identifier: "cardEditor.addPage"
            ) {
                Task {
                    if let pageID = await viewModel.addCardPage(after: selectedPageID) {
                        selectedPageID = pageID
                    }
                }
            }

            cardControlButton(
                title: "Duplicate page",
                systemImage: "plus.square.on.square",
                identifier: "cardEditor.duplicatePage",
                isDisabled: selectedPageID == nil
            ) {
                guard let selectedPageID else { return }
                Task {
                    if let pageID = await viewModel.duplicateCardPage(selectedPageID) {
                        self.selectedPageID = pageID
                    }
                }
            }

            cardControlButton(
                title: "Delete page",
                systemImage: "trash",
                identifier: "cardEditor.deletePage",
                isDisabled: selectedPageID == nil || document.pages.count <= 1
            ) {
                guard let selectedPageID else { return }
                Task {
                    self.selectedPageID = await viewModel.deleteCardPage(selectedPageID)
                }
            }
        }
    }

    private func cardControlButton(
        title: String,
        systemImage: String,
        identifier: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(isDisabled)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityHint("Updates the card page list and can be undone.")
        .accessibilityIdentifier(identifier)
    }

    private func pageThumbnail(
        page: CardPage,
        index: Int,
        format: CardFormat
    ) -> some View {
        let isSelected = selectedPageID == page.id
        let isDropTarget = dropTargetPageID == page.id

        return Button {
            selectedPageID = page.id
        } label: {
            HStack(alignment: .top, spacing: MovieCutSpacing.small) {
                Text("\(index + 1)")
                    .font(MovieCutTypography.metadata.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isSelected ? MovieCutTheme.accentCyan : MovieCutTheme.mutedText)
                    .frame(width: 22, alignment: .trailing)

                VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                    CardPageArtwork(
                        page: page,
                        format: format,
                        mediaAssets: viewModel.currentProject.mediaLibrary.assets
                    )
                    .frame(width: 126)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 2)

                    HStack {
                        Text(page.role.displayTitle)
                            .font(MovieCutTypography.cardTitle)
                        Spacer(minLength: MovieCutSpacing.xSmall)
                        Text("\(page.elements.count) elements")
                            .font(MovieCutTypography.micro)
                            .foregroundStyle(MovieCutTheme.mutedText)
                    }
                }
            }
            .padding(MovieCutSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                    .fill(isSelected ? MovieCutTheme.selectedFill : MovieCutTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                    .stroke(
                        isDropTarget ? MovieCutTheme.accentCyan : (isSelected ? MovieCutTheme.accentCyan.opacity(0.72) : MovieCutTheme.border),
                        lineWidth: isDropTarget ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cardEditor.page.\(index + 1)")
        .accessibilityLabel("Page \(index + 1), \(page.role.displayTitle), \(page.elements.count) elements")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Select this page. Drag it onto another page to reorder the document.")
        .draggable(page.id.uuidString) {
            Label("Page \(index + 1)", systemImage: "rectangle.stack")
                .padding(MovieCutSpacing.small)
                .background(MovieCutTheme.panelBackgroundRaised)
        }
        .dropDestination(for: String.self) { identifiers, _ in
            guard let rawIdentifier = identifiers.first,
                  let draggedPageID = UUID(uuidString: rawIdentifier),
                  draggedPageID != page.id else {
                return false
            }
            selectedPageID = draggedPageID
            Task { await viewModel.moveCardPage(draggedPageID, to: index) }
            return true
        } isTargeted: { isTargeted in
            dropTargetPageID = isTargeted ? page.id : nil
        }
    }

    private func pageWorkspace(document: CardDocument) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: MovieCutSpacing.medium) {
                if let selection = selectedPage(in: document) {
                    VStack(alignment: .leading, spacing: MovieCutSpacing.xxSmall) {
                        Text("Page \(selection.index + 1) of \(document.pages.count)")
                            .font(.headline)
                        Text("\(selection.page.role.displayTitle) · normalized layout preview")
                            .font(MovieCutTypography.panelSubtitle)
                            .foregroundStyle(MovieCutTheme.mutedText)
                    }

                    Spacer()

                    HStack(spacing: MovieCutSpacing.xSmall) {
                        cardControlButton(
                            title: "Move page earlier",
                            systemImage: "chevron.up",
                            identifier: "cardEditor.moveEarlier",
                            isDisabled: selection.index == 0
                        ) {
                            moveSelectedPage(to: selection.index - 1)
                        }

                        cardControlButton(
                            title: "Move page later",
                            systemImage: "chevron.down",
                            identifier: "cardEditor.moveLater",
                            isDisabled: selection.index >= document.pages.count - 1
                        ) {
                            moveSelectedPage(to: selection.index + 1)
                        }
                    }
                }
            }
            .padding(.horizontal, MovieCutSpacing.large)
            .padding(.vertical, MovieCutSpacing.medium)
            .background(MovieCutTheme.panelBackgroundRaised)

            ZStack {
                MovieCutTheme.previewWellBackground

                if let selection = selectedPage(in: document) {
                    CardCanvasView(
                        page: selection.page,
                        format: document.format,
                        viewModel: viewModel
                    )
                } else {
                    VStack(spacing: MovieCutSpacing.medium) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 34))
                            .foregroundStyle(MovieCutTheme.mutedText)
                        Text("Add a page to begin")
                            .foregroundStyle(MovieCutTheme.mutedText)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MovieCutTheme.previewWellBackground)
    }

    private func footer(document: CardDocument) -> some View {
        HStack(spacing: MovieCutSpacing.medium) {
            if let selection = selectedPage(in: document) {
                Text("Selected page \(selection.index + 1) of \(document.pages.count)")
                    .nativeAccessibilityStaticText(
                        identifier: "cardEditor.selectionStatus",
                        label: "Selected page \(selection.index + 1) of \(document.pages.count)"
                    )
            } else {
                Text("No page selected")
                    .nativeAccessibilityStaticText(
                        identifier: "cardEditor.selectionStatus",
                        label: "No page selected"
                    )
            }

            Text("IDs and normalized element frames are preserved across format changes")
                .foregroundStyle(MovieCutTheme.mutedText)

            Spacer()

            Text(viewModel.lastErrorMessage ?? viewModel.lastStatusMessage ?? "")
                .foregroundStyle(viewModel.lastErrorMessage == nil ? MovieCutTheme.mutedText : .red)
                .lineLimit(1)
                .accessibilityIdentifier("moviecut.status")
        }
        .font(MovieCutTypography.metadata)
        .padding(.horizontal, MovieCutSpacing.medium)
        .padding(.vertical, MovieCutSpacing.xSmall)
        .background(MovieCutTheme.panelBackgroundRaised)
    }

    private func selectedPage(in document: CardDocument) -> (index: Int, page: CardPage)? {
        guard let selectedPageID,
              let index = document.pages.firstIndex(where: { $0.id == selectedPageID }) else {
            return nil
        }
        return (index, document.pages[index])
    }

    private func reconcileSelection(with pages: [CardPage]) {
        guard !pages.isEmpty else {
            selectedPageID = nil
            return
        }
        if let selectedPageID, pages.contains(where: { $0.id == selectedPageID }) {
            return
        }
        selectedPageID = pages[0].id
    }

    private func moveSelectedPage(to destinationIndex: Int) {
        guard let selectedPageID else { return }
        Task { await viewModel.moveCardPage(selectedPageID, to: destinationIndex) }
    }
}

private struct CardPageArtwork: View {
    let page: CardPage
    let format: CardFormat
    let mediaAssets: [UUID: MediaAsset]

    var body: some View {
        ZStack {
            Color.white

            GeometryReader { proxy in
                ForEach(page.elements) { element in
                    elementView(element, canvasSize: proxy.size)
                        .frame(
                            width: CGFloat(element.normalizedFrame.width) * proxy.size.width,
                            height: CGFloat(element.normalizedFrame.height) * proxy.size.height
                        )
                        .position(
                            x: CGFloat(element.normalizedFrame.x + element.normalizedFrame.width / 2) * proxy.size.width,
                            y: CGFloat(element.normalizedFrame.y + element.normalizedFrame.height / 2) * proxy.size.height
                        )
                }
            }
        }
        .aspectRatio(CardLayout.aspectRatio(for: format), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(Color.black.opacity(0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func elementView(_ element: CardElement, canvasSize: CGSize) -> some View {
        switch element.kind {
        case .text:
            Text(element.text?.text ?? "Text")
                .font(.system(
                    size: max(6, min(canvasSize.width * 0.065, CGFloat(element.text?.fontSize ?? 24))),
                    weight: element.text?.isBold == true ? .bold : .semibold
                ))
                .multilineTextAlignment(textAlignment(element.text?.alignment ?? .center))
                .foregroundStyle(Color(cardHex: element.text?.fontColor ?? "#111111"))
                .padding(max(2, canvasSize.width * 0.008))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment(element.text?.alignment ?? .center))
                .background(Color(cardHex: element.text?.backgroundColor ?? "#00000000"))
                .clipped()

        case .image, .logo:
            if let mediaAssetID = element.mediaAssetID,
               let data = mediaAssets[mediaAssetID]?.thumbnailData,
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                ZStack {
                    Color.black.opacity(element.kind == .logo ? 0.10 : 0.06)
                    Image(systemName: element.kind == .logo ? "seal" : "photo")
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .foregroundStyle(Color.black.opacity(0.42))
                }
            }
        }
    }

    private func textAlignment(_ alignment: MovieCutCore.TextAlignment) -> SwiftUI.TextAlignment {
        switch alignment {
        case .leading: .leading
        case .center, .justified: .center
        case .trailing: .trailing
        }
    }

    private func frameAlignment(_ alignment: MovieCutCore.TextAlignment) -> Alignment {
        switch alignment {
        case .leading: .leading
        case .center, .justified: .center
        case .trailing: .trailing
        }
    }
}

extension Color {
    init(cardHex: String) {
        let raw = cardHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        switch raw.count {
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        default:
            red = 0.07
            green = 0.07
            blue = 0.07
            alpha = 1
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
