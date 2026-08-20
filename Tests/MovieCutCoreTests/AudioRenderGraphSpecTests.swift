import CoreMedia
import Foundation
import Testing
@testable import MovieCutCore

/// G-25 Inc 7 — AudioRenderGraphSpec pure-model tests (spec §2 schema, §3
/// timebase, §5 node kinds). Renderless by design; engines are Inc 8.
@Suite("AudioRenderGraphSpec (G-25 Inc 7)")
struct AudioRenderGraphSpecTests {
    // MARK: - Schema (§2)

    @Test("full graph round-trips through Codable")
    func fullGraphRoundTrip() throws {
        let sourceId = UUID()
        let stripId = UUID()
        let trackId = UUID()
        let spec = AudioRenderGraphSpec(
            version: 1,
            sources: [
                AudioGraphSource(
                    id: sourceId,
                    kind: .derived,
                    url: URL(filePath: "/tmp/stem.wav"),
                    derivedFrom: UUID(),
                    algorithmVersion: "1.0.0",
                    nativeSampleRate: 44_100
                )
            ],
            clipStrips: [
                AudioGraphClipStrip(
                    clipId: stripId,
                    sourceId: sourceId,
                    channelMapping: .dualMono,
                    gain: [AudioGraphAutomationPoint(samplePosition: 0, value: -3)],
                    fades: [AudioGraphFade(startSample: 0, endSample: 9_600, curve: .exponential)],
                    pan: [AudioGraphAutomationPoint(samplePosition: 48_000, value: -0.25)],
                    disabledNodeKinds: [.pan]
                )
            ],
            trackBuses: [
                AudioGraphTrackBus(
                    trackId: trackId,
                    inputStripIds: [stripId],
                    fader: [AudioGraphAutomationPoint(samplePosition: 96_000, value: -1.5)],
                    mute: false,
                    solo: true,
                    ducking: AudioGraphDucking(levelDb: -12)
                )
            ],
            masterBus: AudioGraphMasterBus(
                fader: [AudioGraphAutomationPoint(samplePosition: 0, value: 0)],
                limiter: AudioGraphNodeLatency(
                    nodeKind: .limiter,
                    algorithmVersion: "0.9.0",
                    reportedLatencySamples: 5,
                    lookAheadSamples: 64
                ),
                targetLoudness: -14
            ),
            timebase: AudioGraphTimebase(sampleRate: 48_000, origin: CMTime(value: 3, timescale: 600)),
            rendering: AudioGraphRenderRules(declaredLatencies: [
                AudioGraphNodeLatency(nodeKind: .limiter, algorithmVersion: "0.9.0", reportedLatencySamples: 5, lookAheadSamples: 64)
            ])
        )

        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(AudioRenderGraphSpec.self, from: data)
        #expect(decoded == spec)
    }

    @Test("empty graph encodes to canonical, byte-stable JSON")
    func emptyGraphBytesAreStable() throws {
        let empty = AudioRenderGraphSpec()
        #expect(empty.version == 1)
        #expect(empty.sources.isEmpty)
        #expect(empty.clipStrips.isEmpty)
        #expect(empty.trackBuses.isEmpty)

        // Byte stability is a property of the model under the canonical
        // encoder settings the project store uses (ProjectStore:
        // [.prettyPrinted, .sortedKeys] — JSONEncoder's default key order is
        // nondeterministic across encoder instances).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let first = try encoder.encode(empty)
        let second = try encoder.encode(empty)
        #expect(first == second)

        // Optional node data must be OMITTED, not null/empty-keyed (§2).
        let json = String(decoding: first, as: UTF8.self)
        #expect(!json.contains("derivedFrom"))
        #expect(!json.contains("algorithmVersion"))
        #expect(!json.contains("nativeSampleRate"))
        #expect(!json.contains("disabledNodeKinds"))
        #expect(!json.contains("ducking"))
        #expect(!json.contains("limiter"))
        #expect(!json.contains("targetLoudness"))
        #expect(!json.contains("declaredLatencies"))

        let decoded = try JSONDecoder().decode(AudioRenderGraphSpec.self, from: first)
        #expect(decoded == empty)
    }

