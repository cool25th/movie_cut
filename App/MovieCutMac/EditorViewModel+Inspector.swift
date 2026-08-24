import AppKit
import AVFoundation
import CoreImage
import Foundation
import MovieCutCore

// Inspector boundary of the EditorViewModel decomposition (roadmap:
// timeline → selection → transport → INSPECTOR → media → effects → audio →
// export). Pure method moves — no behavior change. Stored @Observable state
// stays in the main file (extensions cannot hold stored properties); methods
// that depend on main-file private members stayed put deliberately
// (updateSelectedStickerTransform → isStickerClip, refreshScopes →
// scopeContext/clearScopes).
extension EditorViewModel {
    func updateSelectedTransform(_ transform: ClipTransform) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .transform(transform)))
    }

    func updateSelectedOpacity(_ opacity: Double) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .opacity(opacity)))
    }

    func updateSelectedVolume(_ volume: Double) async {
        guard let selectedClipId else { return }
        await apply(SetVolumeCommand(clipId: selectedClipId, volume: volume))
    }

    func updateSelectedAudioFade(fadeInDuration: TimeInterval? = nil, fadeOutDuration: TimeInterval? = nil) async {
        guard let selectedClipId, let selectedClip else { return }
        await apply(AudioFadeCommand(
            clipId: selectedClipId,
            fadeInDuration: fadeInDuration ?? selectedClip.fadeInDuration,
            fadeOutDuration: fadeOutDuration ?? selectedClip.fadeOutDuration
        ))
    }

    func updateSelectedPlaybackRate(_ rate: Double) async {
        guard let selectedClipId else { return }
        await apply(SetClipSpeedCommand(clipId: selectedClipId, change: .constantRate(rate)))
        playbackEngine.setRate(Float(rate))
    }

    func updateSelectedSpeedRampPoints(_ points: [SpeedRampPoint]) async {
        guard let selectedClipId else { return }
        await apply(SetClipSpeedCommand(clipId: selectedClipId, change: .rampPoints(points)))
    }

    func updateSelectedOpticalFlow(_ enabled: Bool) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .opticalFlow(enabled)))
    }

    func updateSelectedKeyframes(_ keyframes: [Keyframe]) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .keyframes(keyframes)))
    }

    func updateSelectedTransition(_ transition: Transition?) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .transition(transition)))
    }

    func updateSelectedTextContent(_ textContent: TextClipContent?) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .textContent(textContent)))
    }

    func updateSelectedChromaKey(_ chromaKey: ChromaKeySettings?) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .chromaKey(chromaKey)))
    }

    func updateSelectedColorCorrection(_ colorCorrection: ColorCorrection?) async {
        guard let selectedClipId else { return }
        await apply(SetColorCorrectionCommand(clipId: selectedClipId, colorCorrection: colorCorrection))
    }

    /// Sets the 3-way color grade on the selected clip (Phase 2A Pro grading).
    func updateSelectedColorGrade(_ colorGrade: ColorGrade?) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .colorGrade(colorGrade)))
    }

    func autoEnhance() async {
        guard let clipId = selectedClipId else { return }
        try? await autoColorCorrect(for: clipId)
    }

    func autoColorCorrect() async {
        guard let clipId = selectedClipId else { return }
        try? await autoColorCorrect(for: clipId)
    }

    func autoColorCorrect(for clipId: UUID) async throws {
        let snapshot = await session.snapshot()
        var found: Clip?
        outer: for track in snapshot.timeline.tracks {
            for c in track.clips {
                if c.id == clipId { found = c; break outer }
            }
        }
        guard let clip = found else {
            throw EditorCommandError.invalidCommand("Clip not found")
        }
        var colorCorrection = clip.colorCorrection ?? ColorCorrection()
        colorCorrection.brightness = 0.05
        colorCorrection.contrast = 1.1
        colorCorrection.saturation = 1.1

        try await session.dispatch(SetColorCorrectionCommand(clipId: clipId, colorCorrection: colorCorrection))
        try await refreshFromSession()
    }

    func updateSelectedMask(_ mask: Mask?) async {
        guard let selectedClipId else { return }
        await apply(SetClipMaskCommand(clipId: selectedClipId, mask: mask))
    }

    /// Commits a canvas-edited crop rect as one undoable property edit. A
    /// full-frame rect is stored as nil so never-cropped projects keep the
    /// byte-identical JSON encoding (cropRect key omitted).
    func updateSelectedCropRect(_ cropRect: NormalizedRect?) async {
        guard let selectedClipId else { return }
        let normalized = cropRect.flatMap { CropPixelProcessor.isFullFrame($0) ? nil : $0 }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .cropRect(normalized)))
    }

    func updateSelectedReversePlayback(_ isReversed: Bool) async {
        guard let selectedClipId, let selectedClip, selectedClip.isReversed != isReversed else { return }
        await apply(ReverseClipCommand(clipId: selectedClipId))
    }

    func updateSelectedEffects(_ effects: [Effect]) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .effects(effects)))
    }

    /// Appends against the EditorSession's current state rather than replacing
    /// an effects array captured by the sheet. The target clip is explicit so a
    /// selection change while the browser sheet is open cannot redirect Apply.
    func appendEffect(_ effect: Effect, to clipId: UUID) async {
        await apply(AppendClipEffectCommand(clipId: clipId, effect: effect))
    }
}
