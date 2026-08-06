import Foundation
import Testing
@testable import MovieCutCore

/// Tests for the "Photo to Video" home onboarding entry point (G-21 partial).
///
/// These verify the built-in photo-slideshow template is registered, has the
/// expected 9:16 canvas + music/title tracks, and that `TemplateStore` produces
/// a well-formed project from it. This is the Core-level contract for the
/// one-click photo-to-video workflow wired in the home Quick Start card.
@Suite("Photo Slideshow Template")
struct PhotoSlideshowTemplateTests {
    @Test("Photo slideshow template is registered in the built-in bundles")
    func slideshowTemplateRegistered() {
        let bundles = TemplateStore.builtInTemplateBundles
        let identifiers = bundles.map(\.identifier)
        #expect(identifiers.contains("com.moviecut.template.photo-slideshow"))
    }

    @Test("Photo slideshow template targets 9:16 portrait at 1080p")
    func slideshowCanvasIsPortrait9x16() {
        let template = TemplateStore.photoSlideshowTemplate
        #expect(template.canvasPreset.aspectRatio == .portrait9x16)
        #expect(template.canvasPreset.size == CGSize(width: 1080, height: 1920))
        #expect(template.exportPreset.resolution == .p1080)
    }

    @Test("Photo slideshow template seeds a video track, a music track, and a title track")
    func slideshowTrackLayout() throws {
        let template = TemplateStore.photoSlideshowTemplate
        let kinds = template.tracks.map(\.kind)
        #expect(kinds == [.video, .audio, .text])

        let videoTrack = try #require(template.tracks.first(where: { $0.kind == .video }))
        // Placeholder image clips exist so the user sees structure before picking photos.
        #expect(!videoTrack.placeholderClips.isEmpty)
        #expect(videoTrack.placeholderClips.allSatisfy { $0.kind == .image })

        // Music track is empty and ready for the user's BGM.
        let audioTrack = try #require(template.tracks.first(where: { $0.kind == .audio }))
        #expect(audioTrack.placeholderClips.isEmpty)

        // Title track carries text content.
        let textTrack = try #require(template.tracks.first(where: { $0.kind == .text }))
        #expect(textTrack.placeholderClips.contains(where: { $0.textContent != nil }))
    }

    @Test("Photo slideshow clip default duration is 3 seconds")
    func slideshowClipDuration() {
        #expect(PhotoSlideshowDefaults.clipDuration == 3.0)
        // Every image placeholder uses the shared default.
        let template = TemplateStore.photoSlideshowTemplate
        let videoTrack = template.tracks.first(where: { $0.kind == .video })
        #expect(videoTrack?.placeholderClips.allSatisfy { $0.duration == PhotoSlideshowDefaults.clipDuration } ?? false)
    }

    @Test("TemplateStore creates a well-formed project from the photo slideshow template")
    func storeCreatesProject() {
        let store = TemplateStore(bundles: [TemplateStore.photoSlideshowTemplate])
        let project = store.createProject(from: TemplateStore.photoSlideshowTemplate)

        #expect(project.canvas.aspectRatio == .portrait9x16)
        #expect(project.timeline.tracks.count == 3)
        // Video track clips are image placeholders laid out sequentially.
        let videoTrack = project.timeline.tracks.first(where: { $0.kind == .video })
        #expect(videoTrack != nil)
        #expect(videoTrack?.clips.allSatisfy { $0.kind == .image } ?? false)
    }

    // MARK: - Pace and transition presets (Task 2)

    @Test("Pace presets map to distinct per-photo durations")
    func paceDurationsAreDistinct() {
        #expect(PhotoSlideshowPace.slow.clipDuration == 5.0)
        #expect(PhotoSlideshowPace.normal.clipDuration == PhotoSlideshowDefaults.clipDuration)
        #expect(PhotoSlideshowPace.fast.clipDuration == 1.5)
        // All three differ so the picker is meaningful.
        let durations = Set(PhotoSlideshowPace.allCases.map(\.clipDuration))
        #expect(durations.count == 3)
    }

    @Test("Pace and transition presets are CaseIterable and Identifiable for pickers")
    func presetsArePickerReady() {
        #expect(PhotoSlideshowPace.allCases.count == 3)
        #expect(PhotoSlideshowTransition.allCases.count == 3)
        // Identifiable via rawValue so they work in ForEach.
        #expect(PhotoSlideshowPace.allCases.map(\.id) == PhotoSlideshowPace.allCases.map(\.rawValue))
        #expect(PhotoSlideshowTransition.allCases.map(\.id) == PhotoSlideshowTransition.allCases.map(\.rawValue))
    }

    @Test("Transition style maps to the expected core transition type, none for hard cut")
    func transitionStyleMapsToCoreType() {
        #expect(PhotoSlideshowTransition.none.transitionType == nil)
        #expect(PhotoSlideshowTransition.crossDissolve.transitionType == .crossDissolve)
        #expect(PhotoSlideshowTransition.fadeThroughBlack.transitionType == .fadeThroughBlack)
    }

    @Test("Transition duration default is positive and shorter than the fastest pace")
    func transitionDurationIsSane() {
        // The workflow clamps the boundary transition to half the clip duration,
        // so the default must stay below the shortest pace to be meaningful.
        #expect(PhotoSlideshowDefaults.transitionDuration > 0)
        #expect(PhotoSlideshowDefaults.transitionDuration < PhotoSlideshowPace.fast.clipDuration)
    }
}
