import AVFoundation
import CoreImage
import Foundation
import MovieCutCore

/// Chroma-key eyedropper, real-time color scopes, and cut-suggestion boundary
/// of the EditorViewModel decomposition. Pure method moves from
/// `EditorViewModel.swift`; stored `@Observable` scope state stays in the main
/// class body.
extension EditorViewModel {
    // MARK: - Chroma key eyedropper (F-10)

    func toggleChromaKeyEyedropper() {
        isChromaKeyEyedropperActive.toggle()
        lastStatusMessage = isChromaKeyEyedropperActive
            ? "Eyedropper on: click the preview to pick the key color."
            : nil
    }

    /// Samples the selected video clip's frame at a normalized preview point and
    /// sets it as the chroma key color (F-10 eyedropper).
    func pickChromaKeyColor(atNormalizedPoint point: CGPoint) async {
        defer { isChromaKeyEyedropperActive = false }

        guard let selectedClipId, let clip = selectedClip, clip.kind == .video,
              let assetId = clip.assetId,
              let asset = currentProject.mediaLibrary.assets[assetId] else {
            lastErrorMessage = "Select a video clip to pick a key color."
            return
        }
        _ = selectedClipId

        let localTime = max(0, playheadTime - clip.timelineRange.start)
        let sourceTime = clip.sourceRange.start + localTime
        let avAsset = AVAsset(url: asset.originalURL)
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        do {
            let cmTime = CMTime(seconds: sourceTime, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)
            guard let color = PixelSampler.color(in: cgImage, atNormalizedPoint: point) else {
                lastErrorMessage = "Couldn't sample that point."
                return
            }

            let hex = PixelSampler.hexString(from: color)
            var settings = clip.chromaKey ?? ChromaKeySettings.greenScreen()
            settings.keyColor = hex
            await updateSelectedChromaKey(settings)
            lastErrorMessage = nil
            lastStatusMessage = "Key color set to \(hex)."
        } catch {
            lastErrorMessage = "Couldn't read the frame: \(error.localizedDescription)"
        }
    }

    // MARK: - Color scopes (Phase 2A)

    func clearScopes() {
        scopeHistogram = nil
        scopeWaveform = nil
        scopeVectorscope = nil
        scopeRGBParade = nil
    }

    /// Recomputes ``scopeHistogram`` from the selected clip's graded thumbnail.
    func refreshScopes() {
        guard let clip = selectedClip,
              let assetId = clip.assetId,
              let asset = currentProject.mediaLibrary.assets[assetId],
              let thumbnailData = asset.thumbnailData,
              let source = CIImage(data: thumbnailData) else {
            clearScopes()
            return
        }

        var image = source
        if let colorCorrection = clip.colorCorrection {
            image = ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)
        }
        if let colorGrade = clip.colorGrade {
            image = ColorGradePixelProcessor.apply(colorGrade, to: image)
        }

        let width = 96
        let height = 54
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { clearScopes(); return }
        let scaled = image.transformed(by: CGAffineTransform(
            scaleX: CGFloat(width) / extent.width,
            y: CGFloat(height) / extent.height
        ))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            scopeContext.render(
                scaled,
                toBitmap: base,
                rowBytes: width * 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        // Single pass over the rendered bytes: the four individual reducers
        // each walked the same 96×54 buffer again (4 redundant pixel loops).
        let all = ScopeAnalyzer.analyzeAll(
            rgba: bytes,
            width: width,
            height: height,
            histogramBins: 64,
            waveformColumns: width,
            waveformLevels: 48,
            vectorscopeSize: 48
        )
        scopeHistogram = all.histogram
        scopeWaveform = all.lumaWaveform
        scopeVectorscope = all.vectorscope
        scopeRGBParade = all.rgbParade
    }

    func suggestCuts() async throws {
        guard let clipId = selectedClipId else { return }
        // Attempt BOTH tools (a silence-cut result is still useful when scene
        // detection fails), but never swallow the failures — report which
        // ones failed so the user knows what they got.
        var failures: [String] = []
        do {
            _ = try await autoCutSilence(for: clipId)
        } catch {
            failures.append("silence cut")
        }
        do {
            _ = try await detectAndSplitScenes(for: clipId)
        } catch {
            failures.append("scene detection")
        }
        if !failures.isEmpty {
            lastStatusMessage = nil
            lastErrorMessage = "Cut suggestion failed for: \(failures.joined(separator: ", "))."
        }
    }
}
