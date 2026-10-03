import Foundation

struct GuideRequest {
    var notes: String
    var topicHint: String
    var budget: TimeBudget
    var level: StartingLevel
    var goal: LearningGoal
}

/// Talks to the Claude Messages API over plain HTTPS (there is no official Swift SDK).
/// Claude reads your notes, uses the server-side web search tool to find real videos,
/// and returns a time-boxed study plan as JSON.
struct ClaudeClient {
    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let apiKey: String

    enum ClientError: LocalizedError {
        case missingKey
        case http(Int, String)
        case refusal(String?)
        case unparseable

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Add your Anthropic API key in Settings (⌘,) first."
            case .http(let code, let message):
                return "Claude API error \(code): \(message)"
            case .refusal(let explanation):
                return "Claude declined this request." + (explanation.map { " \($0)" } ?? "")
            case .unparseable:
                return "Claude's answer couldn't be turned into a study guide. Try again."
            }
        }
    }

    // MARK: - Public

    func generateGuide(
        _ request: GuideRequest,
        status: @escaping @MainActor (String) -> Void
    ) async throws -> StudyGuide {
        guard !apiKey.isEmpty else { throw ClientError.missingKey }

        var messages: [[String: Any]] = [["role": "user", "content": Self.userPrompt(for: request)]]
        var answerText = ""
        var searchedURLs = Set<String>()

        // Web search runs in a server-side loop; long research can come back as `pause_turn`,
        // which we resume by sending the partial assistant turn back unchanged.
        for round in 0..<5 {
            await status(round == 0
                ? "Reading your notes and searching the web for the best videos…"
                : "Still researching… (round \(round + 1))")

            let body: [String: Any] = [
                "model": Self.model,
                "max_tokens": 16000,
                "system": Self.systemPrompt,
                "fallbacks": "default",
                "output_config": ["effort": "medium"],
                "tools": [["type": "web_search_20260209", "name": "web_search", "max_uses": 10] as [String: Any]],
                "messages": messages,
            ]
            let response = try await post(body, beta: "server-side-fallback-2026-07-01")
            let content = response["content"] as? [[String: Any]] ?? []
            Self.collect(content, text: &answerText, urls: &searchedURLs)

            let stopReason = response["stop_reason"] as? String
            if stopReason == "refusal" {
                let details = response["stop_details"] as? [String: Any]
                throw ClientError.refusal(details?["explanation"] as? String)
            }
            if stopReason == "pause_turn" {
                messages.append(["role": "assistant", "content": content])
                continue
            }
            break
        }

        await status("Building your study guide…")
        let payload: GuidePayload
        if let parsed = Self.decodePayload(from: answerText) {
            payload = parsed
        } else {
            await status("Tidying up the guide format…")
            payload = try await repair(answerText)
        }
        return payload.toGuide(request: request, searchedURLs: searchedURLs)
    }

    // MARK: - Prompts

    static let systemPrompt = """
    You are an expert learning coach whose single priority is helping the learner master a topic \
    in the LEAST amount of time. You build study sprints using evidence-based techniques: the \
    Pareto principle (teach the 20% of ideas that unlock 80% of understanding first), ordering \
    concepts by dependency, active recall, worked examples, and skipping anything not needed yet.

    Process:
    1. Read the learner's notes and figure out the topic and what they actually need to know.
    2. Use web search to find the best SHORT, high-quality videos for each step (YouTube preferred; \
    strong channels include 3Blue1Brown, Khan Academy, CrashCourse, StatQuest, The Organic Chemistry \
    Tutor, Professor Dave Explains, MIT OpenCourseWare, Fireship, Kurzgesagt — but pick whatever is \
    genuinely best for this topic). Search specifically, e.g. "<concept> explained youtube". Prefer \
    videos under 15 minutes. Never pad the plan with extra videos — at most 2 per step, and zero \
    when reading the explanation is faster.
    3. Only use video URLs that appeared in your search results. Never invent or guess a URL.
    4. Fit the whole plan inside the learner's time budget, including video time at the suggested \
    playback speed and time for recall practice. Fewer, sharper steps beat many shallow ones.

    Write explanations that are concrete and compact: plain language, one good example, no filler.

    When you are done researching, output the final guide as a single JSON object wrapped in \
    <guide_json></guide_json> tags, and nothing after the closing tag. Use exactly this shape:
    {
      "topic": "short topic name",
      "tldr": "2-3 sentence summary of the whole topic",
      "paretoConcepts": ["the few core ideas that unlock most of the topic"],
      "steps": [
        {
          "title": "step title",
          "minutes": 15,
          "why": "one sentence on why this step comes now",
          "explanation": "compact explanation with one concrete example",
          "keyPoints": ["must-remember facts"],
          "videos": [
            {"title": "exact video title", "url": "https://www.youtube.com/watch?v=...", \
    "channel": "channel name", "duration": "8:12", "watchTip": "e.g. Watch 1:30–7:45 at 1.5x"}
          ],
          "activeRecall": ["questions to answer from memory before moving on"]
        }
      ],
      "flashcards": [{"front": "question", "back": "answer"}],
      "commonMistakes": ["misconceptions and traps"],
      "skipList": ["things that are safe to skip for now, and why"],
      "selfTest": ["final questions that prove mastery"]
    }
    """

    static func userPrompt(for r: GuideRequest) -> String {
        """
        Time budget: \(r.budget.rawValue) minutes total.
        My level: \(r.level.rawValue).
        My goal: \(r.goal.rawValue).
        \(r.topicHint.isEmpty ? "" : "Topic: \(r.topicHint)\n")
        Build me the fastest possible study sprint for the material in my notes. Aim for 10–25 flashcards.

        <notes>
        \(r.notes)
        </notes>
        """
    }

    // MARK: - Networking

    private func post(_ body: [String: Any], beta: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 600 // research turns can take several minutes
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let beta { request.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        var delay: UInt64 = 2_000_000_000
        for attempt in 0..<3 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if code == 200 { return json }

            let retryable = code == 429 || code == 529 || code >= 500
            if retryable && attempt < 2 {
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
                continue
            }
            let message = (json["error"] as? [String: Any])?["message"] as? String
                ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClientError.http(code, message)
        }
        throw ClientError.http(0, "Request failed")
    }

    /// Fallback: convert a free-form answer into the guide JSON with structured outputs.
    private func repair(_ text: String) async throws -> GuidePayload {
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": Self.guideSchema] as [String: Any],
            ] as [String: Any],
            "messages": [[
                "role": "user",
                "content": "Convert this study guide into the required JSON. Keep every video URL exactly as written; do not add new ones.\n\n" + text,
            ]],
        ]
        let response = try await post(body)
        var out = ""
        var unused = Set<String>()
        Self.collect(response["content"] as? [[String: Any]] ?? [], text: &out, urls: &unused)
        guard let data = out.data(using: .utf8),
              let payload = try? JSONDecoder().decode(GuidePayload.self, from: data)
        else { throw ClientError.unparseable }
        return payload
    }

    // MARK: - Response handling

    /// Concatenates text blocks (citations split one answer into many blocks) and records
    /// every URL that came back from web search so we can flag invented links.
    static func collect(_ content: [[String: Any]], text: inout String, urls: inout Set<String>) {
        for block in content {
            switch block["type"] as? String {
            case "text":
                text += block["text"] as? String ?? ""
            case "web_search_tool_result":
                // On success `content` is a list of results; on error it is a single object.
                for result in block["content"] as? [[String: Any]] ?? [] {
                    if let url = result["url"] as? String { urls.insert(url) }
                }
            default:
                break
            }
        }
    }

    static func decodePayload(from text: String) -> GuidePayload? {
        var candidate = text
        if let start = text.range(of: "<guide_json>"),
           let end = text.range(of: "</guide_json>", range: start.upperBound..<text.endIndex) {
            candidate = String(text[start.upperBound..<end.lowerBound])
        }
        guard let first = candidate.firstIndex(of: "{"),
              let last = candidate.lastIndex(of: "}") else { return nil }
        let json = String(candidate[first...last])
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GuidePayload.self, from: data)
    }

    static let guideSchema: [String: Any] = {
        func obj(_ props: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": props, "required": Array(props.keys), "additionalProperties": false]
        }
        let str: [String: Any] = ["type": "string"]
        let strs: [String: Any] = ["type": "array", "items": str]
        let video = obj(["title": str, "url": str, "channel": str, "duration": str, "watchTip": str])
        let step = obj([
            "title": str, "minutes": ["type": "integer"], "why": str, "explanation": str,
            "keyPoints": strs, "videos": ["type": "array", "items": video] as [String: Any], "activeRecall": strs,
        ])
        return obj([
            "topic": str, "tldr": str, "paretoConcepts": strs,
            "steps": ["type": "array", "items": step] as [String: Any],
            "flashcards": ["type": "array", "items": obj(["front": str, "back": str])] as [String: Any],
            "commonMistakes": strs, "skipList": strs, "selfTest": strs,
        ])
    }()
}

