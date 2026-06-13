import CoreGraphics
import Foundation
import MovieCutCore
import Testing

@Test func exportSettingsDefaults() {
    let settings = ExportSettings()

    #expect(settings.resolution == .p1080)
    #expect(settings.codec == .h264)
    #expect(settings.audioCodec == .aac)
    #expect(settings.frameRate == .fps30)
    #expect(settings.containerFormat == .mp4)
    #expect(settings.quality == .high)
    #expect(settings.videoBitrateMbps == nil)
    #expect(settings.resolvedVideoBitrateMbps == 20)
}

@Test func exportSettingsRoundTrip() throws {
    let settings = ExportSettings(
        resolution: .p4K,
        frameRate: .fps60,
        codec: .hevc,
        audioCodec: .pcm,
        containerFormat: .mov,
        quality: .custom,
        videoBitrateMbps: 42
    )

    let data = try JSONEncoder().encode(settings)
    let decodedSettings = try JSONDecoder().decode(ExportSettings.self, from: data)

    #expect(decodedSettings == settings)
}

@Test func exportSettingsDecodesLegacyJSONWithDefaults() throws {
    let json = """
    {
      "resolution": "p720",
      "frameRate": "fps24",
      "codec": "h264",
      "audioCodec": "aac"
    }
    """.data(using: .utf8)!

    let settings = try JSONDecoder().decode(ExportSettings.self, from: json)

    #expect(settings.resolution == .p720)
    #expect(settings.frameRate == .fps24)
    #expect(settings.codec == .h264)
    #expect(settings.audioCodec == .aac)
    #expect(settings.containerFormat == .mp4)
    #expect(settings.quality == .high)
    #expect(settings.videoBitrateMbps == nil)
}

@Test func exportResolutionCases() {
    #expect(ExportResolution.p720.rawValue == "p720")
    #expect(ExportResolution.p1080.rawValue == "p1080")
    #expect(ExportResolution.p4K.rawValue == "p4K")
}

@Test func exportCodecCases() {
    #expect(ExportCodec.h264.rawValue == "h264")
    #expect(ExportCodec.hevc.rawValue == "hevc")
}

@Test func exportFrameRateAllCases() {
    #expect(ExportFrameRate.allCases.count == 3)
}

@Test func audioCodecCases() {
    #expect(AudioCodec.aac.rawValue == "aac")
    #expect(AudioCodec.pcm.rawValue == "pcm")
}

@Test func exportContainerFormatCases() {
    #expect(ExportContainerFormat.allCases.count == 3)
    #expect(ExportContainerFormat.mp4.rawValue == "mp4")
    #expect(ExportContainerFormat.mov.rawValue == "mov")
    #expect(ExportContainerFormat.m4v.rawValue == "m4v")
    #expect(ExportContainerFormat.mp4.fileExtension == "mp4")
    #expect(ExportContainerFormat.mov.fileExtension == "mov")
    #expect(ExportContainerFormat.m4v.fileExtension == "m4v")
    #expect(ExportContainerFormat.mp4.displayName == "MP4")
    #expect(ExportContainerFormat.mov.displayName == "MOV")
    #expect(ExportContainerFormat.m4v.displayName == "M4V")
}

@Test func exportQualityCasesAndBitrateMapping() {
    #expect(ExportQuality.allCases.count == 4)
    #expect(ExportQuality.low.rawValue == "low")
    #expect(ExportQuality.medium.rawValue == "medium")
    #expect(ExportQuality.high.rawValue == "high")
    #expect(ExportQuality.custom.rawValue == "custom")
    #expect(ExportQuality.low.defaultVideoBitrateMbps(for: .p1080) == 5)
    #expect(ExportQuality.medium.defaultVideoBitrateMbps(for: .p1080) == 10)
    #expect(ExportQuality.high.defaultVideoBitrateMbps(for: .p1080) == 20)
    #expect(ExportQuality.high.defaultVideoBitrateMbps(for: .p4K) == 60)
    #expect(ExportQuality.custom.defaultVideoBitrateMbps(for: .p1080) == nil)
}

@Test func canvasPresetDefault() {
    let preset = CanvasPreset.defaultPreset()

    #expect(preset.aspectRatio == .landscape16x9)
    #expect(preset.size.width == 1920)
    #expect(preset.size.height == 1080)
    #expect(preset.frameRate == .fps30)
}

