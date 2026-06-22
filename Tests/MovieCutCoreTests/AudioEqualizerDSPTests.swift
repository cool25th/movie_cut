import Foundation
import MovieCutCore
import Testing

/// Phase 0.2 🟡 sweep — evidence that the timeline EQ is a volume approximation,
/// not real per-band equalization.
///
/// Verdict recorded from the sweep (see docs/MOVIECUT_PRO_ROADMAP_20260622.md):
/// - The real `AudioEqualizerService` (5-band `AVAudioUnitEQ`) is **not wired
///   into the app** — `applyRealtime`/`apply` are never called, and invoking the
///   offline render path aborts ("player started when in a disconnected state").
///   So real EQ is unverified, broken, dead code.
/// - The timeline preview (`PlaybackEngine.applyEQBands`) and export
///   (`ExportEngine.eqVolumeMultiplier`) both collapse a 5-band preset to a
///   single average-gain volume scalar on `AVMutableAudioMixInputParameters`.
///
/// This test locks the consequence: the average-gain→volume mapping cannot
/// distinguish spectrally opposite presets, so the timeline EQ discards the
/// actual frequency shaping. Fixing this (real EQ in preview/export via an
/// `MTAudioProcessingTap` or pre-render) is Phase 2A Pro-audio work.
@Suite("Audio Equalizer Gap")
struct AudioEqualizerGapTests {
    /// The exact mapping the export path uses (`ExportEngine.eqVolumeMultiplier`).
    private func averageGainVolumeMultiplier(_ preset: EqualizerPreset) -> Double {
        guard !preset.bands.isEmpty else { return 1 }
        let averageGain = preset.bands.reduce(0.0) { $0 + Double($1.gain) } / Double(preset.bands.count)
        return min(max(pow(10.0, averageGain / 20.0), 0), 2)
    }

    @Test("bass and treble presets are spectrally opposite")
    func presetsAreSpectrallyDistinct() {
        let bass = EqualizerPreset.bassBoost.bands.map(\.gain)
        let treble = EqualizerPreset.trebleBoost.bands.map(\.gain)
        #expect(bass != treble)
        // Bass emphasizes the low bands; treble emphasizes the high bands.
        #expect(bass.first! > treble.first!)
        #expect(bass.last! < treble.last!)
    }

    @Test("the timeline volume approximation cannot distinguish them")
    func volumeApproximationIsLossy() {
        let bassMultiplier = averageGainVolumeMultiplier(.bassBoost)
        let trebleMultiplier = averageGainVolumeMultiplier(.trebleBoost)
        // Equal average gain (2.2 dB) ⇒ identical volume scalar, even though the
        // presets are spectrally opposite. Real EQ would render them differently.
        #expect(abs(bassMultiplier - trebleMultiplier) < 1e-9)
        #expect(EqualizerPreset.bassBoost.bands != EqualizerPreset.trebleBoost.bands)
    }
}
