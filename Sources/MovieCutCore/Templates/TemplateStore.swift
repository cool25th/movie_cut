import Foundation
import os

/// In-memory store for available project templates.
public final class TemplateStore: Sendable {
    private let bundleStorage: OSAllocatedUnfairLock<[TemplateBundle]>

    /// Available template bundles.
    public private(set) var bundles: [TemplateBundle] {
        get {
            bundleStorage.withLock { $0 }
        }
        set {
            bundleStorage.withLock { $0 = newValue }
        }
    }

    /// Creates a template store.
    public init(bundles: [TemplateBundle] = []) {
        bundleStorage = OSAllocatedUnfairLock(initialState: bundles)
    }

    /// Adds or replaces a template bundle.
    public func add(_ bundle: TemplateBundle) {
        bundleStorage.withLock { bundleStorage in
            if let index = bundleStorage.firstIndex(where: { $0.identifier == bundle.identifier }) {
                bundleStorage[index] = bundle
            } else {
                bundleStorage.append(bundle)
            }
        }
    }

    /// Removes a template bundle by identifier.
    public func remove(id: String) {
        bundleStorage.withLock { bundleStorage in
            bundleStorage.removeAll { $0.identifier == id }
        }
    }

    /// Creates a new project from a template bundle.
    public func createProject(from bundle: TemplateBundle) -> Project {
        let tracks = bundle.tracks.enumerated().map { index, templateTrack in
            Track(
                kind: templateTrack.kind,
                name: templateTrack.name,
                zIndex: index,
                clips: clips(from: templateTrack.placeholderClips, textDefaults: bundle.textStyleDefaults)
            )
        }

        let timeline = Timeline(
            frameRate: rationalFrameRate(for: bundle.canvasPreset.frameRate),
            canvasSize: bundle.canvasPreset.size,
            aspectRatio: bundle.canvasPreset.aspectRatio,
            tracks: tracks
        )

        return Project(
            name: bundle.name,
            timeline: timeline,
            canvas: bundle.canvasPreset,
            exportSettings: bundle.exportPreset
        )
    }

    /// Returns templates bundled with MovieCut.
    public static func builtInTemplates() -> [TemplateBundle] {
        builtInTemplateBundles
    }

    private func clips(
        from templateClips: [TemplateClip],
        textDefaults: TextClipContent
    ) -> [Clip] {
        var timelineStart: TimeInterval = 0

        return templateClips.map { templateClip in
            let duration = max(0, templateClip.duration)
            let range = TimeRange(start: timelineStart, duration: duration)
            timelineStart += duration

            return Clip(
                kind: templateClip.kind,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: range,
                textContent: templateClip.kind == .text ? templateClip.textContent ?? textDefaults : nil,
                effects: templateClip.effects
            )
        }
    }

    private func rationalFrameRate(for frameRate: ExportFrameRate) -> Rational {
        switch frameRate {
        case .fps24:
            return Rational(numerator: 24, denominator: 1)
        case .fps30:
            return Rational(numerator: 30, denominator: 1)
        case .fps60:
            return Rational(numerator: 60, denominator: 1)
        }
    }
}
