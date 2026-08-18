import Foundation
import Testing
@testable import MovieCutCore

/// Locks the macOS `ExportEngine` wiring for the planner-backed export kinds
/// added on top of the legacy preset path: audio-only, still-frame, animated
/// GIF, and the explicit-bitrate `AVAssetWriter` path. These assertions run on
/// the app source string because the engine itself lives in the app target.
@Suite("Export Engine Formats Static Contract")
struct ExportEngineFormatsStaticContractTests {
    private func engineSource() throws -> String {
        try String(contentsOfFile: "App/MovieCutMac/Export/ExportEngine.swift", encoding: .utf8)
    }

    @Test("Engine owns a shared ExportPlanner instance")
    func engineUsesExportPlanner() throws {
        let source = try engineSource()
        #expect(source.contains("private let exportPlanner = ExportPlanner()"))
    }

    @Test("Audio-only export produces an m4a from the GRAPH mix (G-25 2C-1a)")
    func audioOnlyExportContract() throws {
        let source = try engineSource()
        #expect(source.contains("func exportAudioOnly("))
        // G-25 switchover: samples originate from the graph (spec §1) —
        // GraphMixRenderer builds the mix, AudioGraphAacEncoder writes the
        // AAC. The legacy composition/audioMix path (AVAssetExportPresetAppleM4A
        // + audioMix) is deliberately GONE from this function.
        #expect(source.contains("GraphMixRenderer.renderMix("))
        #expect(source.contains("AudioGraphAacEncoder.encode("))
        let function = try functionBody(of: "func exportAudioOnly(", in: source)
        #expect(function.contains("AVAssetExportPresetAppleM4A") == false)
        #expect(function.contains(".audioMix") == false)
    }

    /// Extracts one function body (brace-balanced) from a source string so
    /// contract assertions can scope to a single function.
    private func functionBody(of declaration: String, in source: String) throws -> Substring {
        guard let start = source.range(of: declaration)?.lowerBound else {
            throw NSError(domain: "StaticContract", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "missing \(declaration)"])
        }
        guard let openBrace = source[start...].firstIndex(of: "{") else {
            throw NSError(domain: "StaticContract", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "no body for \(declaration)"])
        }
        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return source[openBrace...index] }
            }
            index = source.index(after: index)
        }
        throw NSError(domain: "StaticContract", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "unbalanced braces for \(declaration)"])
    }

    @Test("Still-frame export renders a PNG through the video composition")
    func stillFrameExportContract() throws {
        let source = try engineSource()
        #expect(source.contains("func exportStillFrame("))
        #expect(source.contains("copyCGImage(at: requestedTime, actualTime: nil)"))
        #expect(source.contains("type: UTType.png"))
    }

    @Test("Animated GIF export samples frames into a CGImageDestination GIF")
    func animatedGIFExportContract() throws {
        let source = try engineSource()
        #expect(source.contains("func exportAnimatedGIF("))
        #expect(source.contains("UTType.gif.identifier"))
        #expect(source.contains("kCGImagePropertyGIFDelayTime"))
        #expect(source.contains("kCGImagePropertyGIFLoopCount"))
    }

    @Test("Explicit-bitrate export drives AVAssetWriter from planner output settings")
    func explicitBitrateExportContract() throws {
        let source = try engineSource()
        #expect(source.contains("func exportVideoWithExplicitBitrate("))
        #expect(source.contains("exportPlanner.assetWriterVideoOutputSettings(for: plan)"))
        #expect(source.contains("exportPlanner.assetWriterAudioOutputSettings(for: plan)"))
        #expect(source.contains("AVAssetWriter(outputURL: url, fileType: fileType)"))
        #expect(source.contains("AVAssetReaderVideoCompositionOutput("))
    }

    @Test("Optical-flow slow motion raises export composition frame cadence")
    func opticalFlowSlowMotionExportContract() throws {
        let source = try engineSource()
        #expect(source.contains("maximumOpticalFlowFrameRate"))
        #expect(source.contains("videoCompositionFrameRate(for: exportSettings, clips: clips)"))
        #expect(source.contains("sourceTrackIDForFrameTiming = kCMPersistentTrackID_Invalid"))
        #expect(source.contains("useOpticalFlow: clip.useOpticalFlow"))
        #expect(source.contains("playbackRate: playbackRate"))
        #expect(source.contains("opticalFlowSlowMotionRate"))
    }
}
