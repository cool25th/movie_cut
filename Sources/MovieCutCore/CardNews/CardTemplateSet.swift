import Foundation

/// One reusable page definition within a card template set.
public struct CardTemplatePage: Codable, Sendable, Equatable, Identifiable {
    /// Stable manifest identity. Resolved documents receive fresh UUIDs instead.
    public var id: String

    /// Semantic role used when assembling the five-page draft.
    public var role: CardPageRole

    /// Filled template slots. Their UUIDs identify manifest slots only and are
    /// replaced with fresh deterministic UUIDs during resolution.
    public var elements: [CardElement]

    /// Optional page-local style that takes priority over all inherited styles.
    public var masterOverride: CardMasterStyle?

    public init(
        id: String,
        role: CardPageRole,
        elements: [CardElement],
        masterOverride: CardMasterStyle? = nil
    ) {
        self.id = id
        self.role = role
        self.elements = elements
        self.masterOverride = masterOverride
    }
}

/// A coherent multi-page card-news template.
public struct CardTemplateSet: Codable, Sendable, Equatable, Identifiable {
    /// Stable manifest identifier.
    public var id: String

    /// User-visible template name.
    public var name: String

    /// Page definitions containing cover, body, emphasis, and closing roles.
    public var pages: [CardTemplatePage]

    /// Style used when the target document has no explicit master style.
    public var defaultMasterStyle: CardMasterStyle

    public init(
        id: String,
        name: String,
        pages: [CardTemplatePage],
        defaultMasterStyle: CardMasterStyle
    ) {
        self.id = id
        self.name = name
        self.pages = pages
        self.defaultMasterStyle = defaultMasterStyle
    }
}

/// Fail-closed template validation errors shared by the resolver and commands.
public enum CardTemplateError: Error, LocalizedError, Sendable, Equatable {
    case emptyIdentifier
    case emptyName
    case emptyPages
    case emptyPage(String)
    case missingRole(CardPageRole)
    case duplicatePageIdentifier(String)
    case duplicateElementIdentifier(UUID)
    case emptyRequiredSlot(UUID)
    case invalidMasterStyle
    case duplicateResolvedPageIdentifier(UUID)
    case duplicateResolvedElementIdentifier(UUID)

    public var errorDescription: String? {
        switch self {
        case .emptyIdentifier:
            "Card template identifiers cannot be empty."
        case .emptyName:
            "Card template names cannot be empty."
        case .emptyPages:
            "Card templates must contain pages."
        case .emptyPage(let id):
            "Card template page \(id) cannot be empty."
        case .missingRole(let role):
            "Card template is missing the \(role.rawValue) role."
        case .duplicatePageIdentifier(let id):
            "Card template page identifier is duplicated: \(id)."
        case .duplicateElementIdentifier(let id):
            "Card template element identifier is duplicated: \(id)."
        case .emptyRequiredSlot(let id):
            "Card template required slot is empty: \(id)."
        case .invalidMasterStyle:
            "Card master style values are invalid."
        case .duplicateResolvedPageIdentifier(let id):
            "Resolved card page identifier is duplicated: \(id)."
        case .duplicateResolvedElementIdentifier(let id):
            "Resolved card element identifier is duplicated: \(id)."
        }
    }
}

/// Deterministically turns template definitions into editable card documents.
public enum CardTemplateResolver {
    /// Instantiates exactly five pages using deterministic fresh document, page,
    /// and element UUIDs derived from the supplied seed.
    public static func instantiate(
        _ template: CardTemplateSet,
        title: String? = nil,
        format: CardFormat = .square,
        documentID: UUID? = nil,
        documentMasterStyle: CardMasterStyle? = nil,
        seed: UInt64
    ) throws -> CardDocument {
        try validate(template)
        let masterStyle = documentMasterStyle ?? template.defaultMasterStyle
        try validate(masterStyle)
        let pageDefinitions = try fivePageDefinitions(from: template)
        var sequence = 0

        func nextID() -> UUID {
            defer { sequence += 1 }
            return deterministicUUID(seed: seed, namespace: template.id, index: sequence)
        }

        let resolvedDocumentID = documentID ?? nextID()
        let pages = pageDefinitions.map { definition in
            let effectiveStyle = effectiveMasterStyle(
                pageOverride: definition.masterOverride,
                documentMasterStyle: masterStyle,
                templateDefaultMasterStyle: template.defaultMasterStyle
            )
            return CardPage(
                id: nextID(),
                role: definition.role,
                elements: definition.elements.map { slot in
                    var element = slot
                    element.id = nextID()
                    return applying(effectiveStyle, to: element)
                },
                masterOverride: definition.masterOverride
            )
        }

        let document = CardDocument(
            id: resolvedDocumentID,
            title: title ?? template.name,
            format: format,
            pages: pages,
            masterStyle: masterStyle
        )
        try validateResolvedDocument(document)
        return document
    }

    /// Resolves style priority for one page: page override, then document
    /// master, then the template default.
    public static func effectiveMasterStyle(
        pageOverride: CardMasterStyle?,
        documentMasterStyle: CardMasterStyle?,
        templateDefaultMasterStyle: CardMasterStyle
    ) -> CardMasterStyle {
        pageOverride ?? documentMasterStyle ?? templateDefaultMasterStyle
    }

    /// Applies inherited style values to the element kinds that consume them.
    public static func applying(_ style: CardMasterStyle, to element: CardElement) -> CardElement {
        var resolved = element
        switch resolved.kind {
        case .text:
            if var text = resolved.text {
                text.fontFamily = style.fontFamily
                text.fontColor = style.primaryColorHex
                resolved.text = text
            }
        case .logo:
            if let logoPlacement = style.logoPlacement {
                resolved.normalizedFrame = logoPlacement
            }
        case .image:
            break
        }
        return resolved
    }

