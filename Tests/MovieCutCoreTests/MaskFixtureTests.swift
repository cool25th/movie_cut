import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

/// MC-MASK-FIX fixture manifest: Mask model, Codable round-trip, SetClipMaskCommand apply/undo
/// 이서 데이터 관점: 마스크 데이터가 model → JSON → command → undo chain을 통해 무결성을 유지하는지 검증.
@Suite("MC-MASK-FIX Fixture Manifest")
struct MaskFixtureTests {

    // MARK: - MC-MASK-FIX-01: Rectangle Normal

    @Test("MC-MASK-FIX-01: Rectangle normal — Codable round-trip preserves all fields")
    func fix01RectangleCodableRoundTrip() throws {
        let mask = Mask(
            shape: .rectangle,
            position: CGPoint(x: 0.25, y: 0.25),
            size: CGSize(width: 0.5, height: 0.5),
            rotation: 0,
            feather: 0,
            inverted: false,
            brushPoints: []
        )
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(Mask.self, from: data)

        #expect(decoded.shape == .rectangle)
        #expect(decoded.position.x == 0.25)
        #expect(decoded.position.y == 0.25)
        #expect(decoded.size.width == 0.5)
        #expect(decoded.size.height == 0.5)
        #expect(decoded.rotation == 0)
        #expect(decoded.feather == 0)
        #expect(decoded.inverted == false)
        #expect(decoded.brushPoints.isEmpty)
    }

    @Test("MC-MASK-FIX-01: Rectangle normal — set mask command applies and undoes")
    func fix01RectangleCommandApplyUndo() throws {
        let clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
        var project = Project(name: "FIX-01", timeline: Timeline(tracks: [
            Track(kind: .video, name: "V1", clips: [clip])
        ]))
        let clipId = project.timeline.tracks[0].clips[0].id

        let mask = Mask(
            shape: .rectangle,
            position: CGPoint(x: 0.25, y: 0.25),
            size: CGSize(width: 0.5, height: 0.5),
            rotation: 0,
            feather: 0,
            inverted: false
        )
        let command = SetClipMaskCommand(clipId: clipId, mask: mask)

        // Apply
        try command.apply(to: &project)
        let appliedMask = project.timeline.tracks[0].clips[0].mask
        #expect(appliedMask != nil, "Mask should be set after apply")
        #expect(appliedMask?.shape == .rectangle)
        #expect(appliedMask?.position.x == 0.25)
        #expect(appliedMask?.inverted == false)
    }

    // MARK: - MC-MASK-FIX-02: Ellipse Inverted

    @Test("MC-MASK-FIX-02: Ellipse inverted — Codable round-trip")
    func fix02EllipseInvertedCodable() throws {
        let mask = Mask(
            shape: .ellipse,
            position: CGPoint(x: 0.5, y: 0.5),
            size: CGSize(width: 0.8, height: 0.6),
            rotation: 45,
            feather: 5,
            inverted: true
        )
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(Mask.self, from: data)

        #expect(decoded.shape == .ellipse)
        #expect(decoded.rotation == 45)
        #expect(decoded.feather == 5)
        #expect(decoded.inverted == true)
        #expect(decoded.size.width == 0.8)
        #expect(decoded.size.height == 0.6)
    }

    @Test("MC-MASK-FIX-02: Ellipse inverted — command apply then replace undoes correctly")
    func fix02EllipseCommandReplace() throws {
        let clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 5), timelineRange: TimeRange(start: 0, duration: 5))
        var project = Project(name: "FIX-02", timeline: Timeline(tracks: [
            Track(kind: .video, name: "V1", clips: [clip])
        ]))
        let clipId = project.timeline.tracks[0].clips[0].id

        // First mask: rectangle
        let mask1 = Mask(shape: .rectangle, position: CGPoint(x: 0, y: 0), size: CGSize(width: 1, height: 1))
        let cmd1 = SetClipMaskCommand(clipId: clipId, mask: mask1)
        _ = try cmd1.apply(to: &project)

        // Second mask: ellipse inverted (replaces)
        let mask2 = Mask(shape: .ellipse, position: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 0.5, height: 0.5), inverted: true)
        let cmd2 = SetClipMaskCommand(clipId: clipId, mask: mask2)
        try cmd2.apply(to: &project)

        #expect(project.timeline.tracks[0].clips[0].mask?.shape == .ellipse)
        #expect(project.timeline.tracks[0].clips[0].mask?.inverted == true)
    }

    // MARK: - MC-MASK-FIX-03: All Shapes Enum Coverage

    @Test("MC-MASK-FIX-03: All MaskShape values encode and decode correctly")
    func fix03AllShapesCodable() throws {
        for shape in MaskShape.allCases {
            let mask = Mask(
                shape: shape,
                position: CGPoint(x: 0.1, y: 0.1),
                size: CGSize(width: 0.3, height: 0.3),
                rotation: 15,
                feather: 2,
                inverted: false,
                brushPoints: (shape == .brush ? [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4)] : [])
            )
            let data = try JSONEncoder().encode(mask)
            let decoded = try JSONDecoder().decode(Mask.self, from: data)

            #expect(decoded.shape == shape, "Shape \(shape.rawValue) should round-trip")
            #expect(decoded.rotation == 15, "Shape \(shape.rawValue): rotation preserved")
            #expect(decoded.feather == 2, "Shape \(shape.rawValue): feather preserved")
            if shape == .brush {
                #expect(decoded.brushPoints.count == 2)
            } else {
                #expect(decoded.brushPoints.isEmpty)
            }
        }
    }

    // MARK: - Data Edge Cases

    @Test("Mask with zero size is valid data — renderer handles it")
    func zeroSizeMaskCodable() throws {
        let mask = Mask(shape: .rectangle, position: CGPoint(x: 0, y: 0), size: CGSize(width: 0, height: 0))
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(Mask.self, from: data)
        #expect(decoded.size.width == 0)
        #expect(decoded.size.height == 0)
    }

    @Test("Mask with negative position is preserved as-is")
    func negativePositionMask() throws {
        let mask = Mask(shape: .rectangle, position: CGPoint(x: -0.1, y: -0.1), size: CGSize(width: 0.5, height: 0.5))
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(Mask.self, from: data)
        #expect(decoded.position.x == -0.1, "Negative position stored as-is")
        #expect(decoded.position.y == -0.1)
    }

    @Test("Mask Equatable compares all fields")
    func maskEquality() {
        let a = Mask(shape: .rectangle, position: CGPoint(x: 0, y: 0), size: CGSize(width: 1, height: 1), rotation: 0, feather: 0, inverted: false)
        let b = Mask(shape: .rectangle, position: CGPoint(x: 0, y: 0), size: CGSize(width: 1, height: 1), rotation: 0, feather: 0, inverted: false)
        let c = Mask(shape: .rectangle, position: CGPoint(x: 0, y: 0), size: CGSize(width: 1, height: 1), rotation: 0, feather: 0, inverted: true)

        #expect(a == b, "Identical masks should be equal")
        #expect(a != c, "Different inverted flag should make masks unequal")
    }

    @Test("Mask with large rotation value is preserved")
    func largeRotationMask() throws {
        let mask = Mask(shape: .triangle, position: CGPoint(x: 0, y: 0), size: CGSize(width: 0.5, height: 0.5), rotation: 720.5)
        let data = try JSONEncoder().encode(mask)
        let decoded = try JSONDecoder().decode(Mask.self, from: data)
        #expect(decoded.rotation == 720.5)
    }
}
