import AppKit
import Foundation
import MovieCutCore
import UniformTypeIdentifiers

// Export boundary of the EditorViewModel decomposition (roadmap step 8, the
// final listed boundary: timeline → selection → transport → inspector →
// media → effects[blocked] → audio → EXPORT). Pure method moves — no
// behavior change.
//
// Deliberately NOT moved (pure-move rule — private members): the export
// entry family (exportProject()/exportProject(to:), exportWithExplicitBitrate,
// exportProResMaster, exportHDRMaster, exportAudioOnly, exportAnimatedGIF,
// exportStillFrame — all read the private backgroundRemovedClipIds stored
// state and the private reconciledExportSettingsFromLegacyUI helper) and
// applyExportPreset (private reportQuickToolSuccess). Same access-
// normalization prerequisite as the other blocked boundaries.
extension EditorViewModel {

    // MARK: - CA-30 diagnostics funnel helpers (secondary export routes)

    /// Marks an export attempt in the local beta diagnostics funnel. Call
    /// once the export is actually starting (after the save panel resolves —
    /// a cancelled panel is no attempt, so it records nothing).
    @discardableResult
    func beginDiagnosticsExport() async -> Date {
        await betaDiagnostics.record(.exportStart)
        return Date()
    }

    /// Closes the funnel event: success with wall duration, or failure with
    /// the error's machine type name.
    func endDiagnosticsExport(started: Date, error: (any Error)? = nil) async {
        if let error {
            await betaDiagnostics.record(
                .exportFail,
                errorCode: String(describing: Swift.type(of: error))
            )
        } else {
            await betaDiagnostics.record(
                .exportSuccess,
                durationMs: Int(Date().timeIntervalSince(started) * 1000)
            )
        }
    }

    /// Exports the current project and its media as a `.mctemplate` package.
    func exportProjectPackage() async {
        guard ensureAllMediaReachableForExport() else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name).\(ProjectPackage.fileExtension)"
        if let type = UTType(filenameExtension: ProjectPackage.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let snapshot = await session.snapshot()
            try ProjectPackage.export(snapshot, to: url)
            lastErrorMessage = nil
            lastStatusMessage = "Exported project package to \(url.lastPathComponent)."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = "Could not export package: \(error.localizedDescription)"
        }
    }

    func cancelExport() {
        exportEngine.cancelExport()
    }

    func updateExportSettings(
        resolution: ExportResolution? = nil,
        frameRate: ExportFrameRate? = nil,
        codec: ExportCodec? = nil,
        audioCodec: MovieCutCore.AudioCodec? = nil,
        containerFormat: ExportContainerFormat? = nil,
        quality: ExportQuality? = nil,
        videoBitrateMbps: Int? = nil
    ) async {
        var settings = currentProject.exportSettings
        settings.resolution = resolution ?? settings.resolution
        settings.frameRate = frameRate ?? settings.frameRate
        settings.codec = codec ?? settings.codec
        settings.audioCodec = audioCodec ?? settings.audioCodec
        settings.containerFormat = containerFormat ?? settings.containerFormat
        if let quality {
            settings.quality = quality
            if quality != .custom {
                settings.videoBitrateMbps = nil
            }
        }
        if let videoBitrateMbps {
            settings.videoBitrateMbps = min(max(videoBitrateMbps, 1), 200)
        }

        await apply(SetProjectExportSettingsCommand(exportSettings: settings))
    }

    func applyPlatformExportPreset(_ preset: PlatformExportPreset) async {
        await applyExportPreset(
            named: preset.name,
            canvas: preset.canvas,
            exportSettings: preset.exportSettings
        )
    }
}

extension EditorViewModel {
    /// CA-30 2차: opt-in diagnostics export — copies the local JSONL funnel
    /// log to the pasteboard for a beta feedback attachment. The log never
    /// leaves the device on its own (offline contract).
    func copyBetaDiagnosticsToPasteboard() async {
        guard let contents = await betaDiagnostics.fileContents(), !contents.isEmpty else {
            lastErrorMessage = nil
            lastStatusMessage = NSLocalizedString(
                "No beta diagnostics recorded yet.", comment: "CA-30 export surface"
            )
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contents, forType: .string)
        lastStatusMessage = NSLocalizedString(
            "Copied beta diagnostics for feedback.", comment: "CA-30 export surface"
        )
    }
}
