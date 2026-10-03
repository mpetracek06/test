import Foundation

/// The free engine: an open model running on this Mac (via Ollama) plus free YouTube search.
/// Nothing is sent to a paid service, and nothing costs money.
public struct LocalEngine: StudyEngine {
    public var backend: ChatBackend
    public var videos: VideoFinder

    public init(backend: ChatBackend, videos: VideoFinder = YouTubeSearch()) {
        self.backend = backend
        self.videos = videos
    }

    public var isFree: Bool { true }
    public var canSearchWeb: Bool { false }

    private final class Counter { var characters = 0; var lastReported = 0 }

    public func generateGuide(
        _ request: GuideRequest,
        onEvent: @escaping @MainActor (ResearchEvent) -> Void
    ) async throws -> StudyGuide {
        await onEvent(.phase("Reading your notes on your Mac with \(backend.modelName)…"))
        await onEvent(.note("Free mode: everything runs locally. The first run can take a minute while the model loads."))

        let images = request.attachments.filter { $0.kind == .image }.map(\.data)
        let counter = Counter()
        let reply = try await backend.chat(
            system: Prompts.localGuideSystem,
            messages: [LocalMessage(role: "user", content: Prompts.guideUser(request), images: images)],
            schema: GuidePayload.localSchema
        ) { text in
            counter.characters += text.count
            if counter.characters - counter.lastReported >= 120 {
                counter.lastReported = counter.characters
                onEvent(.writing(characters: counter.characters))
            }
        }
        guard let payload = GuidePayload.decode(from: reply), !payload.steps.isEmpty else {
            throw APIError.unparseable
        }

        var guide = payload.toGuide(request: request, searchHits: [])
        guide.buildCost = 0

        // Find a real video for each step that asked for one.
        await onEvent(.phase("Finding videos on YouTube…"))
        var hits: [SearchHit] = []
        for (i, step) in payload.steps.enumerated() where i < guide.steps.count {
            try Task.checkCancellation()
            let query = step.videoQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { continue }
            await onEvent(.searching(query))
            guard let results = try? await videos.search(query, limit: 8), !results.isEmpty else { continue }
            let found = results.map { SearchHit(title: $0.title, url: $0.url) }
            hits += found
            await onEvent(.found(Array(found.prefix(5))))
            guide.steps[i].videos = YouTubeSearch.pickBest(results).map { v in
                VideoResource(title: v.title, url: v.url, channel: v.channel, duration: v.duration,
                              watchTip: "Top YouTube result for “\(query)”.",
                              playbackSpeed: v.seconds > 6 * 60 ? 1.25 : 1.0, verified: true)
            }
        }
        var seen = Set<String>()
        guide.sources = hits.filter { seen.insert($0.url).inserted }
        return guide
    }

    public func tutorReply(
        system: String,
        history: [ChatTurn],
        onText: @escaping @MainActor (String) -> Void,
        onStatus: @escaping @MainActor (String) -> Void
    ) async throws -> ChatTurn {
        let messages = history.map { LocalMessage(role: $0.role == .user ? "user" : "assistant", content: $0.text) }
        let reply = try await backend.chat(system: system, messages: messages, schema: nil, onText: onText)
        return ChatTurn(role: .assistant, text: reply)
    }

    public func structured(system: String, prompt: String, schema: JSON, effort: String) async throws -> JSON {
        let reply = try await backend.chat(system: system, messages: [LocalMessage(role: "user", content: prompt)],
                                           schema: schema, onText: nil)
        guard let json = Self.parseJSONObject(reply) else { throw APIError.unparseable }
        return json
    }

    /// Parses a JSON object, tolerating stray text or code fences around it.
    static func parseJSONObject(_ text: String) -> JSON? {
        if let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? JSON { return json }
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first < last else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(String(text[first...last]).utf8))) as? JSON
    }
}
