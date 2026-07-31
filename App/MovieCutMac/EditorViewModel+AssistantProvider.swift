import Foundation
import MovieCutCore

// MARK: - Assistant provider wiring (F-21, requirement 10.3)

// The assistant UI reaches the editor through the `AIEditingProvider` protocol.
// `RuleBasedEditingProvider` (Core) wraps the existing `AssistantCommandParser`
// → `AssistantIntent` path, so this is a protocol seam inserted into the existing
// flow, not a new execution path. The intents the provider returns are dispatched
// through the same `executeAssistantIntent` used by the legacy direct-parse path.

extension EditorViewModel {

    /// The editing provider the assistant UI routes through.
    ///
    /// `RuleBasedEditingProvider` is a stateless value type, so a fresh instance per
    /// call is fine and avoids stored-property restrictions on extensions. It needs
    /// no network access and is deterministic (requirement 10.3 acceptance 4).
    private var assistantEditingProvider: any AIEditingProvider { RuleBasedEditingProvider() }

    /// Builds the lightweight project context handed to an `AIEditingProvider`.
    /// The rule-based provider does not read it, but populating it keeps the seam
    /// meaningful for any future provider swap-in.
    private func assistantContext() -> AIEditContext {
        let clips = currentProject.timeline.tracks.flatMap(\.clips)
        return AIEditContext(
            videoClipCount: clips.filter { $0.kind == .video || $0.kind == .image }.count,
            audioClipCount: clips.filter { $0.kind == .audio }.count,
            textClipCount: clips.filter { $0.kind == .text }.count,
            hasSelection: !selectedClipIds.isEmpty
        )
    }

    /// Runs a natural-language instruction via `AIEditingProvider` and applies the
    /// resulting plan to the timeline through the existing intent executor.
    ///
    /// The provider is the primary path. When it reports no applicable action
    /// (`AIEditingError.noApplicableActions`), the suggestion list from the parser
    /// is surfaced so the user-visible "try one of the examples" UX is preserved.
    func executeAssistantPlan(for text: String) async {
        assistantResultMessage = nil
        assistantSuggestions = []

        do {
            let plan = try await assistantEditingProvider.plan(for: text, context: assistantContext())
            for intent in plan.intents {
                await executeAssistantIntent(intent)
            }
            // The intent executor sets its own result message on success/no-op.
            // Keep suggestions clear when the plan ran.
            assistantSuggestions = []
        } catch AIEditingError.noApplicableActions {
            // Fall back to the parser's suggestions to preserve the existing UX.
            if case .unrecognized(let suggestions) = AssistantCommandParser.parse(text) {
                assistantSuggestions = suggestions
            }
            assistantResultMessage = "I couldn't map that to an edit. Try one of the examples."
            lastStatusMessage = nil
        } catch {
            assistantResultMessage = error.localizedDescription
            lastStatusMessage = nil
        }
    }
}