@Test func aspectRatioSizes() {
    #expect(AspectRatio.landscape16x9.size.width == 1920)
    #expect(AspectRatio.landscape16x9.size.height == 1080)
    #expect(AspectRatio.portrait9x16.size.width == 1080)
    #expect(AspectRatio.portrait9x16.size.height == 1920)
    #expect(AspectRatio.portrait4x5.size.width == 1080)
    #expect(AspectRatio.portrait4x5.size.height == 1350)
    #expect(AspectRatio.square1x1.size.width == 1080)
    #expect(AspectRatio.square1x1.size.height == 1080)
    #expect(AspectRatio.wide21x9.size.width == 2560)
    #expect(AspectRatio.wide21x9.size.height == 1080)
    #expect(AspectRatio.ultrawide21x9.size.width == 2520)
    #expect(AspectRatio.ultrawide21x9.size.height == 1080)
    #expect(AspectRatio.custom.size.width == 0)
    #expect(AspectRatio.custom.size.height == 0)
}

@Test func canvasPresetCustomSize() {
    let preset = CanvasPreset(aspectRatio: .custom, customWidth: 800, customHeight: 600)

    #expect(preset.size.width == 800)
    #expect(preset.size.height == 600)
}

@Test func clipTransformDefaults() {
    let transform = ClipTransform()

    #expect(transform.position.x == 0)
    #expect(transform.position.y == 0)
    #expect(transform.scale.width == 1)
    #expect(transform.scale.height == 1)
    #expect(transform.rotation == 0)
    #expect(transform.anchorPoint.x == 0.5)
    #expect(transform.anchorPoint.y == 0.5)
}

@Test func clipTransformCustom() {
    let transform = ClipTransform(
        position: CGPoint(x: 120, y: 240),
        scale: CGSize(width: 1.5, height: 0.75),
        rotation: 45
    )

    #expect(transform.position.x == 120)
    #expect(transform.position.y == 240)
    #expect(transform.scale.width == 1.5)
    #expect(transform.scale.height == 0.75)
    #expect(transform.rotation == 45)
}

@Test func colorCorrectionDefaults() {
    let correction = ColorCorrection()

    #expect(correction.brightness == 0)
    #expect(correction.contrast == 1)
    #expect(correction.saturation == 1)
    #expect(correction.warmth == 0)
    #expect(correction.tint == 0)
}

@Test func colorCorrectionClamping() {
    let correction = ColorCorrection(
        brightness: 2,
        contrast: -1,
        saturation: 3,
        warmth: 2,
        tint: -2
    )

    #expect(correction.brightness == 1)
    #expect(correction.contrast == 0)
    #expect(correction.saturation == 2)
    #expect(correction.warmth == 1)
    #expect(correction.tint == -1)
}

@Test func effectTypeAllCases() {
    #expect(EffectType.allCases.count == 18)
}

@Test func effectCreation() {
    let effect = Effect(type: .blur, parameters: ["radius": 5.0])

    #expect(effect.type == .blur)
    #expect(effect.parameters == ["radius": 5.0])
}

@Test func effectStaticHelpers() {
    #expect(Effect.grayscale.type == .grayscale)
    #expect(Effect.sepia.type == .sepia)
    #expect(Effect.blur.type == .blur)
    #expect(Effect.blur.parameters["radius"] != nil)
    #expect(Effect.styleTransfer.type == .styleTransfer)
    #expect(Effect.cinematicLUT.type == .cinematicLUT)
    #expect(Effect.vintageLUT.type == .vintageLUT)
    #expect(Effect.noirLUT.type == .noirLUT)
    #expect(Effect.vividLUT.type == .vividLUT)
    #expect(Effect.coolLUT.type == .coolLUT)
}

@Test func speedRampCurveLinearIsConstant() {
    #expect(SpeedRampCurve.linear.isConstant() == true)
}

@Test func speedRampCurveSinglePoint() {
    let curve = SpeedRampCurve(points: [
        SpeedRampPoint(time: 0, rate: 2.0)
    ])

    #expect(curve.timeMapping(sourceTime: 2) == 1.0)
}

@Test func speedRampCurveInverseRoundTrip() {
    for sourceTime in [0.0, 0.25, 1.0, 2.5, 10.0] {
        let outputTime = SpeedRampCurve.linear.timeMapping(sourceTime: sourceTime)
        let roundTripSourceTime = SpeedRampCurve.linear.inverseMapping(outputTime: outputTime)

        #expect(abs(roundTripSourceTime - sourceTime) < 1.0e-9)
    }
}

