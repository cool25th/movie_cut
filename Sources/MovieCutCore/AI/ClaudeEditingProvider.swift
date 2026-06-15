import Foundation

/// Transport that POSTs a Claude Messages API request body and returns the raw
/// HTTP response body. Abstracted so request building, response parsing, and
/// intent mapping are unit-testable without a network call.
public protocol ClaudeMessagesTransport: Sendable {
    /// Sends an encoded Messages API request body using the supplied API key and
    /// returns the raw response body.
    func complete(requestBody: Data, apiKey: String) async throws -> Data
}

/// A `URLSession`-backed Claude Messages transport (raw HTTP — the official SDK
/// has no Swift target).
public struct URLSessionClaudeTransport: ClaudeMessagesTransport {
    private let endpoint: URL
    private let anthropicVersion: String
    private let session: URLSession

    /// Creates a URLSession transport.
    public init(
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        anthropicVersion: String = "2023-06-01",
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.anthropicVersion = anthropicVersion
        self.session = session
    }

    public func complete(requestBody: Data, apiKey: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = requestBody

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIEditingError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIEditingError.transport("Missing HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIEditingError.http(
                status: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }
}

/// Builds Claude Messages API request bodies and parses responses for the
/// natural-language → edit-plan task. Pure and side-effect free so both halves
/// are unit-testable.
public enum ClaudeEditPlanCodec {
    /// The model used for edit planning (per the Anthropic model catalog).
    public static let model = "claude-opus-4-8"

    /// The Anthropic API version header value.
    public static let anthropicVersion = "2023-06-01"

    /// System prompt instructing the model to act as a deterministic editing planner.
    public static let systemPrompt = """
    You are the editing planner for a video editor. Convert the user's instruction \
    into a JSON edit plan that the editor can apply. Only use the supported actions \
    and targets in the schema. Pick the most specific target. Use signed amounts \
    between -1 and 1 for adjustments (positive increases, negative decreases), a \
    0...2 fraction for setVolume, and seconds for setFade. If the instruction is not \
    a supported edit, return an empty actions array and explain why in the summary.
    """

