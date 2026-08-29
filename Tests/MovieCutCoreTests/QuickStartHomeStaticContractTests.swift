import Foundation
import Testing
@testable import MovieCutCore

/// Static-contract checks for the CapCut-style home "Quick Start" entry points.
///
/// The home screen previously exposed only New / Open. The Quick Start cards
/// (New Project / Templates / Photo to Video) and the matching router methods
/// are the onboarding gap these tests lock against regression. The macOS app
/// target is built by xcodebuild; these checks keep the wiring visible in the
/// faster SwiftPM core test loop, mirroring the other `*StaticContract` suites.
@Suite("Quick Start Home Static Contract")
struct QuickStartHomeStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    // MARK: - Home Quick Start cards

    @Test("HomeView surfaces a Quick Start section with three entry-point cards")
    func homeHasQuickStartCards() throws {
        let source = try source("App/MovieCutMac/Home/HomeView.swift")

        // The section itself is rendered above the recent-projects grid.
        #expect(source.contains("quickStartSection"))
        #expect(source.contains("Start something new"))

        // Three CapCut-style entry points, each with a stable accessibility id.
        #expect(source.contains("\"New Project\""))
        #expect(source.contains("\"Templates\""))
        #expect(source.contains("\"Photo to Video\""))
        #expect(source.contains("home.quickStart.newProject"))
        #expect(source.contains("home.quickStart.templates"))
        #expect(source.contains("home.quickStart.photoToVideo"))
    }

    @Test("HomeView wires the photo picker to the router's photo-slideshow request")
    func homeWiresPhotoPickerToRouter() throws {
        let source = try source("App/MovieCutMac/Home/HomeView.swift")

        // A multi-image file importer feeds the router with the chosen options.
        #expect(source.contains("isPhotoPickerPresented"))
        #expect(source.contains("allowsMultipleSelection: true"))
        #expect(source.contains("requestCreatePhotoSlideshow("))
        #expect(source.contains("pace: pace"))
        #expect(source.contains("transitionStyle: transitionStyle"))
        #expect(source.contains("kenBurnsEnabled: kenBurnsEnabled"))
    }

    @Test("HomeView opens a slideshow options sheet before the photo picker")
    func homeOpensSlideshowOptionsSheet() throws {
        let source = try source("App/MovieCutMac/Home/HomeView.swift")

        #expect(source.contains("isSlideshowOptionsPresented"))
        #expect(source.contains("slideshowOptionsSheet"))
        // Pace and transition pickers are exposed with stable accessibility ids.
        #expect(source.contains("home.slideshow.pace"))
        #expect(source.contains("home.slideshow.transition"))
        #expect(source.contains("home.slideshow.choosePhotos"))
        // Ken Burns motion toggle is exposed in the options sheet.
        #expect(source.contains("home.slideshow.kenBurns"))
        #expect(source.contains("Motion (Ken Burns)"))
    }

    @Test("HomeView presents the template picker from the home card, not only the editor toolbar")
    func homeOpensTemplatePicker() throws {
        let source = try source("App/MovieCutMac/Home/HomeView.swift")
        #expect(source.contains("isTemplatePickerPresented"))
        #expect(source.contains("TemplatePickerView(viewModel: viewModel)"))
    }

    // MARK: - Router methods

    @Test("AppStageRouter exposes template and photo-slideshow creation requests")
    func routerExposesQuickStartRequests() throws {
        let source = try source("App/MovieCutMac/Home/AppStageRouter.swift")

        #expect(source.contains("func requestCreateFromTemplate"))
        #expect(source.contains("func requestCreatePhotoSlideshow"))
        #expect(source.contains("viewModel.createProjectFromTemplate(bundle)"))
        // The router forwards the chosen pace and transition to the workflow.
        #expect(source.contains("pace: PhotoSlideshowPace"))
        #expect(source.contains("transitionStyle: PhotoSlideshowTransition"))
        #expect(source.contains("pace: pace"))
        #expect(source.contains("transitionStyle: transitionStyle"))
        #expect(source.contains("kenBurnsEnabled: kenBurnsEnabled"))
    }

    // MARK: - ViewModel workflow

    @Test("EditorViewModel implements the photo-slideshow workflow")
    func viewModelImplementsSlideshowWorkflow() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")

        // The workflow accepts pace and transition-style parameters.
        #expect(source.contains("func createPhotoSlideshow("))
        #expect(source.contains("pace: PhotoSlideshowPace = .normal"))
        #expect(source.contains("transitionStyle: PhotoSlideshowTransition = .crossDissolve"))
        #expect(source.contains("kenBurnsEnabled: Bool = true"))
        // Filters to images, seeds from the slideshow template, and lays out the
        // photos sequentially on the first video track.
        #expect(source.contains("(try? MediaImporter.validatedProbe(url: url))?.kind == .image"))
        #expect(source.contains("com.moviecut.template.photo-slideshow"))
        #expect(source.contains("insertionStart += duration"))
        // Adjacent photos get a transition; the first photo does not.
        #expect(source.contains("boundaryTransition"))
        #expect(source.contains("index == 0 ? nil : boundaryTransition"))
        // The per-photo duration is driven by the chosen pace.
        #expect(source.contains("pace.clipDuration"))
        // Ken Burns default zoom-in is applied to each photo when enabled.
        #expect(source.contains("KenBurnsEffect.defaultZoomIn()"))
        #expect(source.contains("kenBurnsEffect: clipKenBurns"))
    }

    // MARK: - Image rasterization wiring (Ken Burns)

    @Test("ImageVideoRenderService bakes Ken Burns into the per-frame draw")
    func imageRasterizerBakesKenBurns() throws {
        // G-15 AC6: the service moved from the Mac app target to Core
        // (Sources/MovieCutCore/Rendering) so the iOS render plan shares it.
        let source = try source("Sources/MovieCutCore/Rendering/ImageVideoRenderService.swift")

        // The render entry point accepts a Ken Burns effect.
        #expect(source.contains("kenBurnsEffect: KenBurnsEffect? = nil"))
        // Per-frame progress is sampled so the motion advances across frames.
        #expect(source.contains("let progress = totalFrames > 1"))
        // The draw resolves the transform at the sampled progress.
        #expect(source.contains("kenBurnsEffect.transform(at: progress)"))
        // The source image is loaded at a higher resolution when zoomed so the
        // zoomed-in crop stays sharp.
        #expect(source.contains("max($0.startScale, $0.endScale)"))
    }

    @Test("Playback and export engines forward the clip's Ken Burns effect")
    func enginesForwardKenBurns() throws {
        let playback = try String(contentsOfFile: "App/MovieCutMac/Playback/PlaybackEngine.swift", encoding: .utf8)
        let export = try String(contentsOfFile: "App/MovieCutMac/Export/ExportEngine.swift", encoding: .utf8)

        // Both engines pass the clip's effect to the rasterizer.
        #expect(playback.contains("kenBurnsEffect: clip.kenBurnsEffect"))
        #expect(export.contains("kenBurnsEffect: clip.kenBurnsEffect"))
    }
}
