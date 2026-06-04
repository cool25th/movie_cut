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
}

@Test func exportSettingsRoundTrip() throws {
    let settings = ExportSettings(
        resolution: .p4K,
        frameRate: .fps60,
        codec: .hevc,
        audioCodec: .pcm
    )

    let data = try JSONEncoder().encode(settings)
    let decodedSettings = try JSONDecoder().decode(ExportSettings.self, from: data)

    #expect(decodedSettings == settings)
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
    #expect(EffectType.allCases.count == 12)
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
    #expect(TransitionType.allCases.count == 4)
    #expect(TransitionType.none.rawValue == "none")
    #expect(TransitionType.crossDissolve.rawValue == "crossDissolve")
    #expect(TransitionType.fadeThroughBlack.rawValue == "fadeThroughBlack")
    #expect(TransitionType.wipeRight.rawValue == "wipeRight")
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