// MARK: - Wire format

struct GuidePayload: Decodable {
    struct Video: Decodable { var title, url, channel, duration, watchTip: String }
    struct Step: Decodable {
        var title: String
        var minutes: Int
        var why, explanation: String
        var keyPoints: [String]
        var videos: [Video]
        var activeRecall: [String]
    }
    struct Card: Decodable { var front, back: String }

    var topic, tldr: String
    var paretoConcepts: [String]
    var steps: [Step]
    var flashcards: [Card]
    var commonMistakes, skipList, selfTest: [String]

    func toGuide(request: GuideRequest, searchedURLs: Set<String>) -> StudyGuide {
        let knownIDs = Set(searchedURLs.compactMap(YouTube.videoID(from:)))
        let knownURLs = Set(searchedURLs.map(YouTube.normalize))

        func resource(_ v: Video) -> VideoResource {
            let idMatch = YouTube.videoID(from: v.url).map { knownIDs.contains($0) } ?? false
            let verified = idMatch || knownURLs.contains(YouTube.normalize(v.url))
            // An unverified link might be made up, so send the learner to a search instead.
            let url = verified ? v.url : YouTube.searchURL(for: "\(v.title) \(v.channel)")
            return VideoResource(title: v.title, url: url, channel: v.channel, duration: v.duration,
                                 watchTip: v.watchTip, verified: verified)
        }

        return StudyGuide(
            topic: topic,
            timeBudgetMinutes: request.budget.rawValue,
            tldr: tldr,
            paretoConcepts: paretoConcepts,
            steps: steps.map {
                StudyStep(title: $0.title, minutes: $0.minutes, why: $0.why, explanation: $0.explanation,
                          keyPoints: $0.keyPoints, videos: $0.videos.map(resource), activeRecall: $0.activeRecall)
            },
            flashcards: flashcards.map { Flashcard(front: $0.front, back: $0.back) },
            commonMistakes: commonMistakes,
            skipList: skipList,
            selfTest: selfTest,
            sourceNotes: request.notes
        )
    }
}

enum YouTube {
    static func videoID(from string: String) -> String? {
        guard let comps = URLComponents(string: string), let host = comps.host?.lowercased() else { return nil }
        if host.hasSuffix("youtu.be") {
            return comps.path.split(separator: "/").first.map(String.init)
        }
        guard host.hasSuffix("youtube.com") else { return nil }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        let parts = comps.path.split(separator: "/").map(String.init)
        if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) { return parts[1] }
        return nil
    }

    static func normalize(_ string: String) -> String {
        var s = string.lowercased()
        for prefix in ["https://", "http://", "www.", "m."] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    static func searchURL(for query: String) -> String {
        var comps = URLComponents(string: "https://www.youtube.com/results")!
        comps.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return comps.url?.absoluteString ?? "https://www.youtube.com"
    }
}
