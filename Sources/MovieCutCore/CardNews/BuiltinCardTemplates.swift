import Foundation

/// The deterministic offline starter library for G-19.
public enum BuiltinCardTemplates {
    /// Ten coherent template sets with stable identifiers and distinct visual
    /// fingerprints. The array order is part of the gallery manifest contract.
    public static let all: [CardTemplateSet] = configurations.enumerated().map { index, configuration in
        makeTemplate(index: index + 1, configuration: configuration)
    }

    private struct Configuration: Sendable {
        var id: String
        var name: String
        var font: String
        var primary: String
        var secondary: String
        var logo: NormalizedRect
        var layoutVariant: Int
    }

    private static let configurations: [Configuration] = [
        Configuration(
            id: "editorial-indigo",
            name: "Editorial Indigo",
            font: "Avenir Next",
            primary: "#243B6B",
            secondary: "#F4D35E",
            logo: rect(0.72, 0.06, 0.2, 0.08),
            layoutVariant: 0
        ),
        Configuration(
            id: "citrus-pop",
            name: "Citrus Pop",
            font: "Futura",
            primary: "#FF6B35",
            secondary: "#F7C948",
            logo: rect(0.08, 0.84, 0.22, 0.09),
            layoutVariant: 1
        ),
        Configuration(
            id: "monochrome-grid",
            name: "Monochrome Grid",
            font: "Helvetica Neue",
            primary: "#151515",
            secondary: "#E8E8E8",
            logo: rect(0.72, 0.84, 0.2, 0.08),
            layoutVariant: 2
        ),
        Configuration(
            id: "forest-journal",
            name: "Forest Journal",
            font: "Georgia",
            primary: "#254441",
            secondary: "#DDA15E",
            logo: rect(0.08, 0.07, 0.18, 0.09),
            layoutVariant: 3
        ),
        Configuration(
            id: "coral-brief",
            name: "Coral Brief",
            font: "Gill Sans",
            primary: "#C8553D",
            secondary: "#F4F1DE",
            logo: rect(0.4, 0.86, 0.2, 0.08),
            layoutVariant: 4
        ),
        Configuration(
            id: "midnight-neon",
            name: "Midnight Neon",
            font: "Menlo",
            primary: "#7B2CBF",
            secondary: "#80FFDB",
            logo: rect(0.72, 0.08, 0.2, 0.08),
            layoutVariant: 1
        ),
        Configuration(
            id: "warm-paper",
            name: "Warm Paper",
            font: "Baskerville",
            primary: "#7F5539",
            secondary: "#EDE0D4",
            logo: rect(0.08, 0.82, 0.22, 0.1),
            layoutVariant: 3
        ),
        Configuration(
            id: "ocean-signal",
            name: "Ocean Signal",
            font: "Trebuchet MS",
            primary: "#0077B6",
            secondary: "#90E0EF",
            logo: rect(0.7, 0.84, 0.22, 0.09),
            layoutVariant: 0
        ),
        Configuration(
            id: "plum-luxe",
            name: "Plum Luxe",
            font: "Didot",
            primary: "#5A189A",
            secondary: "#E0AAFF",
            logo: rect(0.39, 0.06, 0.22, 0.08),
            layoutVariant: 4
        ),
        Configuration(
            id: "cobalt-tech",
            name: "Cobalt Tech",
            font: "SF Mono",
            primary: "#0047AB",
            secondary: "#A8DADC",
            logo: rect(0.08, 0.08, 0.2, 0.08),
            layoutVariant: 2
        )
    ]

    private static func makeTemplate(index: Int, configuration: Configuration) -> CardTemplateSet {
        let frames = layoutFrames(variant: configuration.layoutVariant)
        let logoAssetID = stableUUID(set: index, page: 0, element: 240)
        let imageAssetID = stableUUID(set: index, page: 0, element: 241)
        let master = CardMasterStyle(
            fontFamily: configuration.font,
            primaryColorHex: configuration.primary,
            secondaryColorHex: configuration.secondary,
            logoPlacement: configuration.logo
        )
        let emphasisOverride = CardMasterStyle(
            fontFamily: configuration.font,
            primaryColorHex: configuration.secondary,
            secondaryColorHex: configuration.primary,
            logoPlacement: configuration.logo
        )

        return CardTemplateSet(
            id: configuration.id,
            name: configuration.name,
            pages: [
                CardTemplatePage(
                    id: "\(configuration.id)-cover",
                    role: .cover,
                    elements: [
                        slot(set: index, page: 1, element: 1, kind: .text, frame: frames.coverText, text: "\(configuration.name) headline"),
                        slot(set: index, page: 1, element: 2, kind: .logo, frame: configuration.logo, mediaID: logoAssetID)
                    ]
                ),
                CardTemplatePage(
                    id: "\(configuration.id)-body-one",
                    role: .body,
                    elements: [
                        slot(set: index, page: 2, element: 1, kind: .text, frame: frames.bodyText, text: "First insight"),
                        slot(set: index, page: 2, element: 2, kind: .image, frame: frames.bodyImage, mediaID: imageAssetID)
                    ]
                ),
                CardTemplatePage(
                    id: "\(configuration.id)-body-two",
                    role: .body,
                    elements: [
                        slot(set: index, page: 3, element: 1, kind: .image, frame: frames.detailImage, mediaID: imageAssetID),
                        slot(set: index, page: 3, element: 2, kind: .text, frame: frames.detailText, text: "Supporting detail")
                    ]
                ),
                CardTemplatePage(
                    id: "\(configuration.id)-emphasis",
                    role: .emphasis,
                    elements: [
                        slot(set: index, page: 4, element: 1, kind: .text, frame: frames.emphasisText, text: "Key takeaway")
                    ],
                    masterOverride: emphasisOverride
                ),
                CardTemplatePage(
                    id: "\(configuration.id)-closing",
                    role: .closing,
                    elements: [
                        slot(set: index, page: 5, element: 1, kind: .text, frame: frames.closingText, text: "Continue the story"),
                        slot(set: index, page: 5, element: 2, kind: .logo, frame: configuration.logo, mediaID: logoAssetID)
                    ]
                )
            ],
            defaultMasterStyle: master
        )
    }

