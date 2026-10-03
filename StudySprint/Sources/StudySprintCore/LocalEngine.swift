import Foundation

/// The free engine: an open model running on this Mac (via Ollama) plus free YouTube search.
/// Nothing is sent to a paid service, and nothing costs money.
///
/// Small local models do much better with several focused requests than with one huge one,
/// so a guide is written in passes: outline → each step → flashcards and extras.
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
        let images = request.attachments.filter { $0.kind == .image }.map(\.data)
        let counter = Counter()
        let progress: @MainActor (String) -> Void = { text in
            counter.characters += text.count
            if counter.characters - counter.lastReported >= 120 {
                counter.lastReported = counter.characters
                onEvent(.writing(characters: counter.characters))
            }
        }

        // Pass 1: outline.
        await onEvent(.phase("Planning the outline with \(backend.modelName) on your Mac…"))
        await onEvent(.note("Free mode: everything runs locally. The first run can take a minute while the model loads."))
        let outlineReply = try await backend.chat(
            system: Prompts.localOutlineSystem,
            messages: [LocalMessage(role: "user", content: Prompts.guideUser(request), images: images)],
            schema: LocalSchemas.outline, onText: progress)
        guard let outline = LocalEngine.parseJSONObject(outlineReply),
              let outlineSteps = outline["steps"] as? [JSON], !outlineSteps.isEmpty else {
            throw APIError.unparseable
        }
        let topic = outline["topic"] as? String ?? (request.topicHint.isEmpty ? "Study guide" : request.topicHint)
        let outlineText = Self.describe(outline: outline)
        await onEvent(.note("Outline ready: \(outlineSteps.count) steps."))

        // Pass 2: each step. The notes + outline prefix stays identical so the model reuses its cache.
        let context = Prompts.localContext(request: request, outline: outlineText)
        var steps: [JSON] = []
        for (i, s) in outlineSteps.enumerated() {
            try Task.checkCancellation()
            let title = s["title"] as? String ?? "Step \(i + 1)"
            await onEvent(.phase("Writing step \(i + 1) of \(outlineSteps.count): \(title)…"))
            let reply = try await backend.chat(
                system: Prompts.localStepSystem,
                messages: [LocalMessage(role: "user", content: context + Prompts.localStepInstruction(number: i + 1, title: title))],
                schema: LocalSchemas.stepDetail, onText: progress)
            var step = LocalEngine.parseJSONObject(reply) ?? [:]
            for key in ["title", "minutes", "why", "prerequisites"] { step[key] = s[key] }
            step["videoQuery"] = Self.videoQuery(s["videoQuery"] as? String ?? "", step: title, topic: topic)
            steps.append(step)
        }

        // Pass 3: flashcards, traps, self-test.
        try Task.checkCancellation()
        await onEvent(.phase("Making flashcards and a self-test…"))
        let extrasReply = try await backend.chat(
            system: Prompts.localExtrasSystem,
            messages: [LocalMessage(role: "user", content: context + "Now write the flashcards, common mistakes, memory aids, what's safe to skip, and final self-test questions.")],
            schema: LocalSchemas.extras, onText: progress)
        let extras = LocalEngine.parseJSONObject(extrasReply) ?? [:]

        var assembled = outline
        assembled["steps"] = steps
        for key in ["flashcards", "commonMistakes", "skipList", "mnemonics", "selfTest"] {
            assembled[key] = extras[key] ?? []
        }
        guard let data = try? JSONSerialization.data(withJSONObject: assembled),
              let payload = try? JSONDecoder().decode(GuidePayload.self, from: data), !payload.steps.isEmpty else {
            throw APIError.unparseable
        }
        var guide = payload.toGuide(request: request, searchHits: [])
        guide.buildCost = 0

        // Pass 4: a real video for each step, from free YouTube search.
        await onEvent(.phase("Finding videos on YouTube…"))
        var hits: [SearchHit] = []
        for (i, step) in payload.steps.enumerated() where i < guide.steps.count {
            try Task.checkCancellation()
            let query = step.videoQuery
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

    /// The model's search phrase if it's usable; otherwise one built from the step title.
    /// (Small models sometimes return a URL or nothing here.)
    static func videoQuery(_ raw: String, step: String, topic: String) -> String {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()
        let looksBroken = q.count < 4 || q.count > 90 || lower.contains("http") || lower.contains("www.")
            || lower.contains("youtube.com") || lower.contains("youtu.be")
        if !looksBroken { return q }
        let base = step.lowercased().contains(topic.lowercased()) ? step : "\(step) \(topic)"
        return "\(base) explained"
    }

    static func describe(outline: JSON) -> String {
        let steps = (outline["steps"] as? [JSON] ?? []).enumerated().map { i, s in
            "\(i + 1). \(s["title"] as? String ?? "") (\(s["minutes"] as? Int ?? 10) min) — \(s["why"] as? String ?? "")"
        }
        return """
        Topic: \(outline["topic"] as? String ?? "")
        Core ideas: \((outline["paretoConcepts"] as? [String] ?? []).joined(separator: "; "))
        Steps:
        \(steps.joined(separator: "\n"))
        """
    }

    // MARK: Tutor and structured calls

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

/// JSON schemas for the free engine's passes. Local models enforce these with a grammar,
/// including array lengths, so a small model can't return a one-step "plan".
enum LocalSchemas {
    static let str: JSON = ["type": "string"]
    static let int: JSON = ["type": "integer"]
    static func list(_ items: JSON, min: Int, max: Int) -> JSON {
        ["type": "array", "items": items, "minItems": min, "maxItems": max]
    }
    static func obj(_ props: [String: Any]) -> JSON {
        ["type": "object", "properties": props, "required": Array(props.keys).sorted(), "additionalProperties": false]
    }

    static let outline = obj([
        "topic": str, "emoji": str, "tldr": str,
        "paretoConcepts": list(str, min: 2, max: 5),
        "steps": list(obj([
            "title": str, "minutes": int, "why": str, "videoQuery": str,
            "prerequisites": list(int, min: 0, max: 4),
        ]), min: 3, max: 8),
    ])

    static let stepDetail = obj([
        "explanation": str, "analogy": str,
        "keyPoints": list(str, min: 2, max: 5),
        "activeRecall": list(str, min: 2, max: 3),
        "testOut": obj(["question": str, "answer": str]),
    ])

    static let extras = obj([
        "flashcards": list(obj(["front": str, "back": str]), min: 8, max: 25),
        "commonMistakes": list(str, min: 2, max: 5),
        "mnemonics": list(str, min: 0, max: 3),
        "skipList": list(str, min: 1, max: 4),
        "selfTest": list(str, min: 3, max: 5),
    ])
}
