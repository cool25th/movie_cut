import Foundation
import MovieCutCore

/// Crash-recovery and periodic named-file autosave boundary of the
/// EditorViewModel decomposition, plus export media-reachability preflight.
/// Pure method moves from `EditorViewModel.swift`; stored `@Observable`
/// state (`currentProjectURL`, `isSavingCurrentProject`, `autosaveFailureMessage`,
/// and coalescing flags) remains in the main class body.
extension EditorViewModel {
    // MARK: - Crash-recovery debounced autosave

    func scheduleAutosave() {
        // A no-op re-publish of identical content skips the write entirely.
        if let lastAutosavedProject, lastAutosavedProject == currentProject, !autosaveSaveInFlight {
            return
        }
        pendingAutosaveTask?.cancel()
        pendingAutosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000) // 0.75 s debounce
            guard !Task.isCancelled else { return }
            await self?.performAutosave()
        }
    }

    /// Serial, latest-snapshot-wins autosave. Recommitted after an in-flight
    /// save when an edit landed mid-save (autosaveDirty).
    func performAutosave() async {
        if autosaveSaveInFlight {
            autosaveDirty = true
            return
        }
        let snapshot = currentProject
        if let lastAutosavedProject, lastAutosavedProject == snapshot {
            autosaveDirty = false
            return
        }
        autosaveSaveInFlight = true
        defer { autosaveSaveInFlight = false }
        do {
            try await projectStore.saveAutosave(snapshot)
            lastAutosavedProject = snapshot
            autosaveSaveSucceeded()
        } catch {
            autosaveSaveFailed(FileOperationError.classify(error))
        }
        if autosaveDirty {
            autosaveDirty = false
            await performAutosave()
        }
    }

    /// Awaitable autosave flush (used by automation to deterministically persist
    /// recovery state before quitting; same path as the edit-driven autosave).
    /// Cancels any pending debounced save and writes the latest snapshot now.
    func flushAutosave() async {
        pendingAutosaveTask?.cancel()
        pendingAutosaveTask = nil
        await performAutosave()
    }

    private func autosaveSaveSucceeded() {
        guard autosaveFailureMessage != nil || consecutiveAutosaveFailures > 0 else { return }
        consecutiveAutosaveFailures = 0
        autosaveFailureMessage = nil
    }

    private func autosaveSaveFailed(_ failure: FileOperationError) {
        consecutiveAutosaveFailures += 1
        autosaveFailureMessage = String(
            format: NSLocalizedString(
                "Autosave failed: %@. Changes are not being backed up for crash recovery — check free disk space.",
                comment: "Warning shown when the crash-recovery autosave cannot be written"
            ),
            failure.userMessage
        )
    }

    /// A project recovered from a non-clean previous session, if any.
    func recoverableProject() async -> Project? {
        await projectStore.loadAutosaveIfAvailable()
    }

    /// The reason a recovery file existed but could not be loaded (corrupt),
    /// if the last `recoverableProject()` call hit that case. The launch flow
    /// surfaces this so the user is told their recovery file was damaged
    /// instead of the previous silent `try?` swallow.
    func autosaveLoadFailure() async -> FileOperationError? {
        await projectStore.lastAutosaveLoadFailure
    }

    /// When the crash-recovery autosave was last written, for the launch
    /// recovery prompt's identification line (project name + backup time).
    func recoverableAutosaveDate() async -> Date? {
        await projectStore.autosaveModificationDate()
    }

    /// Removes the crash-recovery autosave (clean quit or after a manual save).
    func clearRecoveryAutosave() async {
        await projectStore.clearAutosave()
    }

    // MARK: - Periodic project autosave (named-file durability)
    //
    // This 30s timer writes the current project to a NAMED file
    // (Application Support/MovieCut/Autosave/<name>-<uuid>.moviecut) every 30s
    // so a long unsaved session is durable on disk. It is DISTINCT from the
    // crash-recovery path in ProjectStore (recovery.moviecut, written on every
    // edit via scheduleAutosave): that one is a single rolling recovery
    // snapshot offered on next launch; this one is a per-project durable copy.
    // Both paths go through ProjectStore.save, so both now surface classified
    // FileOperationError messages (e.g. disk-full) instead of raw strings.
    // The harness calls stopAutoSave() to make export/reload deterministic.

    func startAutoSave() {
        guard !isAutoSaveRunning else { return }

        isAutoSaveRunning = true
        scheduleNextAutoSave()
    }

    func stopAutoSave() {
        isAutoSaveRunning = false
    }

    func scheduleNextAutoSave() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }

            self.saveCurrentProject()
            if self.isAutoSaveRunning {
                self.scheduleNextAutoSave()
            }
        }
    }

    func defaultAutoSaveURL(for project: Project) -> URL {
        // Routes through the project store so an injected test autosave
        // directory isolates the NAMED autosave too (the 30 s timer below
        // outlives short tests in lingering hosts — CRASH_DIAGNOSIS_20261005
        // §3). The store's default equals the previous hardcoded path.
        let baseDirectory = projectStore.namedAutosaveDirectory
            ?? FileManager.default.temporaryDirectory

        let sanitizedName = project.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let fileName = sanitizedName.isEmpty ? "Untitled" : sanitizedName

        return baseDirectory
            .appendingPathComponent("Autosave", isDirectory: true)
            .appendingPathComponent("\(fileName)-\(project.id.uuidString).moviecut")
    }

    /// BUG-04 (CA-03 audit): export/package pre-flight. Missing-media
    /// detection and the relink prompt only run at project OPEN — a disk
    /// ejected mid-session used to fail the export minutes into the render.
    /// Re-evaluate reachability NOW and refuse explicitly with relink
    /// guidance before any render work starts.
    func ensureAllMediaReachableForExport() -> Bool {
        evaluateMissingMedia(in: currentProject)
        guard !missingMediaAssets.isEmpty else { return true }
        lastExportURL = nil
        lastStatusMessage = nil
        lastErrorMessage = String(
            format: NSLocalizedString(
                "Can't export: %d media file(s) can't be found. Use “Re-link Missing Media” to locate them, then export again.",
                comment: "Export pre-flight refusal when source media is unreachable"
            ),
            missingMediaAssets.count
        )
        return false
    }
}