    private struct LayoutFrames: Sendable {
        var coverText: NormalizedRect
        var bodyText: NormalizedRect
        var bodyImage: NormalizedRect
        var detailImage: NormalizedRect
        var detailText: NormalizedRect
        var emphasisText: NormalizedRect
        var closingText: NormalizedRect
    }

    private static func layoutFrames(variant: Int) -> LayoutFrames {
        switch variant {
        case 1:
            LayoutFrames(
                coverText: rect(0.08, 0.52, 0.84, 0.26),
                bodyText: rect(0.1, 0.64, 0.8, 0.18),
                bodyImage: rect(0.08, 0.08, 0.84, 0.48),
                detailImage: rect(0.5, 0.12, 0.42, 0.62),
                detailText: rect(0.08, 0.22, 0.34, 0.34),
                emphasisText: rect(0.12, 0.24, 0.76, 0.42),
                closingText: rect(0.1, 0.35, 0.8, 0.24)
            )
        case 2:
            LayoutFrames(
                coverText: rect(0.08, 0.12, 0.6, 0.34),
                bodyText: rect(0.08, 0.1, 0.36, 0.38),
                bodyImage: rect(0.5, 0.1, 0.42, 0.72),
                detailImage: rect(0.08, 0.1, 0.42, 0.72),
                detailText: rect(0.56, 0.18, 0.36, 0.38),
                emphasisText: rect(0.08, 0.3, 0.84, 0.3),
                closingText: rect(0.2, 0.3, 0.6, 0.28)
            )
        case 3:
            LayoutFrames(
                coverText: rect(0.14, 0.18, 0.72, 0.3),
                bodyText: rect(0.14, 0.12, 0.72, 0.18),
                bodyImage: rect(0.14, 0.38, 0.72, 0.46),
                detailImage: rect(0.12, 0.12, 0.76, 0.42),
                detailText: rect(0.14, 0.62, 0.72, 0.18),
                emphasisText: rect(0.18, 0.28, 0.64, 0.36),
                closingText: rect(0.16, 0.32, 0.68, 0.22)
            )
        case 4:
            LayoutFrames(
                coverText: rect(0.08, 0.62, 0.84, 0.22),
                bodyText: rect(0.08, 0.1, 0.84, 0.16),
                bodyImage: rect(0.08, 0.34, 0.84, 0.56),
                detailImage: rect(0.08, 0.08, 0.84, 0.56),
                detailText: rect(0.08, 0.72, 0.84, 0.16),
                emphasisText: rect(0.1, 0.18, 0.8, 0.5),
                closingText: rect(0.1, 0.24, 0.8, 0.3)
            )
        default:
            LayoutFrames(
                coverText: rect(0.1, 0.14, 0.8, 0.3),
                bodyText: rect(0.08, 0.1, 0.84, 0.18),
                bodyImage: rect(0.08, 0.36, 0.84, 0.52),
                detailImage: rect(0.08, 0.1, 0.84, 0.5),
                detailText: rect(0.08, 0.68, 0.84, 0.18),
                emphasisText: rect(0.12, 0.26, 0.76, 0.4),
                closingText: rect(0.12, 0.3, 0.76, 0.24)
            )
        }
    }

    private static func slot(
        set: Int,
        page: Int,
        element: Int,
        kind: CardElementKind,
        frame: NormalizedRect,
        text: String? = nil,
        mediaID: UUID? = nil
    ) -> CardElement {
        CardElement(
            id: stableUUID(set: set, page: page, element: element),
            kind: kind,
            normalizedFrame: frame,
            text: text.map { TextClipContent(text: $0) },
            mediaAssetID: mediaID
        )
    }

    private static func stableUUID(set: Int, page: Int, element: Int) -> UUID {
        UUID(uuid: (
            0xb1, UInt8(set), UInt8(page), UInt8(element),
            0x00, 0x00, 0x40, 0x00,
            0x80, 0x00, 0x00, 0x00,
            0x00, UInt8(set), UInt8(page), UInt8(element)
        ))
    }

    private static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> NormalizedRect {
        NormalizedRect(x: x, y: y, width: width, height: height)!
    }
}
