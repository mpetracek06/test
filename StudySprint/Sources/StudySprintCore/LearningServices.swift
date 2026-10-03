import Foundation

/// The Claude engine: research with live web search, tutor chat, quizzes and grading via the Claude API.
public struct LearningServices: StudyEngine {
    public var client: AnthropicClient

    public init(client: AnthropicClient) {
        self.client = client
    }

    public var isFree: Bool { false }
    public var canSearchWeb: Bool { true }

    public func generateGuide(
        _ request: GuideRequest,
        onEvent: @escaping @MainActor (ResearchEvent) -> Void
    ) async throws -> StudyGuide {
        try await GuideGenerator(client: client).generate(request, onEvent: onEvent)
    }

    // MARK: - Tutor

    /// Streams a tutor reply. `history` must end with the learner's newest message.
    /// Assistant turns are replayed with their exact original content blocks so the
    /// conversation stays append-only (required for thinking blocks, and good for caching).
    public func tutorReply(
        system: String,
        history: [ChatTurn],
        onText: @escaping @MainActor (String) -> Void,
        onStatus: @escaping @MainActor (String) -> Void = { _ in }
    ) async throws -> ChatTurn {
        let messages = Self.tutorMessages(history)

        let body: JSON = [
            "max_tokens": 8000,
            "system": [[
                "type": "text",
                "text": system,
                "cache_control": ["type": "ephemeral"],
            ] as JSON],
            "output_config": ["effort": "low"],
            "fallbacks": "default",
            "tools": [["type": "web_search_20260209", "name": "web_search", "max_uses": 3] as JSON],
            "messages": messages,
        ]

        let message = try await client.stream(body, betas: [AnthropicClient.fallbackBeta]) { update in
            switch update {
            case .text(let t): onText(t)
            case .searchQuery(let q): onStatus("Searching: \(q)")
            case .fallback: onStatus("Switched to a fallback model")
            default: break
            }
        }
        try message.throwIfRefused()
        return ChatTurn(role: .assistant, text: message.text, rawContent: message.echoData)
    }

    /// Converts saved turns to API messages, replaying assistant turns with their exact original blocks.
    static func tutorMessages(_ history: [ChatTurn]) -> [JSON] {
        history.map { turn -> JSON in
            switch turn.role {
            case .user:
                return ["role": "user", "content": turn.text]
            case .assistant:
                if let raw = turn.rawContent,
                   let blocks = (try? JSONSerialization.jsonObject(with: raw)) as? [JSON], !blocks.isEmpty {
                    return ["role": "assistant", "content": blocks]
                }
                return ["role": "assistant", "content": turn.text.isEmpty ? "…" : turn.text]
            }
        }
    }

    // MARK: - Helpers

    public func structured(system: String, prompt: String, schema: JSON, effort: String) async throws -> JSON {
        let body: JSON = [
            "max_tokens": 16000,
            "system": system,
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema] as JSON,
            ] as JSON,
            "messages": [["role": "user", "content": prompt]],
        ]
        let message = try await client.stream(body) { _ in }
        try message.throwIfRefused()
        guard let json = (try? JSONSerialization.jsonObject(with: Data(message.text.utf8))) as? JSON else {
            throw APIError.unparseable
        }
        return json
    }
}
