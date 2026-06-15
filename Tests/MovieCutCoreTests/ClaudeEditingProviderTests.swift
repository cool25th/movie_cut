import Foundation
import Testing
@testable import MovieCutCore

@Suite("Claude Editing Provider")
struct ClaudeEditingProviderTests {
    /// A transport that returns a canned response or throws a canned error.
    private struct StubTransport: ClaudeMessagesTransport {
        var response: Data?
        var error: AIEditingError?
        var capturedBody: UncheckedBox<Data?> = UncheckedBox(nil)

        func complete(requestBody: Data, apiKey: String) async throws -> Data {
            capturedBody.value = requestBody
            if let error { throw error }
            return response ?? Data()
        }
    }

    /// Mutable capture box for the request body (StubTransport is a value type).
    private final class UncheckedBox<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func messagesResponse(planJSON: String, stopReason: String = "end_turn") -> Data {
        // Build the envelope with JSONSerialization so the inner text is escaped correctly.
        let envelope: [String: Any] = [
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "stop_reason": stopReason,
            "content": [["type": "text", "text": planJSON]]
        ]
        return (try? JSONSerialization.data(withJSONObject: envelope)) ?? Data()
    }

    // MARK: - Request building

    @Test("Request body targets the Opus model with a JSON-schema format and adaptive thinking")
    func requestBodyContract() throws {
        let context = AIEditContext(videoClipCount: 2, audioClipCount: 1, textClipCount: 0, hasSelection: true)
        let body = try ClaudeEditPlanCodec.makeRequestBody(instruction: "make it brighter", context: context)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(object["model"] as? String == "claude-opus-4-8")
        #expect((object["thinking"] as? [String: Any])?["type"] as? String == "adaptive")

        let outputConfig = try #require(object["output_config"] as? [String: Any])
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["schema"] != nil)

        let messages = try #require(object["messages"] as? [[String: Any]])
        let userContent = try #require(messages.first?["content"] as? String)
        #expect(userContent.contains("make it brighter"))
        #expect(userContent.contains("2 video clip"))
    }

    // MARK: - Response parsing

    @Test("A structured response decodes into mapped intents")
    func parsePlan() throws {
        let response = messagesResponse(planJSON: """
        {"summary":"Brighten all video","actions":[{"target":"videoClips","kind":"adjustBrightness","amount":0.3}]}
        """)
        let plan = try ClaudeEditPlanCodec.parsePlan(from: response)

        #expect(plan.summary == "Brighten all video")
        #expect(plan.intents == [AssistantIntent(target: .videoClips, action: .adjustBrightness(0.3))])
    }

    @Test("Action mapping covers every supported kind")
    func mapsAllActions() {
        func intent(_ dict: [String: Any]) -> AssistantIntent? {
            ClaudeEditPlanCodec.mapIntent(from: dict)
        }

        #expect(intent(["target": "allClips", "kind": "applyFilter", "filter": "cinematicLUT"])
            == AssistantIntent(target: .allClips, action: .applyFilter(.cinematicLUT)))
        #expect(intent(["target": "allClips", "kind": "removeFilters"])
            == AssistantIntent(target: .allClips, action: .removeFilters))
        #expect(intent(["target": "audioClips", "kind": "setVolume", "amount": 0.5])
            == AssistantIntent(target: .audioClips, action: .setVolume(0.5)))
        #expect(intent(["target": "audioClips", "kind": "setFade", "amount": 1.5])
            == AssistantIntent(target: .audioClips, action: .setFade(1.5)))
        #expect(intent(["target": "audioClips", "kind": "removeFade"])
            == AssistantIntent(target: .audioClips, action: .removeFade))
        #expect(intent(["target": "videoClips", "kind": "adjustContrast", "amount": -0.2])
            == AssistantIntent(target: .videoClips, action: .adjustContrast(-0.2)))
        #expect(intent(["target": "videoClips", "kind": "adjustSaturation", "amount": 0.4])
            == AssistantIntent(target: .videoClips, action: .adjustSaturation(0.4)))
        #expect(intent(["target": "selection", "kind": "addMarker"])
            == AssistantIntent(target: .selection, action: .addMarker))
    }

    @Test("Out-of-range amounts are clamped during mapping")
    func clampsAmounts() {
        #expect(ClaudeEditPlanCodec.mapIntent(from: ["target": "allClips", "kind": "adjustBrightness", "amount": 5.0])
            == AssistantIntent(target: .allClips, action: .adjustBrightness(1.0)))
        #expect(ClaudeEditPlanCodec.mapIntent(from: ["target": "audioClips", "kind": "setVolume", "amount": 9.0])
            == AssistantIntent(target: .audioClips, action: .setVolume(2.0)))
    }

    @Test("Unmappable actions are dropped and an empty plan throws")
    func emptyPlanThrows() {
        let response = messagesResponse(planJSON: """
        {"summary":"nothing supported","actions":[{"target":"allClips","kind":"teleport"}]}
        """)
        #expect(throws: AIEditingError.noApplicableActions) {
            try ClaudeEditPlanCodec.parsePlan(from: response)
        }
    }

    @Test("A refusal stop reason throws a malformed-response error")
    func refusalThrows() {
        let response = messagesResponse(planJSON: "{}", stopReason: "refusal")
        #expect(throws: AIEditingError.self) {
            try ClaudeEditPlanCodec.parsePlan(from: response)
        }
    }

    // MARK: - Provider end-to-end (mock transport)

    @Test("Provider plans end-to-end through a mock transport")
    func providerPlansEndToEnd() async throws {
        let transport = StubTransport(response: messagesResponse(planJSON: """
        {"summary":"Mute music","actions":[{"target":"audioClips","kind":"setVolume","amount":0}]}
        """))
        let provider = ClaudeEditingProvider(transport: transport) { "test-key" }

        #expect(provider.isAvailable)
        let plan = try await provider.plan(for: "mute the music", context: .empty)
        #expect(plan.intents == [AssistantIntent(target: .audioClips, action: .setVolume(0))])
        #expect(transport.capturedBody.value != nil)
    }

    @Test("Provider without an API key is unavailable and throws")
    func providerMissingKey() async {
        let provider = ClaudeEditingProvider(transport: StubTransport()) { nil }
        #expect(provider.isAvailable == false)
        await #expect(throws: AIEditingError.missingAPIKey) {
            try await provider.plan(for: "anything", context: .empty)
        }
    }

    @Test("Provider propagates transport HTTP errors")
    func providerPropagatesHTTPError() async {
        let transport = StubTransport(error: .http(status: 401, body: "unauthorized"))
        let provider = ClaudeEditingProvider(transport: transport) { "bad-key" }
        await #expect(throws: AIEditingError.self) {
            try await provider.plan(for: "anything", context: .empty)
        }
    }

    // MARK: - Rule-based fallback

    @Test("Rule-based provider recognizes and rejects instructions offline")
    func ruleBasedFallback() async throws {
        let provider = RuleBasedEditingProvider()
        #expect(provider.isAvailable)

        let plan = try await provider.plan(for: "convert all clips to black and white", context: .empty)
        #expect(plan.intents == [AssistantIntent(target: .allClips, action: .applyFilter(.grayscale))])

        await #expect(throws: AIEditingError.noApplicableActions) {
            try await provider.plan(for: "qwzx nonsense", context: .empty)
        }
    }
}
