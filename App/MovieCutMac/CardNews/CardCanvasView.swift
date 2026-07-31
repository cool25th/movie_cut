import AppKit
import MovieCutCore
import SwiftUI
import UniformTypeIdentifiers

/// G-18's real selected-page canvas. NormalizedRect is always the persisted
/// source of truth; pixel geometry exists only for drawing and local gestures.
struct CardCanvasView: View {
    let page: CardPage
    let format: CardFormat
    @Bindable var viewModel: EditorViewModel

    @State private var selectedElementID: UUID?
    @State private var moveDraft: GeometryDraft?
    @State private var resizeDraft: GeometryDraft?
    @State private var editingElementID: UUID?
    @State private var inlineDraft = ""
    @State private var inlineOriginal = ""
    @FocusState private var inlineEditorFocused: Bool

    private struct GeometryDraft {
        let elementID: UUID
        let frame: NormalizedRect
    }

    var body: some View {
        VStack(spacing: 0) {
            canvasToolbar

            GeometryReader { proxy in
                let canvasSize = fittedCanvasSize(in: proxy.size)
                canvas(size: canvasSize)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .padding(32)
            .background(MovieCutTheme.previewWellBackground)

            canvasStatus
        }
        .onAppear(perform: reconcileSelection)
        .onChange(of: page.id) { _, _ in
            cancelInlineEditing()
            moveDraft = nil
            resizeDraft = nil
            reconcileSelection()
        }
        .onChange(of: page.elements.map(\.id)) { _, _ in
            reconcileSelection()
        }
        .onChange(of: inlineEditorFocused) { _, isFocused in
            if !isFocused, editingElementID != nil {
                commitInlineEditing()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card canvas editing surface")
        .accessibilityIdentifier("cardCanvas.surface")
    }

    private var selectedElement: CardElement? {
        guard let selectedElementID else { return nil }
        return page.elements.first { $0.id == selectedElementID }
    }

    private var canvasToolbar: some View {
        HStack(spacing: MovieCutSpacing.small) {
            Label("Canvas", systemImage: "rectangle.dashed")
                .font(.headline)

            Text(format.accessibilityTitle)
                .font(MovieCutTypography.metadata.monospacedDigit())
                .foregroundStyle(MovieCutTheme.mutedText)

            Spacer()

            if let selectedElement,
               selectedElement.kind == .image || selectedElement.kind == .logo {
                Button {
                    chooseReplacementImage(for: selectedElement)
                } label: {
                    Label("Replace Image…", systemImage: "photo.badge.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("cardCanvas.replaceImage")
                .accessibilityLabel("Replace selected card image")
                .accessibilityHint("Choose an image file and replace this element in one undoable action.")
            }

            Text("Double-click text to edit · drag to move · drag the handle to resize")
                .font(MovieCutTypography.metadata)
                .foregroundStyle(MovieCutTheme.mutedText)
        }
        .padding(.horizontal, MovieCutSpacing.medium)
        .padding(.vertical, MovieCutSpacing.small)
        .background(MovieCutTheme.panelBackgroundRaised)
    }

    private var canvasStatus: some View {
        HStack(spacing: MovieCutSpacing.medium) {
            if let selectedElement {
                Text("Selected \(selectedElement.kind.rawValue) \(selectedElement.id.uuidString)")
                Text(frameStatus(displayFrame(for: selectedElement)))
                    .foregroundStyle(MovieCutTheme.mutedText)
            } else {
                Text("No element selected")
            }

            Spacer()

            Text(viewModel.lastErrorMessage ?? viewModel.lastStatusMessage ?? "Ready")
                .foregroundStyle(viewModel.lastErrorMessage == nil ? MovieCutTheme.mutedText : .red)
                .lineLimit(1)
        }
        .font(MovieCutTypography.metadata.monospacedDigit())
        .padding(.horizontal, MovieCutSpacing.medium)
        .padding(.vertical, MovieCutSpacing.xSmall)
        .background(MovieCutTheme.panelBackgroundRaised)
        .accessibilityIdentifier("cardCanvas.status")
        .accessibilityLabel("Card canvas status")
    }

    private func canvas(size: CGSize) -> some View {
        ZStack {
            Color.white
                .contentShape(Rectangle())
                .onTapGesture {
                    if editingElementID == nil {
                        selectedElementID = nil
                    }
                }

            ForEach(page.elements) { element in
                elementLayer(element, canvasSize: size)
                    .zIndex(selectedElementID == element.id ? 2 : 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(Color.black.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.42), radius: 20, y: 9)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cardCanvas.canvas")
        .accessibilityLabel("Card canvas, \(format.accessibilityTitle), \(page.elements.count) elements")
    }

    private func elementLayer(_ element: CardElement, canvasSize: CGSize) -> some View {
        let frame = displayFrame(for: element)
        let pixelRect = CardLayout.pixelRect(for: frame, in: canvasSize)
        let isSelected = selectedElementID == element.id
        let isEditing = editingElementID == element.id

        return ZStack(alignment: .bottomTrailing) {
            if isEditing, element.kind == .text {
                inlineEditor(for: element)
            } else {
                elementArtwork(element, canvasSize: canvasSize)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        selectedElementID = element.id
                        if element.kind == .text {
                            beginInlineEditing(element)
                        }
                    }
                    .onTapGesture {
                        selectedElementID = element.id
                    }
                    .simultaneousGesture(moveGesture(for: element, canvasSize: canvasSize))
                    .accessibilityHidden(true)
            }

            if isSelected, !isEditing {
                Circle()
                    .fill(MovieCutTheme.accentCyan)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .frame(width: 18, height: 18)
                    .offset(x: 9, y: 9)
                    .contentShape(Rectangle().inset(by: -10))
                    .gesture(resizeGesture(for: element, canvasSize: canvasSize))
                    .accessibilityIdentifier("cardCanvas.resizeHandle.\(element.id.uuidString)")
                    .accessibilityLabel("Resize selected \(element.kind.rawValue) element")
                    .accessibilityHint("Drag the handle to resize while keeping the element inside the card.")
            }
        }
        .frame(width: pixelRect.width, height: pixelRect.height)
        .nativeAccessibilityStaticText(
            identifier: "cardCanvas.element.\(element.id.uuidString)",
            label: elementAccessibilityLabel(element),
            hint: element.kind == .text
                ? "Double-click to edit inline. Drag to move."
                : "Drag to move. Select to reveal image replacement and resize controls.",
            hidesContent: false
        )
        .position(x: pixelRect.midX, y: pixelRect.midY)
        .overlay {
            if isSelected {
                Rectangle()
                    .stroke(MovieCutTheme.accentCyan, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .allowsHitTesting(false)
            }
        }
    }

    private func inlineEditor(for element: CardElement) -> some View {
        ZStack(alignment: .topTrailing) {
            TextField("Card text", text: $inlineDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: element.text?.isBold == true ? .bold : .regular))
                .foregroundStyle(Color(cardHex: element.text?.fontColor ?? "#111111"))
                .padding(8)
                .background(Color.white.opacity(0.96))
                .focused($inlineEditorFocused)
                .onSubmit(commitInlineEditing)
                .onExitCommand(perform: cancelInlineEditing)
                .accessibilityIdentifier("cardCanvas.inlineEditor")
                .accessibilityLabel("Inline card text editor")
                .accessibilityValue(inlineDraft)

            HStack(spacing: 4) {
                Button(action: cancelInlineEditing) {
                    Image(systemName: "xmark")
                }
                .accessibilityIdentifier("cardCanvas.inlineCancel")
                .accessibilityLabel("Cancel inline text edit")

                Button(action: commitInlineEditing) {
                    Image(systemName: "checkmark")
                }
                .accessibilityIdentifier("cardCanvas.inlineCommit")
                .accessibilityLabel("Commit inline text edit")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .padding(4)
        }
    }

    @ViewBuilder
    private func elementArtwork(_ element: CardElement, canvasSize: CGSize) -> some View {
        switch element.kind {
        case .text:
            Text(element.text?.text ?? "Text")
                .font(.system(
                    size: max(10, min(canvasSize.width * 0.065, CGFloat(element.text?.fontSize ?? 24))),
                    weight: element.text?.isBold == true ? .bold : .semibold
                ))
                .multilineTextAlignment(textAlignment(element.text?.alignment ?? .center))
                .foregroundStyle(Color(cardHex: element.text?.fontColor ?? "#111111"))
                .padding(max(4, canvasSize.width * 0.008))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: frameAlignment(element.text?.alignment ?? .center)
                )
                .background(Color(cardHex: element.text?.backgroundColor ?? "#00000000"))
                .clipped()

        case .image, .logo:
            if let image = image(for: element) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else {
                ZStack {
                    Color.black.opacity(element.kind == .logo ? 0.10 : 0.06)
                    VStack(spacing: 6) {
                        Image(systemName: element.kind == .logo ? "seal" : "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 52, maxHeight: 52)
                        Text(element.kind == .logo ? "Select logo to replace" : "Select image to replace")
                            .font(MovieCutTypography.micro)
                    }
                    .padding(8)
                    .foregroundStyle(Color.black.opacity(0.48))
                }
            }
        }
    }

    private func moveGesture(for element: CardElement, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard editingElementID == nil else { return }
                selectedElementID = element.id
                moveDraft = GeometryDraft(
                    elementID: element.id,
                    frame: CardLayout.moving(
                        element.normalizedFrame,
                        deltaX: value.translation.width / canvasSize.width,
                        deltaY: value.translation.height / canvasSize.height
                    )
                )
            }
            .onEnded { value in
                guard editingElementID == nil else { return }
                let finalFrame = CardLayout.moving(
                    element.normalizedFrame,
                    deltaX: value.translation.width / canvasSize.width,
                    deltaY: value.translation.height / canvasSize.height
                )
                moveDraft = nil
                commitGeometry(element, frame: finalFrame)
            }
    }

    private func resizeGesture(for element: CardElement, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                resizeDraft = GeometryDraft(
                    elementID: element.id,
                    frame: CardLayout.resizing(
                        element.normalizedFrame,
                        deltaWidth: value.translation.width / canvasSize.width,
                        deltaHeight: value.translation.height / canvasSize.height
                    )
                )
            }
            .onEnded { value in
                let finalFrame = CardLayout.resizing(
                    element.normalizedFrame,
                    deltaWidth: value.translation.width / canvasSize.width,
                    deltaHeight: value.translation.height / canvasSize.height
                )
                resizeDraft = nil
                commitGeometry(element, frame: finalFrame)
            }
    }

    private func commitGeometry(_ element: CardElement, frame: NormalizedRect) {
        guard frame != element.normalizedFrame else { return }
        var updated = element
        updated.normalizedFrame = frame
        Task { await viewModel.updateCardElement(pageId: page.id, element: updated) }
    }

    private func beginInlineEditing(_ element: CardElement) {
        guard element.kind == .text else { return }
        editingElementID = element.id
        inlineOriginal = element.text?.text ?? ""
        inlineDraft = inlineOriginal
        DispatchQueue.main.async {
            inlineEditorFocused = true
        }
    }

    private func commitInlineEditing() {
        guard let editingElementID,
              let element = page.elements.first(where: { $0.id == editingElementID }) else {
            return
        }
        let committedText = inlineDraft
        self.editingElementID = nil
        inlineEditorFocused = false
        inlineOriginal = ""
        guard committedText != element.text?.text else { return }

        var updated = element
        var content = element.text ?? TextClipContent(text: "")
        content.text = committedText
        updated.text = content
        Task { await viewModel.updateCardElement(pageId: page.id, element: updated) }
    }

    private func cancelInlineEditing() {
        guard editingElementID != nil else { return }
        inlineDraft = inlineOriginal
        editingElementID = nil
        inlineEditorFocused = false
        inlineOriginal = ""
    }

    private func chooseReplacementImage(for element: CardElement) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image for the selected card element."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await viewModel.replaceCardElementImage(
                pageId: page.id,
                elementId: element.id,
                with: url
            )
        }
    }

    private func reconcileSelection() {
        if let selectedElementID, page.elements.contains(where: { $0.id == selectedElementID }) {
            return
        }
        selectedElementID = page.elements.first?.id
    }

    private func displayFrame(for element: CardElement) -> NormalizedRect {
        if let resizeDraft, resizeDraft.elementID == element.id {
            return resizeDraft.frame
        }
        if let moveDraft, moveDraft.elementID == element.id {
            return moveDraft.frame
        }
        return element.normalizedFrame
    }

    private func fittedCanvasSize(in available: CGSize) -> CGSize {
        let ratio = CardLayout.aspectRatio(for: format)
        let availableRatio = available.width / max(available.height, 1)
        if availableRatio > ratio {
            return CGSize(width: available.height * ratio, height: available.height)
        }
        return CGSize(width: available.width, height: available.width / ratio)
    }

    private func image(for element: CardElement) -> NSImage? {
        guard let mediaAssetID = element.mediaAssetID,
              let asset = viewModel.currentProject.mediaLibrary.assets[mediaAssetID] else {
            return nil
        }
        if let thumbnailData = asset.thumbnailData, let image = NSImage(data: thumbnailData) {
            return image
        }
        return NSImage(contentsOf: asset.originalURL)
    }

    private func elementAccessibilityLabel(_ element: CardElement) -> String {
        switch element.kind {
        case .text:
            "Text element, \(element.text?.text ?? "empty")"
        case .image:
            "Image element"
        case .logo:
            "Logo element"
        }
    }

    private func frameStatus(_ frame: NormalizedRect) -> String {
        String(
            format: "x %.3f · y %.3f · w %.3f · h %.3f",
            frame.x,
            frame.y,
            frame.width,
            frame.height
        )
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