@Test func transitionTypeAllCases() {
    #expect(TransitionType.allCases.count == 12)
    #expect(TransitionType.none.rawValue == "none")
    #expect(TransitionType.crossDissolve.rawValue == "crossDissolve")
    #expect(TransitionType.fadeThroughBlack.rawValue == "fadeThroughBlack")
    #expect(TransitionType.wipeRight.rawValue == "wipeRight")
    #expect(TransitionType.wipeLeft.rawValue == "wipeLeft")
    #expect(TransitionType.wipeUp.rawValue == "wipeUp")
    #expect(TransitionType.wipeDown.rawValue == "wipeDown")
    #expect(TransitionType.slideLeft.rawValue == "slideLeft")
    #expect(TransitionType.slideRight.rawValue == "slideRight")
    #expect(TransitionType.zoomIn.rawValue == "zoomIn")
    #expect(TransitionType.zoomOut.rawValue == "zoomOut")
    #expect(TransitionType.glitch.rawValue == "glitch")
}

@Test func maskCreation() {
    let mask = Mask(
        shape: .rectangle,
        position: CGPoint(x: 100, y: 200),
        size: CGSize(width: 300, height: 400),
        feather: 12.5,
        inverted: true
    )

    #expect(mask.shape == .rectangle)
    #expect(mask.position.x == 100)
    #expect(mask.position.y == 200)
    #expect(mask.size.width == 300)
    #expect(mask.size.height == 400)
    #expect(mask.rotation == 0)
    #expect(mask.feather == 12.5)
    #expect(mask.inverted == true)
    #expect(mask.brushPoints.isEmpty)
}

@Test func maskJSONRoundTrip() throws {
    let mask = Mask(
        shape: .brush,
        position: CGPoint(x: 50, y: 75),
        size: CGSize(width: 250, height: 125),
        rotation: 30,
        feather: 8,
        inverted: true,
        brushPoints: [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 30, y: 40)
        ]
    )

    let data = try JSONEncoder().encode(mask)
    let decodedMask = try JSONDecoder().decode(Mask.self, from: data)

    #expect(decodedMask == mask)
}

@Test func maskShapeAllCases() {
    #expect(MaskShape.allCases.count == 6)
}

@Test func chromaKeyGreenScreen() {
    #expect(ChromaKeySettings.greenScreen().keyColor == "#00FF00")
}

@Test func chromaKeyBlueScreen() {
    #expect(ChromaKeySettings.blueScreen().keyColor == "#0000FF")
}

@Test func chromaKeyClamping() {
    let settings = ChromaKeySettings(
        keyColor: "#00FF00",
        tolerance: 2.0,
        softness: -1.0,
        spillSuppression: 0.5
    )

    #expect(settings.tolerance == 1.0)
    #expect(settings.softness == 0.0)
}

@Test func textClipContentDefaults() {
    let content = TextClipContent(text: "Hello")

    #expect(content.fontFamily == "System")
    #expect(content.fontSize == 48)
    #expect(content.fontColor == "#FFFFFF")
    #expect(content.alignment == .center)
    #expect(content.contentKind == .text)
    #expect(content.stickerAssetID == nil)
    #expect(content.isSticker == false)
}

@Test func textClipContentRoundTrip() throws {
    let content = TextClipContent(
        text: "Hello",
        fontFamily: "Helvetica",
        fontSize: 36,
        fontColor: "#FFCC00",
        alignment: .leading,
        backgroundColor: "#000000",
        position: CGPoint(x: 400, y: 300),
        animation: TextAnimation(type: .slideUp, duration: 0.75, delay: 0.2)
    )

    let data = try JSONEncoder().encode(content)
    let decodedContent = try JSONDecoder().decode(TextClipContent.self, from: data)

    #expect(decodedContent == content)
}

@Test func textClipContentDecodesLegacyStickerMetadataDefaults() throws {
    let legacyArrayPointJSON = """
    {
      "text": "Legacy",
      "fontFamily": "System",
      "fontSize": 48,
      "fontColor": "#FFFFFF",
      "alignment": "center",
      "position": [0, 0]
    }
    """.data(using: .utf8)!
    let legacyDictionaryPointJSON = """
    {
      "text": "Legacy",
      "fontFamily": "System",
      "fontSize": 48,
      "fontColor": "#FFFFFF",
      "alignment": "center",
      "position": { "x": 12, "y": 24 }
    }
    """.data(using: .utf8)!

    let decodedContent = try JSONDecoder().decode(TextClipContent.self, from: legacyArrayPointJSON)
    let decodedDictionaryPointContent = try JSONDecoder().decode(TextClipContent.self, from: legacyDictionaryPointJSON)

    #expect(decodedContent.text == "Legacy")
    #expect(decodedContent.contentKind == .text)
    #expect(decodedContent.stickerAssetID == nil)
    #expect(decodedContent.isSticker == false)
    #expect(decodedDictionaryPointContent.position.x == 12)
    #expect(decodedDictionaryPointContent.position.y == 24)
    #expect(decodedDictionaryPointContent.contentKind == .text)
}