    /// Re-resolves inherited elements in an existing document while preserving
    /// page overrides and every stable page/element identifier.
    public static func applyingMasterStyle(
        _ masterStyle: CardMasterStyle,
        to document: CardDocument
    ) throws -> CardDocument {
        try validate(masterStyle)
        var resolved = document
        resolved.masterStyle = masterStyle
        resolved.pages = document.pages.map { page in
            var resolvedPage = page
            let effectiveStyle = page.masterOverride ?? masterStyle
            resolvedPage.elements = page.elements.map { applying(effectiveStyle, to: $0) }
            return resolvedPage
        }
        try validateResolvedDocument(resolved)
        return resolved
    }

    /// Returns the number of text/image/logo slots whose required payload is
    /// empty. This is also used by the actual-app E2E dump.
    public static func emptyRequiredSlotCount(in pages: [CardPage]) -> Int {
        pages.flatMap(\.elements).reduce(into: 0) { count, element in
            if isRequiredSlotEmpty(element) { count += 1 }
        }
    }

    /// Validates the template manifest before any project mutation occurs.
    public static func validate(_ template: CardTemplateSet) throws {
        guard !template.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CardTemplateError.emptyIdentifier
        }
        guard !template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CardTemplateError.emptyName
        }
        guard !template.pages.isEmpty else { throw CardTemplateError.emptyPages }
        try validate(template.defaultMasterStyle)

        var pageIDs = Set<String>()
        var elementIDs = Set<UUID>()
        for page in template.pages {
            guard pageIDs.insert(page.id).inserted else {
                throw CardTemplateError.duplicatePageIdentifier(page.id)
            }
            guard !page.elements.isEmpty else { throw CardTemplateError.emptyPage(page.id) }
            if let override = page.masterOverride { try validate(override) }
            for element in page.elements {
                guard elementIDs.insert(element.id).inserted else {
                    throw CardTemplateError.duplicateElementIdentifier(element.id)
                }
                guard !isRequiredSlotEmpty(element) else {
                    throw CardTemplateError.emptyRequiredSlot(element.id)
                }
            }
        }
        for role in [CardPageRole.cover, .body, .emphasis, .closing]
        where !template.pages.contains(where: { $0.role == role }) {
            throw CardTemplateError.missingRole(role)
        }
    }

    /// Validates values accepted by master-style commands.
    public static func validate(_ style: CardMasterStyle) throws {
        guard !style.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              isHexColor(style.primaryColorHex),
              isHexColor(style.secondaryColorHex) else {
            throw CardTemplateError.invalidMasterStyle
        }
    }

    /// Validates identifier uniqueness in an existing or newly resolved card
    /// document before it is committed through EditorSession.
    public static func validateResolvedDocument(_ document: CardDocument) throws {
        var pageIDs = Set<UUID>()
        var elementIDs = Set<UUID>()
        for page in document.pages {
            guard pageIDs.insert(page.id).inserted else {
                throw CardTemplateError.duplicateResolvedPageIdentifier(page.id)
            }
            for element in page.elements {
                guard elementIDs.insert(element.id).inserted else {
                    throw CardTemplateError.duplicateResolvedElementIdentifier(element.id)
                }
            }
        }
    }

    private static func fivePageDefinitions(from template: CardTemplateSet) throws -> [CardTemplatePage] {
        let covers = template.pages.filter { $0.role == .cover }
        let bodies = template.pages.filter { $0.role == .body }
        let emphasis = template.pages.filter { $0.role == .emphasis }
        let closings = template.pages.filter { $0.role == .closing }
        guard let cover = covers.first else { throw CardTemplateError.missingRole(.cover) }
        guard let body = bodies.first else { throw CardTemplateError.missingRole(.body) }
        guard let emphasized = emphasis.first else { throw CardTemplateError.missingRole(.emphasis) }
        guard let closing = closings.first else { throw CardTemplateError.missingRole(.closing) }

        if bodies.count >= 2 {
            return [cover, bodies[0], bodies[1], emphasized, closing]
        }
        if emphasis.count >= 2 {
            return [cover, body, emphasis[0], emphasis[1], closing]
        }
        return [cover, body, body, emphasized, closing]
    }

    private static func isRequiredSlotEmpty(_ element: CardElement) -> Bool {
        switch element.kind {
        case .text:
            guard let text = element.text else { return true }
            return text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image, .logo:
            return element.mediaAssetID == nil
        }
    }

    private static func isHexColor(_ value: String) -> Bool {
        guard value.first == "#" else { return false }
        let digits = value.dropFirst()
        guard digits.count == 6 || digits.count == 8 else { return false }
        return digits.allSatisfy { $0.isHexDigit }
    }

    private static func deterministicUUID(seed: UInt64, namespace: String, index: Int) -> UUID {
        let namespaceHash = namespace.utf8.reduce(UInt64(0xcbf29ce484222325)) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x100000001b3
        }
        let base = seed ^ namespaceHash ^ (UInt64(index) &* 0x9e3779b97f4a7c15)
        var first = splitMix64(base)
        var second = splitMix64(first ^ 0xd6e8feb86659fd93)
        var bytes = withUnsafeBytes(of: &first) { Array($0) }
            + withUnsafeBytes(of: &second) { Array($0) }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func splitMix64(_ value: UInt64) -> UInt64 {
        var value = value &+ 0x9e3779b97f4a7c15
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}
