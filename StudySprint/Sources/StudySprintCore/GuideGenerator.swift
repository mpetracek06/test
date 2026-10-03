import Foundation

/// What the live research screen shows while a guide is being built.
public enum ResearchEvent: Equatable, Sendable {
    case phase(String)
    case searching(String)
    case found([SearchHit])
    case note(String)
    case writing(characters: Int)
    case fallback(String)
}

public struct GuideGenerator {
    public var client: AnthropicClient

    public init(client: AnthropicClient) {
        self.client = client
    }

    private final class Counter { var characters = 0; var lastReported = 0 }

    public func generate(
        _ request: GuideRequest,
        onEvent: @escaping @MainActor (ResearchEvent) -> Void
    ) async throws -> StudyGuide {
        var messages: [JSON] = [["role": "user", "content": Prompts.guideUserContent(request)]]
        var cost = CostEstimator.Tally(model: client.model)
        var answer = ""
        var hits: [SearchHit] = []
        let counter = Counter()

        await onEvent(.phase("Reading your notes…"))

        // Web search runs in a server-side loop. A long research turn can return `pause_turn`;
        // we resume by sending the partial assistant turn back unchanged.
        for round in 0..<6 {
            if round > 0 { await onEvent(.phase("Continuing research…")) }
            let body: JSON = [
                "max_tokens": 32000,
                "system": Prompts.guideSystem,
                "thinking": ["type": "adaptive", "display": "updates"],
                "output_config": ["effort": request.depth.effort],
                "fallbacks": "default",
                "tools": [[
                    "type": "web_search_20260209",
                    "name": "web_search",
                    "max_uses": request.depth.maxSearches,
                ] as JSON],
                "messages": messages,
                // Caches the prompt so a paused research turn resumes cheaply.
                "cache_control": ["type": "ephemeral"],
            ]

            let message = try await client.stream(
                body,
                betas: [AnthropicClient.fallbackBeta, AnthropicClient.progressUpdatesBeta]
            ) { update in
                switch update {
                case .started:
                    onEvent(.phase("Researching…"))
                case .searchQuery(let q):
                    onEvent(.searching(q))
                case .searchResults(let found):
                    onEvent(.found(found))
                case .progressNote(let note):
                    onEvent(.note(note))
                case .fallback(let model):
                    onEvent(.fallback(model))
                case .text(let t):
                    counter.characters += t.count
                    if counter.characters - counter.lastReported >= 120 {
                        counter.lastReported = counter.characters
                        onEvent(.writing(characters: counter.characters))
                    }
                }
            }

            cost.add(message)
            try message.throwIfRefused()
            hits += message.searchHits
            answer += message.text

            if message.stopReason == "pause_turn" {
                messages.append(["role": "assistant", "content": message.contentForEcho])
                continue
            }
            break
        }

        await onEvent(.phase("Assembling your sprint…"))
        if let payload = GuidePayload.decode(from: answer) {
            var guide = payload.toGuide(request: request, searchHits: hits)
            guide.buildCost = cost.dollars
            return guide
        }

        // Rare: the answer didn't contain clean JSON. Reformat it with structured outputs.
        await onEvent(.phase("Tidying up the format…"))
        let repairBody: JSON = [
            "max_tokens": 32000,
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": GuidePayload.schema] as JSON,
            ] as JSON,
            "messages": [[
                "role": "user",
                "content": "Convert this study guide into the required JSON. Keep every video URL exactly as written; do not add new ones.\n\n" + answer,
            ]],
        ]
        let repaired = try await client.stream(repairBody) { _ in }
        cost.add(repaired)
        try repaired.throwIfRefused()
        guard let data = repaired.text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(GuidePayload.self, from: data) else {
            throw APIError.unparseable
        }
        var guide = payload.toGuide(request: request, searchHits: hits)
        guide.buildCost = cost.dollars
        return guide
    }
}
