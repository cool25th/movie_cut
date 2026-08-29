import Foundation
import MovieCutCore

/// User text style presets boundary of the EditorViewModel decomposition
/// (review 2026-08-28 #7 — boundary separation continues). Pure method moves
/// from the main file, no behavior change. The stored `userTextStylePresets`
/// state stays in the main class body (extensions cannot hold stored
/// properties).
extension EditorViewModel {
    // MARK: - User text style presets (F-12R)

    func loadUserTextStylePresets() {
        userTextStylePresets = UserTextStylePresetStore.load(from: UserTextStylePresetStore.defaultStoreURL())
    }

    /// Captures the selected text clip's style as a reusable preset.
    func saveSelectedTextStyleAsPreset() {
        guard let textContent = selectedClip?.textContent else {
            lastErrorMessage = "Select a text clip to save its style."
            return
        }

        let name = "My Style \(userTextStylePresets.count + 1)"
        let preset = UserTextStylePreset(name: name, capturing: textContent)
        userTextStylePresets.append(preset)
        persistUserTextStylePresets()
        lastStatusMessage = "Saved text style preset \"\(name)\"."
    }

    /// Applies a saved preset's style to the selected text clip.
    func applyUserTextStylePreset(_ preset: UserTextStylePreset) async {
        guard let textContent = selectedClip?.textContent else { return }
        await updateSelectedTextContent(preset.applying(to: textContent))
        lastStatusMessage = "Applied text style preset \"\(preset.name)\"."
    }

    func deleteUserTextStylePreset(_ presetId: UUID) {
        userTextStylePresets.removeAll { $0.id == presetId }
        persistUserTextStylePresets()
    }

    private func persistUserTextStylePresets() {
        do {
            try UserTextStylePresetStore.save(
                userTextStylePresets,
                to: UserTextStylePresetStore.defaultStoreURL()
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
