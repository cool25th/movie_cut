import Foundation
import MovieCutCore
import Testing

@Suite("Audio Equalizer DSP")
struct AudioEqualizerDSPTests {
    @Test("five-band EQ uses the CapCut-style timeline frequencies")
    func fiveBandFrequencies() {
        #expect(EqualizerPreset.bandFrequencies == [60, 250, 1_000, 4_000, 12_000])
        #expect(EqualizerPreset.flat.bands.map(\.frequency) == EqualizerPreset.bandFrequencies)
        #expect(EqualizerPreset.voiceEnhance.bands.map(\.frequency) == EqualizerPreset.bandFrequencies)
    }

    @Test("bass and treble presets remain spectrally distinct")
    func presetsAreSpectrallyDistinct() {
        let bass = EqualizerPreset.bassBoost.bands.map(\.gain)
        let treble = EqualizerPreset.trebleBoost.bands.map(\.gain)

        #expect(bass != treble)
        #expect(bass.first! > treble.first!)
        #expect(bass.last! < treble.last!)
    }

    @Test("clip equalizer settings are optional and round-trip custom gains")
    func clipEqualizerCodableCompatibility() throws {
        let legacyClip = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        let legacyData = try JSONEncoder().encode(legacyClip)
        let legacyJSON = String(decoding: legacyData, as: UTF8.self)
        #expect(!legacyJSON.contains("\"equalizer\""))

        let decodedLegacyClip = try JSONDecoder().decode(Clip.self, from: legacyData)
        #expect(decodedLegacyClip.equalizer == nil)

        let custom = ClipEqualizerSettings.custom(bands: [
            EQBand(frequency: 60, gain: 6),
            EQBand(frequency: 250, gain: 3),
            EQBand(frequency: 1_000, gain: 0),
            EQBand(frequency: 4_000, gain: -2),
            EQBand(frequency: 12_000, gain: -5)
        ])
        let clip = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2),
            equalizer: custom
        )
        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)

        #expect(decoded.equalizer?.preset == .custom)
        #expect(decoded.equalizer?.bands.map(\.frequency) == EqualizerPreset.bandFrequencies)
        #expect(decoded.equalizer?.bands.map(\.gain) == custom.bands.map(\.gain))
    }

    @Test("set clip property applies equalizer metadata")
    func setClipPropertyEqualizerAppliesAndInverts() throws {
        let clip = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        var project = Project(name: "EQ", timeline: Timeline(tracks: [
            Track(kind: .audio, name: "A1", clips: [clip])
        ]))

        let command = SetClipPropertyCommand(
            clipId: clip.id,
            property: .equalizer(.settings(for: .voiceEnhance))
        )
        try command.apply(to: &project)
        #expect(project.timeline.tracks[0].clips[0].equalizer?.preset == .voiceEnhance)
    }

    @Test("preview and export no longer collapse EQ to volume")
    func previewAndExportUseRealDSPContracts() throws {
        let playback = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")
        let export = try source("App/MovieCutMac/Export/ExportEngine.swift")
        let helper = try source("App/MovieCutMac/Audio/ClipEqualizerProcessing.swift")

        #expect(playback.contains("MTAudioProcessingTapCreate"))
        #expect(playback.contains("AVAudioUnitEQ(numberOfBands: 5)"))
        #expect(playback.contains("audioParameters.audioTapProcessor = audioTap"))
        #expect(playback.contains("clip.resolvedEqualizerPreset"))
        #expect(!playback.contains("applyEQBands"))

        #expect(export.contains("AudioEqualizerService().apply"))
        #expect(export.contains("equalizedAudioAsset"))
        #expect(export.contains("temporaryRenderURLs"))
        #expect(export.contains("clip.resolvedEqualizerPreset"))
        #expect(!export.contains("eqVolumeMultiplier"))
        #expect(!export.contains("averageGain"))

        #expect(helper.contains("func resolvedEqualizerPreset"))
        #expect(helper.contains("if let equalizer, !equalizer.isFlat"))
    }

    @Test("inspector exposes preset picker and five band sliders")
    func inspectorExposesFiveBandEQControls() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")

        #expect(shared.contains("case voiceEnhance"))
        #expect(shared.contains("case bassBoost"))
        #expect(shared.contains("case trebleBoost"))
        #expect(shared.contains("case custom"))
        #expect(inspector.contains("Slider(value: Binding("))
        #expect(inspector.contains("in: -12 ... 12"))
        #expect(inspector.contains("60Hz"))
        #expect(inspector.contains("250Hz"))
        #expect(inspector.contains("1kHz"))
        #expect(inspector.contains("4kHz"))
        #expect(inspector.contains("12kHz"))
        #expect(viewModel.contains("SetClipPropertyCommand(clipId: clipId, property: .equalizer"))
        #expect(viewModel.contains("func updateSelectedEQBandGain"))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }
}
