import Foundation

/// Lightweight project context handed to an AI editing provider so the model can
/// ground its plan (how many clips of each kind exist, whether a clip is selected).
public struct AIEditContext: Sendable, Equatable {
    /// Number of video clips on the timeline.
    public var videoClipCount: Int
    /// Number of audio clips on the timeline.
    public var audioClipCount: Int
    /// Number of text/sticker clips on the timeline.
    public var textClipCount: Int
    /// Whether the user currently has a clip selected.
    public var hasSelection: Bool

    /// Creates an AI edit context.
    public init(
        videoClipCount: Int = 0,
        audioClipCount: Int = 0,
        textClipCount: Int = 0,
        hasSelection: Bool = false
    ) {
        self.videoClipCount = videoClipCount
        self.audioClipCount = audioClipCount
        self.textClipCount = textClipCount
        self.hasSelection = hasSelection
    }

    /// An empty context.
    public static let empty = AIEditContext()

    /// A compact human-readable description for the model prompt.
    public var promptDescription: String {
        "Timeline has \(videoClipCount) video clip(s), \(audioClipCount) audio clip(s), "
            + "\(textClipCount) text/sticker clip(s). A clip is \(hasSelection ? "" : "not ")currently selected."
    }
}

/// A structured editing plan produced from a natural-language instruction.
///
/// The plan reuses the existing ``AssistantIntent`` type so a provider's output
/// flows through the same command-application path as the rule-based
/// ``AssistantCommandParser`` — the AI provider is a drop-in upgrade, not a
/// parallel system.
public struct AIEditPlan: Sendable, Equatable {
    /// A short, user-facing summary of what the plan does.
    public var summary: String
    /// The ordered editing intents to apply.
    public var intents: [AssistantIntent]

    /// Creates an AI edit plan.
    public init(summary: String, intents: [AssistantIntent]) {
        self.summary = summary
        self.intents = intents
    }
}

/// Errors surfaced while producing an AI edit plan.
public enum AIEditingError: Error, Sendable, Equatable {
    /// The instruction did not map to an applicable editing action.
    case noApplicableActions
}

/// A provider that maps a natural-language instruction to a structured
/// ``AIEditPlan``. Conformers may be rule-based or model-backed.
public protocol AIEditingProvider: Sendable {
    /// User-visible provider name.
    var providerName: String { get }

    /// Whether the provider can run in the current environment (e.g. has an API key).
    var isAvailable: Bool { get }

    /// Produces an edit plan for the instruction within the supplied context.
    func plan(for instruction: String, context: AIEditContext) async throws -> AIEditPlan
}

/// An ``AIEditingProvider`` backed by the existing rule-based parser.
///
/// This lets the same plan/apply UI fall back to fully offline, deterministic
/// behavior when no model is configured.
public struct RuleBasedEditingProvider: AIEditingProvider {
    public let providerName = "Rule-based"
    public let isAvailable = true

    /// Creates a rule-based editing provider.
    public init() {}

    public func plan(for instruction: String, context: AIEditContext) async throws -> AIEditPlan {
        switch AssistantCommandParser.parse(instruction) {
        case let .recognized(intent):
            return AIEditPlan(summary: instruction, intents: [intent])
        case .unrecognized:
            throw AIEditingError.noApplicableActions
        }
    }
}