    @Test("schema version starts at 1")
    func versionStartsAtOne() {
        #expect(AudioRenderGraphSpec().version == 1)
    }

    // MARK: - Sample timebase (§3)

    @Test("automation and fade time coordinates are Int64 sample positions")
    func automationUsesSamplePositions() {
        // 60 minutes at 48 kHz exercises values well past 32-bit — the drift
        // gate (§9.4) depends on these staying exact integers.
        let oneHour = Int64(60 * 60 * 48_000)
        let point = AudioGraphAutomationPoint(samplePosition: oneHour, value: -6)
        #expect(point.samplePosition == 172_800_000)
        let fade = AudioGraphFade(startSample: oneHour - 480, endSample: oneHour)
        #expect(fade.endSample - fade.startSample == 480)
    }

    @Test("timebase origin serializes as an exact num/den rational string")
    func timebaseOriginRationalRoundTrip() throws {
        let origin = CMTime(value: 7, timescale: 600)
        let encoded = AudioGraphTimebase.encodeOrigin(origin)
        #expect(encoded == "7/600")

        let decoded = try AudioGraphTimebase.decodeOrigin(encoded)
        #expect(decoded.value == 7)
        #expect(decoded.timescale == 600)

        let timebase = AudioGraphTimebase(sampleRate: 48_000, origin: origin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(timebase)
        let roundTrip = try JSONDecoder().decode(AudioGraphTimebase.self, from: data)
        #expect(roundTrip == timebase)
        #expect(String(decoding: data, as: UTF8.self).contains("\"origin\":\"7/600\""))
    }

    @Test("malformed or non-positive-denominator origins fail to decode")
    func timebaseRejectsMalformedOrigins() {
        #expect(throws: DecodingError.self) {
            _ = try AudioGraphTimebase.decodeOrigin("not-a-rational")
        }
        #expect(throws: DecodingError.self) {
            _ = try AudioGraphTimebase.decodeOrigin("7/0")
        }
        #expect(throws: DecodingError.self) {
            _ = try AudioGraphTimebase.decodeOrigin("7/-600")
        }
        #expect(throws: DecodingError.self) {
            _ = try AudioGraphTimebase.decodeOrigin("7/600/extra")
        }
    }

    @Test("negative numerators stay exact (pre-origin media)")
    func timebaseAllowsNegativeNumerator() throws {
        let decoded = try AudioGraphTimebase.decodeOrigin("-3/1000")
        #expect(decoded.value == -3)
        #expect(decoded.timescale == 1000)
    }

    // MARK: - Node kinds (§5)

    @Test("stage-1 supported node kinds are exactly the spec set")
    func stage1SupportMatchesSpec() {
        let supported = AudioGraphNodeKind.allCases.filter(\.isStage1Supported)
        #expect(supported == [
            .channelMapping, .gainFade, .pan, .summing, .ducking, .fader, .meter, .encoder,
            .compressor, .limiter
        ])
        let placeholders = AudioGraphNodeKind.allCases.filter { !$0.isStage1Supported }
        #expect(placeholders == [
            .noiseReduction, .mlStem, .eq, .creativeFX, .masterEQ
        ])
    }

    @Test("every node kind round-trips through its raw value")
    func nodeKindsRoundTrip() throws {
        for kind in AudioGraphNodeKind.allCases {
            let decoded = try JSONDecoder().decode(
                AudioGraphNodeKind.self,
                from: JSONEncoder().encode(kind)
            )
            #expect(decoded == kind)
        }
    }

    // MARK: - Channel mapping

    @Test("channel mapping covers mono, stereo, and dual-mono")
    func channelMappings() throws {
        for mapping in [AudioGraphChannelMapping.mono, .stereo, .dualMono] {
            let decoded = try JSONDecoder().decode(
                AudioGraphChannelMapping.self,
                from: JSONEncoder().encode(mapping)
            )
            #expect(decoded == mapping)
        }
    }
}