@Test func stickerTextClipContentRoundTrip() throws {
    let stickerID = UUID(uuidString: "00000000-0000-4000-8000-000000000006")!
    let content = TextClipContent(
        text: "🔥",
        fontFamily: "Apple Color Emoji",
        fontSize: 120,
        backgroundColor: "#00000000",
        position: CGPoint(x: 640, y: 360),
        animation: TextAnimation(type: .scale, duration: 0.25),
        contentKind: .sticker,
        stickerAssetID: stickerID
    )

    let data = try JSONEncoder().encode(content)
    let decodedContent = try JSONDecoder().decode(TextClipContent.self, from: data)

    #expect(decodedContent == content)
    #expect(decodedContent.isSticker == true)
    #expect(decodedContent.stickerAssetID == stickerID)
}

@Test func builtInStickerAssetIDsAreStable() {
    let firstLibrary = StickerLibrary.builtIn()
    let secondLibrary = StickerLibrary.builtIn()

    #expect(firstLibrary.stickers.map(\.id) == secondLibrary.stickers.map(\.id))
    #expect(Set(firstLibrary.stickers.map(\.id)).count == firstLibrary.stickers.count)
}

@Test func textClipContentWithAnimation() {
    let animation = TextAnimation(type: .fadeIn, duration: 0.5)
    let content = TextClipContent(text: "Hello", animation: animation)

    #expect(content.animation == animation)
}

@Test func keyframeInterpolateLinear() {
    #expect(Keyframe.interpolate(from: 0, to: 10, progress: 0.5, mode: .linear) == 5.0)
}

@Test func keyframeInterpolateHold() {
    #expect(Keyframe.interpolate(from: 0, to: 10, progress: 0.5, mode: .hold) == 0.0)
}

@Test func keyframeInterpolateEaseIn() {
    #expect(Keyframe.interpolate(from: 0, to: 10, progress: 0.5, mode: .easeIn) < 5.0)
}

@Test func keyframeTimeClamping() {
    let keyframe = Keyframe(property: .opacity, time: -5, value: 0.5)

    #expect(keyframe.time == 0)
}

@Test func mediaAssetCreation() {
    let videoURL = URL(fileURLWithPath: "/tmp/video.mov")
    let audioURL = URL(fileURLWithPath: "/tmp/audio.wav")
    let imageURL = URL(fileURLWithPath: "/tmp/image.png")
    let videoAsset = MediaAsset(originalURL: videoURL, kind: .video)
    let audioAsset = MediaAsset(originalURL: audioURL, kind: .audio)
    let imageAsset = MediaAsset(originalURL: imageURL, kind: .image)

    #expect(videoAsset.kind == .video)
    #expect(videoAsset.originalURL == videoURL)
    #expect(audioAsset.kind == .audio)
    #expect(audioAsset.originalURL == audioURL)
    #expect(imageAsset.kind == .image)
    #expect(imageAsset.originalURL == imageURL)
}

@Test func mediaAssetOptionalDuration() {
    let url = URL(fileURLWithPath: "/tmp/video.mov")
    let assetWithDuration = MediaAsset(originalURL: url, kind: .video, duration: 12.5)
    let assetWithoutDuration = MediaAsset(originalURL: url, kind: .video)

    #expect(assetWithDuration.duration == 12.5)
    #expect(assetWithoutDuration.duration == nil)
}

@Test func waveformDataEquality() {
    let firstWaveform = WaveformData(samples: [0.0, 0.25, 0.5, 1.0], sampleCount: 4)
    let secondWaveform = WaveformData(samples: [0.0, 0.25, 0.5, 1.0], sampleCount: 4)

    #expect(firstWaveform == secondWaveform)
}

@Test func animatablePropertyAllCases() {
    #expect(AnimatableProperty.allCases.count == 7)
}

@Test func interpolationModeAllCases() {
    #expect(InterpolationMode.allCases.count == 5)
}