    /// The JSON schema for the structured `output_config.format` response.
    public static var responseSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "summary": ["type": "string"],
                "actions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "target": [
                                "type": "string",
                                "enum": ["selection", "allClips", "videoClips", "audioClips", "textClips"]
                            ],
                            "kind": [
                                "type": "string",
                                "enum": [
                                    "applyFilter", "removeFilters", "setVolume", "setFade",
                                    "removeFade", "adjustBrightness", "adjustContrast",
                                    "adjustSaturation", "addMarker"
                                ]
                            ],
                            "amount": ["type": "number"],
                            "filter": [
                                "type": "string",
                                "enum": ["grayscale", "cinematicLUT", "vintageLUT", "noirLUT", "vividLUT", "coolLUT", "sepia", "blur"]
                            ]
                        ],
                        "required": ["target", "kind"]
                    ]
                ]
            ],
            "required": ["summary", "actions"]
        ]
    }

    /// Builds the Messages API request body for an instruction.
    public static func makeRequestBody(instruction: String, context: AIEditContext) throws -> Data {
        let userContent = "\(context.promptDescription)\n\nInstruction: \(instruction)"
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": systemPrompt,
            "thinking": ["type": "adaptive"],
            "output_config": [
                "format": [
                    "type": "json_schema",
                    "schema": responseSchema
                ]
            ],
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Parses a Messages API response body into an ``AIEditPlan``.
    public static func parsePlan(from responseData: Data) throws -> AIEditPlan {
        guard let root = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw AIEditingError.malformedResponse("Response was not a JSON object")
        }

        if let stopReason = root["stop_reason"] as? String, stopReason == "refusal" {
            throw AIEditingError.malformedResponse("The model refused the request")
        }

        guard let content = root["content"] as? [[String: Any]] else {
            throw AIEditingError.malformedResponse("Response had no content array")
        }
        guard let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let planData = text.data(using: .utf8),
              let planObject = try? JSONSerialization.jsonObject(with: planData) as? [String: Any] else {
            throw AIEditingError.malformedResponse("Response text was not a JSON edit plan")
        }

        let summary = planObject["summary"] as? String ?? ""
        let actionDictionaries = planObject["actions"] as? [[String: Any]] ?? []
        let intents = actionDictionaries.compactMap(mapIntent(from:))

        guard !intents.isEmpty else {
            throw AIEditingError.noApplicableActions
        }
        return AIEditPlan(summary: summary, intents: intents)
    }

    /// Maps one decoded action dictionary into an ``AssistantIntent``.
    static func mapIntent(from dictionary: [String: Any]) -> AssistantIntent? {
        guard let targetRaw = dictionary["target"] as? String,
              let target = AssistantTarget(rawValue: targetRaw),
              let kind = dictionary["kind"] as? String else {
            return nil
        }

        let amount = (dictionary["amount"] as? NSNumber)?.doubleValue
        let filter = (dictionary["filter"] as? String).flatMap(effectType(from:))

        let action: AssistantAction?
        switch kind {
        case "applyFilter":
            action = filter.map(AssistantAction.applyFilter)
        case "removeFilters":
            action = .removeFilters
        case "setVolume":
            action = amount.map { AssistantAction.setVolume(min(max($0, 0), 2)) }
        case "setFade":
            action = amount.map { AssistantAction.setFade(max($0, 0)) }
        case "removeFade":
            action = .removeFade
        case "adjustBrightness":
            action = amount.map { AssistantAction.adjustBrightness(clampAdjustment($0)) }
        case "adjustContrast":
            action = amount.map { AssistantAction.adjustContrast(clampAdjustment($0)) }
        case "adjustSaturation":
            action = amount.map { AssistantAction.adjustSaturation(clampAdjustment($0)) }
        case "addMarker":
            action = .addMarker
        default:
            action = nil
        }

        return action.map { AssistantIntent(target: target, action: $0) }
    }

    private static func clampAdjustment(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }

    private static func effectType(from raw: String) -> EffectType? {
        switch raw {
        case "grayscale": return .grayscale
        case "cinematicLUT": return .cinematicLUT
        case "vintageLUT": return .vintageLUT
        case "noirLUT": return .noirLUT
        case "vividLUT": return .vividLUT
        case "coolLUT": return .coolLUT
        case "sepia": return .sepia
        case "blur": return .blur
        default: return nil
        }
    }
}

/// An ``AIEditingProvider`` backed by the Claude Messages API.
///
/// The model converts an instruction into a constrained JSON edit plan
/// (`output_config.format`), which maps onto the same ``AssistantIntent`` set the
/// rule-based parser produces. The network call is isolated behind
/// ``ClaudeMessagesTransport`` so planning logic is fully testable offline.
public struct ClaudeEditingProvider: AIEditingProvider {
    public let providerName = "Claude"

    private let transport: any ClaudeMessagesTransport
    private let apiKeyProvider: @Sendable () -> String?

    /// Creates a Claude editing provider.
    ///
    /// - Parameters:
    ///   - transport: The Messages API transport (defaults to URLSession).
    ///   - apiKeyProvider: Returns the current API key, or nil when unconfigured.
    public init(
        transport: any ClaudeMessagesTransport = URLSessionClaudeTransport(),
        apiKeyProvider: @escaping @Sendable () -> String?
    ) {
        self.transport = transport
        self.apiKeyProvider = apiKeyProvider
    }

    public var isAvailable: Bool {
        guard let key = apiKeyProvider() else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func plan(for instruction: String, context: AIEditContext) async throws -> AIEditPlan {
        guard let apiKey = apiKeyProvider(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIEditingError.missingAPIKey
        }

        let requestBody = try ClaudeEditPlanCodec.makeRequestBody(instruction: instruction, context: context)
        let responseData = try await transport.complete(requestBody: requestBody, apiKey: apiKey)
        return try ClaudeEditPlanCodec.parsePlan(from: responseData)
    }
}
