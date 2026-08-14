import CoreGraphics
import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for the shared clip-transform affine helper.
///
/// These are NOT static-contract tests — they assert real CGAffineTransform
/// values. The historical bug: preview and export each kept a private copy of
/// the affine math, and the two copies had DRIFTED (preview resolved the anchor
/// against the source frame + composed `preferredTransform`; export resolved it
/// against the canvas with an identity base). The shared
/// ``ClipTransform/affineTransform(for:)`` consolidates them. These tests pin
/// both that the two anchors produce DIFFERENT transforms (so the deliberate
/// semantic difference is preserved) and that the same anchor reproduces the
/// prior engines' math byte-for-byte.
@Suite("ClipTransform Affine Helper")
struct ClipTransformAnchorTests {
    private let sourceSize = CGSize(width: 1920, height: 1080)
    private let canvasSize = CGSize(width: 1080, height: 1920)
    private let preferredTransform = CGAffineTransform(rotationAngle: .pi / 2) // 90° source rotation

    private var sampleTransform: ClipTransform {
        ClipTransform(
            position: CGPoint(x: 100, y: 50),
            offset: CGPoint(x: 10, y: 5),
            scale: CGSize(width: 1.5, height: 0.75),
            rotation: 30,
            anchorPoint: CGPoint(x: 0.5, y: 0.5)
        )
    }

    // MARK: - Same anchor reproduces prior engine math

    @Test("sourceFrame anchor reproduces the preview engine's math")
    func sourceFrameAnchorMatchesPreviewMath() {
        // The preview engine's historical computation, transcribed exactly:
        let t = sampleTransform
        let anchorPoint = CGPoint(x: sourceSize.width * t.anchorPoint.x, y: sourceSize.height * t.anchorPoint.y)
        let radians = CGFloat(t.rotation * .pi / 180)
        var expected = preferredTransform
        expected = expected.translatedBy(x: t.position.x + t.offset.x, y: t.position.y + t.offset.y)
        expected = expected.translatedBy(x: anchorPoint.x, y: anchorPoint.y)
        expected = expected.rotated(by: radians)
        expected = expected.scaledBy(x: t.scale.width, y: t.scale.height)
        expected = expected.translatedBy(x: -anchorPoint.x, y: -anchorPoint.y)

        let actual = sampleTransform.affineTransform(
            for: .sourceFrame(preferredTransform: preferredTransform, size: sourceSize)
        )
        // CGAffineTransform is not Equatable in a useful way; compare via the
        // six matrix components.
        expectAffineEqual(actual, expected)
    }

    @Test("canvas anchor reproduces the export engine's math")
    func canvasAnchorMatchesExportMath() {
        let t = sampleTransform
        let anchorPoint = CGPoint(x: canvasSize.width * t.anchorPoint.x, y: canvasSize.height * t.anchorPoint.y)
        let radians = CGFloat(t.rotation * .pi / 180)
        var expected = CGAffineTransform.identity
        expected = expected.translatedBy(x: t.position.x + t.offset.x, y: t.position.y + t.offset.y)
        expected = expected.translatedBy(x: anchorPoint.x, y: anchorPoint.y)
        expected = expected.rotated(by: radians)
        expected = expected.scaledBy(x: t.scale.width, y: t.scale.height)
        expected = expected.translatedBy(x: -anchorPoint.x, y: -anchorPoint.y)

        let actual = sampleTransform.affineTransform(for: .canvas(size: canvasSize))
        expectAffineEqual(actual, expected)
    }

    // MARK: - Different anchors yield different transforms (semantic preserved)

    @Test("sourceFrame and canvas anchors produce different transforms for a non-trivial clip")
    func anchorsDiffer() {
        let sourceFrame = sampleTransform.affineTransform(
            for: .sourceFrame(preferredTransform: preferredTransform, size: sourceSize)
        )
        let canvas = sampleTransform.affineTransform(for: .canvas(size: canvasSize))
        // The two anchors resolve against different sizes AND different bases, so
        // they must NOT be equal — this is the deliberate preview/export
        // semantic difference, now made explicit.
        expectAffineNotEqual(sourceFrame, canvas)
    }

    // MARK: - Identity / determinism

    @Test("identity transform with identity base and zero anchor yields identity")
    func identityTransformYieldsIdentityBase() {
        let identity = ClipTransform()
        let result = identity.affineTransform(
            for: .sourceFrame(preferredTransform: .identity, size: CGSize(width: 100, height: 100))
        )
        expectAffineEqual(result, .identity)
    }

    @Test("the helper is deterministic — repeated calls are equal")
    func helperIsDeterministic() {
        let anchor = ClipTransformAnchor.canvas(size: canvasSize)
        let first = sampleTransform.affineTransform(for: anchor)
        let second = sampleTransform.affineTransform(for: anchor)
        expectAffineEqual(first, second)
    }

    // MARK: - Affine comparison helpers

    private func expectAffineEqual(_ a: CGAffineTransform, _ b: CGAffineTransform) {
        #expect(a.a == b.a && a.b == b.b && a.c == b.c && a.d == b.d && a.tx == b.tx && a.ty == b.ty,
                "affine mismatch:\n actual \(affineString(a))\n expected \(affineString(b))")
    }

    private func expectAffineNotEqual(_ a: CGAffineTransform, _ b: CGAffineTransform) {
        #expect(!(a.a == b.a && a.b == b.b && a.c == b.c && a.d == b.d && a.tx == b.tx && a.ty == b.ty),
                "affine transforms were unexpectedly equal (both \(affineString(a))); the two anchors must produce different output.")
    }

    private func affineString(_ t: CGAffineTransform) -> String {
        String(format: "[%.4f %.4f %.4f %.4f %.4f %.4f]", t.a, t.b, t.c, t.d, t.tx, t.ty)
    }
}
