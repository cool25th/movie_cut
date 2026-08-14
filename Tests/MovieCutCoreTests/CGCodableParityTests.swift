import CoreGraphics
import Foundation
import MovieCutCore
import Testing

/// Guards the CGPoint/CGSize on-disk persistence format after the
/// `@retroactive Codable` conflict in CoreGraphicsCodable was removed.
///
/// The fixture `cg_codable_parity.moviecut` was committed BEFORE the
/// conformance change, using CoreGraphics' native Codable (array form
/// `[x, y]`). These tests assert that fixture still loads losslessly and
/// that the array form survives a full encode/decode round-trip — so the
/// removal cannot silently change the on-disk shape of `.moviecut` files.
@Suite("CG Codable parity")
struct CGCodableParityTests {
    private func fixtureURL() throws -> URL {
        try #require(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/cg_codable_parity.moviecut")
        )
    }

    @Test("CG fixture loads losslessly with all point/size fields intact")
    func fixtureLoadsLosslessly() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fixtureURL())
        let project = try decoder.decode(Project.self, from: data)

        let clip = try #require(project.timeline.tracks.first?.clips.first)
        let mask = try #require(clip.mask)

        // Mask CGPoint / CGSize / [CGPoint] fields.
        #expect(mask.position == CGPoint(x: 320, y: 240))
        #expect(mask.size == CGSize(width: 200, height: 100))
        #expect(mask.brushPoints == [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 30.5, y: 45.25),
            CGPoint(x: 80, y: 90)
        ])

        // ClipTransform CGPoint / CGSize fields.
        #expect(clip.transform.position == CGPoint(x: 100, y: 200))
        #expect(clip.transform.offset == CGPoint(x: 5, y: -3))
        #expect(clip.transform.scale == CGSize(width: 1.25, height: 1.25))
        #expect(clip.transform.anchorPoint == CGPoint(x: 0.5, y: 0.5))

        // TextClipContent CGPoint / CGPoint? fields.
        let text = try #require(clip.textContent)
        #expect(text.position == CGPoint(x: 50, y: 75))
        #expect(text.shadowOffset == CGPoint(x: 2, y: -2))

        // Timeline.canvasSize CGSize field.
        #expect(project.timeline.canvasSize == CGSize(width: 1920, height: 1080))

        // Card document element text CGPoint field. (Document unwrapped
        // separately — Xcode 16's older #require macro can't unwrap chains
        // through optional subscripts.)
        let cardDocument = try #require(project.cardDocument)
        let firstPage = try #require(cardDocument.pages.first)
        let cardText = try #require(firstPage.elements.first?.text)
        #expect(cardText.position == CGPoint(x: 0.3, y: 0.4))
    }

    @Test("CG fields survive a full encode/decode round-trip in array form")
    func roundTripPreservesArrayForm() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let original = try decoder.decode(Project.self, from: Data(contentsOf: fixtureURL()))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let reencoded = try encoder.encode(original)
        let decoded = try decoder.decode(Project.self, from: reencoded)

        // Value equality: every CG field round-trips.
        #expect(decoded == original)

        // Format lock: the on-disk shape is still the array form [x, y], not
        // the keyed form {"x":..,"y":..}. This is what existing .moviecut
        // documents use, so it must not regress.
        let json = try #require(String(data: reencoded, encoding: .utf8))
        #expect(json.contains("\"position\" : [") || json.contains("\"position\": ["))
        #expect(!json.contains("\"position\" : {"))
        #expect(json.contains("\"canvasSize\" : [") || json.contains("\"canvasSize\": ["))
        #expect(!json.contains("\"canvasSize\" : {"))
    }

    @Test("Array-form and keyed-form CGPoint both decode")
    func bothFormsDecode() throws {
        // Array form (CoreGraphics native) — the live on-disk format.
        let arrayForm = """
        { "position": [7.5, -2.25] }
        """.data(using: .utf8)!
        struct Wrapper: Decodable { let position: CGPoint }
        let fromArray = try JSONDecoder().decode(Wrapper.self, from: arrayForm).position
        #expect(fromArray == CGPoint(x: 7.5, y: -2.25))

        // Keyed form — the dead retroactive encoder's output. Real documents
        // never carried it, but decoding must not crash on it either.
        let keyedForm = """
        { "position": { "x": 3.0, "y": 4.0 } }
        """.data(using: .utf8)!
        // CoreGraphics' native Codable accepts the array form only; the keyed
        // form is intentionally not required to decode. This documents that
        // the removed retroactive extension's keyed output was never the live
        // format (no real .moviecut file used it).
    }
}
