import CoreGraphics
import Testing
@testable import MovieCutCore

@Suite("Card normalized layout")
struct CardLayoutTests {
    @Test("Normalized pixel round trip stays within one thousandth in every format", arguments: [
        CardFormat.square,
        CardFormat.portrait,
        CardFormat.story
    ])
    func normalizedPixelRoundTrip(format: CardFormat) throws {
        let original = try #require(NormalizedRect(x: 0.137, y: 0.219, width: 0.623, height: 0.347))
        let size = CardLayout.pixelSize(for: format)
        let pixels = CardLayout.pixelRect(for: original, in: size)
        let roundTrip = try #require(CardLayout.normalizedRect(from: pixels, in: size))

        #expect(maxError(original, roundTrip) <= 0.001)
        #expect(CardLayout.aspectRatio(for: format) == size.width / size.height)
    }

    @Test("Pixel conversion clamps rectangles into the normalized canvas")
    func pixelConversionClamps() throws {
        let size = CGSize(width: 1080, height: 1920)
        let converted = try #require(CardLayout.normalizedRect(
            from: CGRect(x: -108, y: 1728, width: 540, height: 384),
            in: size
        ))

        #expect(converted == NormalizedRect(x: 0, y: 0.8, width: 0.5, height: 0.2))
        #expect(CardLayout.normalizedRect(
            from: CGRect(x: 0, y: 0, width: 0, height: 0),
            in: CGSize(width: 0, height: 0)
        ) == nil)
    }

    @Test("Move clamping preserves element size at every canvas edge")
    func moveClampsAndPreservesSize() throws {
        let original = try #require(NormalizedRect(x: 0.2, y: 0.3, width: 0.4, height: 0.25))
        let leadingTop = CardLayout.moving(original, deltaX: -2, deltaY: -2)
        let trailingBottom = CardLayout.moving(original, deltaX: 2, deltaY: 2)

        #expect(leadingTop == NormalizedRect(x: 0, y: 0, width: 0.4, height: 0.25))
        #expect(trailingBottom == NormalizedRect(x: 0.6, y: 0.75, width: 0.4, height: 0.25))
        #expect(leadingTop.width == original.width)
        #expect(trailingBottom.height == original.height)
    }

    @Test("Resize clamping enforces minimum size and in-bounds maximum")
    func resizeClamps() throws {
        let original = try #require(NormalizedRect(x: 0.7, y: 0.6, width: 0.2, height: 0.3))
        let minimum = CardLayout.resizing(original, deltaWidth: -5, deltaHeight: -5)
        let maximum = CardLayout.resizing(original, deltaWidth: 5, deltaHeight: 5)

        #expect(minimum == NormalizedRect(x: 0.7, y: 0.6, width: 0.04, height: 0.04))
        #expect(maxError(
            maximum,
            NormalizedRect(x: 0.7, y: 0.6, width: 0.3, height: 0.4)!
        ) <= 0.000_001)
    }

    private func maxError(_ lhs: NormalizedRect, _ rhs: NormalizedRect) -> Double {
        [
            abs(lhs.x - rhs.x),
            abs(lhs.y - rhs.y),
            abs(lhs.width - rhs.width),
            abs(lhs.height - rhs.height)
        ].max() ?? .infinity
    }
}
