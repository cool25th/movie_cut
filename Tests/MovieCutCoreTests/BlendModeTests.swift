import Foundation
import MovieCutCore
import Testing

/// Coverage for the `Clip.blendMode` field (Requirement 4.4). The key
/// invariant: a project saved before the field existed must still decode, and
/// every clip must resolve to `.normal`, so multi-track layering is unchanged
/// for legacy projects. These are behavior tests (decode + value check), not
/// StaticContract string checks.
@Suite("Clip Blend Mode")
struct ClipBlendModeTests {
    /// A minimal Clip JSON shape that omits `blendMode` entirely, mirroring a
    /// project file written before this feature existed. Must decode without
    /// throwing and resolve the field to the default.
    ///
    /// CGPoint / CGSize use CoreGraphics' native Codable, which serializes the
    /// *array* form (`[x, y]`), not a keyed object — see
    /// `Sources/MovieCutCore/Models/CoreGraphicsCodable.swift`. The transform
    /// below is written in that on-disk array form on purpose.
    private static let legacyClipJSON: Data = {
        """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "kind": "video",
          "sourceRange": { "start": 0, "duration": 2 },
          "timelineRange": { "start": 0, "duration": 2 },
          "transform": {
            "position": [0, 0],
            "offset": [0, 0],
            "scale": [1, 1],
            "rotation": 0,
            "anchorPoint": [0.5, 0.5]
          },
          "opacity": 1,
          "volume": 1
        }
        """.data(using: .utf8)!
    }()

    @Test("a clip without blendMode decodes to .normal")
    func clipWithoutBlendModeDecodesToNormal() throws {
        let clip = try JSONDecoder().decode(Clip.self, from: Self.legacyClipJSON)
        #expect(clip.blendMode == .normal)
    }

    @Test("a clip with an explicit blend mode round-trips")
    func explicitBlendModeRoundTrips() throws {
        var clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        clip.blendMode = .screen

        let encoded = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(Clip.self, from: encoded)
        #expect(decoded.blendMode == .screen)
    }

    @Test("a .normal clip omits the blendMode key from its JSON")
    func normalClipOmitsBlendModeKey() throws {
        // Requirement 4.4: encode only when not the default, so a .normal clip
        // stays byte-identical to its pre-feature JSON.
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        #expect(clip.blendMode == .normal)

        let encoded = try JSONEncoder().encode(clip)
        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Clip did not encode to a JSON object")
            return
        }
        #expect(object["blendMode"] == nil, "default .normal must not be written to JSON")
    }

    @Test("a non-default clip writes the blendMode raw value")
    func nonDefaultClipWritesBlendModeRawValue() throws {
        var clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        clip.blendMode = .multiply

        let encoded = try JSONEncoder().encode(clip)
        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Clip did not encode to a JSON object")
            return
        }
        #expect(object["blendMode"] as? String == "multiply")
    }

    @Test("stripping blendMode from a current project still decodes to .normal")
    func strippingBlendModeFromCurrentProjectDecodesToNormal() throws {
        // Belt-and-suspenders: encode a full current project, then remove the
        // blendMode key from every clip and confirm they all fall back to
        // .normal. Mirrors the legacy-decode pattern in PlaybackSettingsTests.
        var project = Project(name: "Blend legacy")
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        project.timeline.tracks.append(Track(kind: .video, name: "Video", clips: [clip]))

        var encoded = try JSONEncoder().encode(project)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              var timeline = object["timeline"] as? [String: Any],
              var tracks = timeline["tracks"] as? [[String: Any]] else {
            Issue.record("Project did not encode to the expected shape")
            return
        }
        for index in tracks.indices {
            var track = tracks[index]
            if var clips = track["clips"] as? [[String: Any]] {
                for clipIndex in clips.indices {
                    clips[clipIndex].removeValue(forKey: "blendMode")
                }
                track["clips"] = clips
            }
            tracks[index] = track
        }
        timeline["tracks"] = tracks
        object["timeline"] = timeline
        encoded = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Project.self, from: encoded)
        let decodedClips = decoded.timeline.tracks.flatMap(\.clips)
        #expect(decodedClips.allSatisfy { $0.blendMode == .normal })
    }
}
